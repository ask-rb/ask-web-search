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

    def self.max_retries
      return @max_retries if defined?(@max_retries)

      @max_retries = DEFAULT_MAX_RETRIES
    end

    def self.max_retries=(val)
      @max_retries = val
    end

    # Searches +query+ and returns the results as numbered markdown
    # ("No results found." when SearXNG found nothing). Raises on
    # connection/HTTP failures — the caller decides how to surface them.
    def self.search(query)
      format_results(search_results(query))
    end

    # The raw result list: { url:, title:, content: } entries from the
    # results and infoboxes, deduplicated by url. Retries up to
    # max_retries times on connection/HTTP failures with exponential
    # backoff. Set max_retries to 0 to disable.
    def self.search_results(query)
      uri = URI("#{searxng_url}/search?q=#{URI.encode_www_form_component(query)}&format=json")
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

        parse_results(JSON.parse(res.body))
      rescue StandardError
        raise if attempt > retries

        sleep RETRY_BACKOFF[[attempt - 1, RETRY_BACKOFF.size - 1].min]
        retry
      end
    end

    def self.parse_results(data)
      results = []
      data.fetch("results", []).each do |r|
        results << { url: r["url"], title: r["title"], content: r["content"] }
      end
      data.fetch("infoboxes", []).each do |ib|
        results << { url: ib["id"], title: ib["infobox"], content: ib["content"] }
      end
      results.uniq { |r| r[:url] }
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
