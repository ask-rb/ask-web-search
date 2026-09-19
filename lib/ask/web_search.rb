# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require_relative "web_search/version"

module Ask
  # Searches the web via a local SearXNG instance and returns the results
  # as clean, numbered markdown for LLM consumption. The capability layer:
  # one entry point (WebSearch.search) and a configurable endpoint. Tool
  # framing — name, parameter schema, result wrapping — lives with the
  # consumers (the MCP server, the agents) that call this library.
  module WebSearch
    # Search errors that carry engine diagnostics — the agent needs to
    # know *which* engines failed and *why* (CAPTCHA, timeout, suspended)
    # instead of just "No results found."
    class Error < StandardError; end

    # SearXNG answered but every engine failed (CAPTCHA, timeout,
    # suspended). The message lists which engines failed and why, plus
    # what the agent can try next.
    class AllEnginesFailedError < Error; end

    # Local SearXNG endpoint. Defaults to the standard local instance;
    # override with SEARXNG_URL or WebSearch.searxng_url=.
    def self.searxng_url
      @searxng_url || ENV.fetch("SEARXNG_URL", "http://localhost:8888")
    end

    def self.searxng_url=(url)
      @searxng_url = url
    end

    # Retry configuration. Set max_retries to 0 to disable retries.
    DEFAULT_MAX_RETRIES = 3
    RETRY_BACKOFF = [0.5, 1.0, 2.0].freeze

    # SearXNG's freshness windows — the valid values of its time_range
    # search parameter. Anything else is rejected up front, so a bad value
    # fails with a message listing these instead of silently searching
    # unfiltered.
    TIME_RANGES = %w[day week month year].freeze

    def self.max_retries
      return @max_retries if defined?(@max_retries)

      @max_retries = DEFAULT_MAX_RETRIES
    end

    def self.max_retries=(val)
      @max_retries = val
    end

    # Searches +query+ and returns the results as numbered markdown.
    # "No results found." only when SearXNG answered cleanly with zero
    # results and no engine failures. When engines failed, raises
    # AllEnginesFailedError with per-engine diagnostics (see
    # #format_engine_error). Raises on connection/HTTP failures — the
    # caller decides how to surface them.
    #
    # time_range: restricts results to a freshness window — one of
    # TIME_RANGES (day, week, month, year). With a window set, a clean
    # zero-result search says so ("No results found within the day
    # freshness window...") instead of a bare "No results found.", so the
    # agent widens the window rather than concluding the web is silent.
    # categories: scopes the search to a SearXNG vertical — e.g. "news"
    # or "science" (research papers); instances configure their own set,
    # so values pass through unvalidated. A string or anything Array-able
    # ("news,science" form).
    def self.search(query, time_range: nil, categories: nil)
      time_range = normalize_time_range(time_range)
      categories = normalize_categories(categories)
      response = search_raw(query, time_range: time_range, categories: categories)
      raise AllEnginesFailedError, format_engine_error(query, response, time_range: time_range) if response[:results].empty? &&
                                                                          response[:unresponsive].any?

      return format_results(response[:results]) unless response[:results].empty? && time_range

      "No results found within the #{time_range} freshness window. Retry with a broader time_range or without one."
    end

    # The raw result list: { url:, title:, content: } entries from the
    # results and infoboxes, deduplicated by url. Retries up to
    # max_retries times on connection/HTTP failures with exponential
    # backoff. Set max_retries to 0 to disable. See #search for
    # time_range / categories.
    def self.search_results(query, time_range: nil, categories: nil)
      search_raw(query, time_range: time_range, categories: categories)[:results]
    end

    # The full SearXNG response: { results: [...], unresponsive: [[name,
    # reason], ...] }. Same retry logic as #search_results, but preserves
    # the engine diagnostics the caller needs to explain an empty result.
    # time_range / categories are normalized here — the single point that
    # builds the request — and are idempotent, so callers may pass raw or
    # already-normalized values.
    def self.search_raw(query, time_range: nil, categories: nil)
      params = { q: query, format: "json" }
      params[:time_range] = normalize_time_range(time_range) if time_range
      params[:categories] = normalize_categories(categories) if categories
      uri = URI("#{searxng_url}/search")
      uri.query = URI.encode_www_form(params)
      retries = max_retries || 0
      attempt = 0
      begin
        attempt += 1
        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = 5
        http.read_timeout = 10
        req = Net::HTTP::Get.new(uri)
        req["User-Agent"] = "ask-web-search/#{Ask::WebSearch::VERSION}"
        res = http.request(req)
        raise "SearXNG returned #{res.code}: #{res.body}" unless res.code.start_with?("2")

        parse_response(JSON.parse(res.body))
      rescue StandardError
        raise if attempt > retries

        sleep RETRY_BACKOFF[[attempt - 1, RETRY_BACKOFF.size - 1].min]
        retry
      end
    end

    # Formats the engine failure into an actionable message: which engines
    # failed and why, plus what the agent can try next. Keeps the raw
    # SearXNG reason strings (CAPTCHA, timeout, suspended) — the caller
    # can see exactly what happened. When a freshness window was set, the
    # hint suggests broadening it.
    def self.format_engine_error(query, response, time_range: nil)
      lines = ["No search results for #{query.inspect} — all #{response[:unresponsive].size} engine(s) failed:"]
      response[:unresponsive].each do |name, reason|
        lines << "- #{name}: #{reason}"
      end
      hint = "Try: a simpler query, or ask-web-fetch for a known URL."
      hint = "Try: a simpler query, a broader time_range, or ask-web-fetch for a known URL." if time_range
      lines << hint
      lines.join("\n")
    end
    private_class_method :format_engine_error

    # Validates +time_range+ against TIME_RANGES (nil/blank → nil, symbols
    # accepted). Raises ArgumentError for anything else — the request is
    # never sent.
    def self.normalize_time_range(time_range)
      value = time_range.to_s.strip.downcase
      return nil if value.empty?

      raise ArgumentError, "invalid time_range #{time_range.inspect} — use one of: #{TIME_RANGES.join(', ')}" unless TIME_RANGES.include?(value)

      value
    end

    # Normalizes +categories+ to SearXNG's comma-separated form —
    # ["news", :science] → "news,science"; nil/blank → nil. Values pass
    # through unvalidated: SearXNG instances configure their own category
    # set, and a bad one degrades to a clean empty result, not a failure.
    def self.normalize_categories(categories)
      value = Array(categories).map { |c| c.to_s.strip.downcase }.reject(&:empty?).uniq.join(",")
      value.empty? ? nil : value
    end

    # Parses the full SearXNG JSON response into { results:, unresponsive: }.
    # results are { url:, title:, content: } entries from results and
    # infoboxes, deduplicated by url. unresponsive is the raw
    # [[engine_name, reason], ...] list SearXNG returns for failed
    # engines (e.g. [["duckduckgo", "CAPTCHA"], ["mojeek", "timeout"]]).
    def self.parse_response(data)
      results = []
      data.fetch("results", []).each do |r|
        results << { url: r["url"], title: r["title"], content: r["content"] }
      end
      data.fetch("infoboxes", []).each do |ib|
        results << { url: ib["id"], title: ib["infobox"], content: ib["content"] }
      end
      {
        results: results.uniq { |r| r[:url] },
        unresponsive: Array(data.fetch("unresponsive_engines", []))
      }
    end
    private_class_method :parse_response

    def self.parse_results(data)
      parse_response(data)[:results]
    end
    private_class_method :parse_results

    def self.format_results(results)
      return "No results found." if results.empty?

      results.each_with_index.map do |r, i|
        line = "#{i + 1}. #{r[:title]}"
        line += "\n   #{r[:url]}"
        line += "\n   #{r[:content]}" if r[:content] && !r[:content].empty?
        line
      end.join("\n\n")
    end
    private_class_method :format_results
  end
end

# The native agent tool (Ask::Tools::WebSearch) is an OPTIONAL integration:
# it loads and registers only when ask-tools is present. The library works
# standalone — consumers that only call WebSearch.search pay nothing —
# while agent frameworks (ask-agent, ask-app-server, llm-proxy) all ship
# ask-tools and get the registry tool with no extra step. Only the
# ask-tools miss is swallowed; any other LoadError is real.
begin
  require "ask-tools"
  require_relative "web_search/tool"
rescue LoadError => e
  raise unless e.path == "ask-tools"
end
