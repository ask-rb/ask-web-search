# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require_relative "web_search/version"

module Ask
  # Searches the web and returns the results as clean, numbered markdown
  # for LLM consumption. Two interchangeable backends: a local SearXNG
  # instance — the default path for everyone — and TinyFish's hosted
  # search API, strictly opt-in (SEARCH_BACKEND=tinyfish + a free API
  # key) for users who'd rather hold a key than run SearXNG. When the
  # tinyfish backend fails, an explicitly configured SearXNG endpoint is
  # still the automatic fallback. The capability layer: one entry point
  # (WebSearch.search). Tool framing — name, parameter schema, result
  # wrapping — lives with the consumers (the MCP server, the agents)
  # that call this library.
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
      @searxng_url_set = !url.nil?
    end

    # Retry configuration. Set max_retries to 0 to disable retries.
    DEFAULT_MAX_RETRIES = 3
    RETRY_BACKOFF = [0.5, 1.0, 2.0].freeze

    # SearXNG's freshness windows — the valid values of its time_range
    # search parameter. Anything else is rejected up front, so a bad value
    # fails with a message listing these instead of silently searching
    # unfiltered.
    TIME_RANGES = %w[day week month year].freeze

    # TinyFish's hosted search endpoint — available when the tinyfish
    # backend is selected (SEARCH_BACKEND=tinyfish). The bare host root
    # per the official docs curl example; the /client.search.query path
    # seen on the marketing pages 404s.
    TINYFISH_SEARCH_URL = "https://api.search.tinyfish.ai"

    # The selectable backends (see .backend for how one is chosen).
    BACKENDS = %w[searxng tinyfish].freeze

    # Our time_range → TinyFish's recency_minutes (SearXNG's month/year
    # are approximate engine filters anyway; these are the equivalents).
    TIME_RANGE_TO_MINUTES = {
      "day" => 1440,
      "week" => 10_080,
      "month" => 43_200,
      "year" => 525_600
    }.freeze

    # Our categories → TinyFish's single-value domain_type. The FIRST
    # recognized value wins (TinyFish is one-domain-per-query); unknown
    # categories are omitted so TinyFish falls back to its web default.
    CATEGORIES_TO_DOMAIN_TYPE = {
      "general" => "web",
      "web" => "web",
      "news" => "news",
      "science" => "research_paper",
      "research_paper" => "research_paper"
    }.freeze

    # The search backend — :searxng (the default path for everyone) or
    # :tinyfish (opt-in for users who'd rather hold an API key than run
    # SearXNG). Selection precedence:
    #
    #   1. TINYFISH_SEARCH=0 — a hard-off that forces :searxng
    #   2. backend= setter (Ask::WebSearch.backend = :tinyfish)
    #   3. SEARCH_BACKEND env ("searxng" | "tinyfish")
    #   4. default :searxng
    def self.backend
      return :searxng if ENV["TINYFISH_SEARCH"] == "0"
      return @backend if defined?(@backend) && @backend

      raw = ENV["SEARCH_BACKEND"]
      return :searxng if raw.to_s.empty?

      normalize_backend(raw)
    end

    # Selects the backend in code (:searxng / :tinyfish, or nil to fall
    # back to env/default). Raises ArgumentError for anything else —
    # config-time failure instead of a silently ignored value.
    def self.backend=(name)
      @backend = name.nil? ? nil : normalize_backend(name)
    end

    def self.normalize_backend(name)
      value = name.to_s.strip.downcase
      unless BACKENDS.include?(value)
        raise ArgumentError, "invalid backend #{name.inspect} — use one of: #{BACKENDS.join(', ')}"
      end

      value.to_sym
    end
    private_class_method :normalize_backend

    # The TinyFish API key: ask-auth's chain when that gem is present
    # (env override → ~/.ask/credentials.yml → …), raw ENV otherwise.
    # nil when nothing resolves.
    def self.tinyfish_api_key
      return ENV["TINYFISH_API_KEY"] unless defined?(Ask::Auth)

      Ask::Auth.resolve(:tinyfish_api_key)
    rescue Ask::Auth::MissingCredential
      nil
    end

    # True when searches should go to TinyFish — i.e. the backend was
    # explicitly selected. Read fresh on every call so tests and config
    # reloads don't need memo resets. Holding a key alone does NOT
    # opt in: SearXNG stays the default path.
    def self.use_tinyfish?
      backend == :tinyfish
    end

    # True when a SearXNG endpoint was configured explicitly (SEARXNG_URL
    # or searxng_url=). Gates the TinyFish → SearXNG fallback so a failed
    # TinyFish search never probes a default localhost instance that may
    # not exist.
    def self.searxng_configured?
      return true if @searxng_url_set

      !ENV["SEARXNG_URL"].to_s.empty?
    end

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

    # The full response: { results: [...], unresponsive: [[name,
    # reason], ...] }. Routes to TinyFish when #use_tinyfish? (the
    # opt-in tinyfish backend — a keyless selection raises its
    # onboarding error; a transport failure falls back to SearXNG when
    # explicitly configured), otherwise to SearXNG — the default path
    # for everyone. Same retry logic either way, but preserves the
    # engine diagnostics the caller needs to explain an empty result.
    # time_range / categories are normalized by the backends that build
    # requests — idempotent, so callers may pass raw or
    # already-normalized values.
    def self.search_raw(query, time_range: nil, categories: nil)
      return searxng_search_raw(query, time_range: time_range, categories: categories) unless use_tinyfish?

      begin
        tinyfish_search_raw(query, time_range: time_range, categories: categories)
      rescue StandardError => primary_error
        raise primary_error unless searxng_configured?

        begin
          searxng_search_raw(query, time_range: time_range, categories: categories)
        rescue StandardError => fallback_error
          raise Error, "search failed: TinyFish → #{primary_error.message}; " \
                       "SearXNG fallback → #{fallback_error.message}"
        end
      end
    end

    # The SearXNG backend: GET {searxng_url}/search with the metasearch
    # params, parsed into { results:, unresponsive: }. Call directly to
    # bypass the router (and any TinyFish routing/fallback).
    def self.searxng_search_raw(query, time_range: nil, categories: nil)
      params = { q: query, format: "json" }
      params[:time_range] = normalize_time_range(time_range) if time_range
      params[:categories] = normalize_categories(categories) if categories
      uri = URI("#{searxng_url}/search")
      uri.query = URI.encode_www_form(params)

      with_retries do
        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = 5
        http.read_timeout = 10
        req = Net::HTTP::Get.new(uri)
        req["User-Agent"] = "ask-web-search/#{Ask::WebSearch::VERSION}"
        res = http.request(req)
        raise "SearXNG returned #{res.code}: #{res.body}" unless res.code.start_with?("2")

        parse_response(JSON.parse(res.body))
      end
    end

    # The TinyFish backend: GET the hosted search API (needs
    # TINYFISH_API_KEY), normalized into the same { results:,
    # unresponsive: } contract — snippet → content; a single hosted
    # API has no per-engine status, so unresponsive is always empty
    # (transport failures raise instead, which the router's fallback
    # catches). time_range maps to recency_minutes; the FIRST
    # recognized categories value maps to domain_type.
    def self.tinyfish_search_raw(query, time_range: nil, categories: nil)
      key = tinyfish_api_key
      if key.to_s.empty?
        raise Error, "TinyFish backend selected (SEARCH_BACKEND=tinyfish) but no API key resolves. " \
                     "Get a free key at https://agent.tinyfish.ai/api-keys, then add " \
                     "`tinyfish_api_key: <key>` to ~/.ask/credentials.yml or export " \
                     "TINYFISH_API_KEY — or drop SEARCH_BACKEND to stay on the default SearXNG path."
      end

      params = { query: query }
      normalized_range = normalize_time_range(time_range)
      params[:recency_minutes] = TIME_RANGE_TO_MINUTES[normalized_range] if normalized_range
      normalized_categories = normalize_categories(categories)
      if normalized_categories
        domain = CATEGORIES_TO_DOMAIN_TYPE[normalized_categories.split(",").first]
        params[:domain_type] = domain if domain
      end
      uri = URI(TINYFISH_SEARCH_URL)
      uri.query = URI.encode_www_form(params)

      with_retries do
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 5
        http.read_timeout = 10
        req = Net::HTTP::Get.new(uri)
        req["X-API-Key"] = key
        req["User-Agent"] = "ask-web-search/#{Ask::WebSearch::VERSION}"
        res = http.request(req)
        raise Error, "TinyFish returned #{res.code}: #{res.body[0, 200]}" unless res.code.start_with?("2")

        data = JSON.parse(res.body)
        results = data.fetch("results", []).map do |r|
          { url: r["url"], title: r["title"], content: r["snippet"] }
        end
        { results: results, unresponsive: [] }
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

    # Retries the block up to max_retries times on any StandardError
    # with exponential backoff (RETRY_BACKOFF). Param building and
    # validation happen OUTSIDE the block in the backends, so an
    # ArgumentError never sleeps and retries.
    def self.with_retries
      attempt = 0
      begin
        attempt += 1
        yield
      rescue StandardError
        raise if attempt > (max_retries || 0)

        sleep RETRY_BACKOFF[[attempt - 1, RETRY_BACKOFF.size - 1].min]
        retry
      end
    end
    private_class_method :with_retries

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

# ask-auth is an OPTIONAL credential source for the TinyFish key: when
# present, #tinyfish_api_key resolves through Ask::Auth (env override →
# ~/.ask/credentials.yml → …) instead of raw ENV alone, so the key can
# live in one canonical 0600 file instead of every config that spawns a
# server. Only the ask-auth miss is swallowed; any other LoadError is
# real.
begin
  require "ask-auth"
rescue LoadError => e
  raise unless e.path == "ask-auth"
end
