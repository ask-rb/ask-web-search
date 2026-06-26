require "ask-tools"
require "net/http"
require "uri"
require "json"

module Ask
  module Tools
    class WebSearch < Ask::Tool
      def self.searxng_url
        @searxng_url || ENV.fetch("SEARXNG_URL", "http://localhost:8888")
      end

      def self.searxng_url=(url)
        @searxng_url = url
      end

      description "Search the web for current information. Use this to get up-to-date results, recent events, or facts that may have changed."

      params(
        type: "object",
        properties: {
          query: { type: "string", description: "The search query" }
        },
        required: ["query"]
      )

      def execute(query:)
        results = search(query)
        Ask::Result.ok(data: format_results(results))
      end

      private

      def search(query)
        uri = URI("#{self.class.searxng_url}/search?q=#{URI.encode_www_form_component(query)}&format=json")
        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = 5
        http.read_timeout = 10
        req = Net::HTTP::Get.new(uri)
        req["User-Agent"] = "ask-web-search/1.0"
        res = http.request(req)
        raise "SearXNG returned #{res.code}: #{res.body}" unless res.code.start_with?("2")

        data = JSON.parse(res.body)
        parse_results(data)
      end

      def parse_results(data)
        results = []
        data.fetch("results", []).each do |r|
          results << { url: r["url"], title: r["title"], content: r["content"] }
        end
        data.fetch("infoboxes", []).each do |ib|
          results << { url: ib["id"], title: ib["infobox"], content: ib["content"] }
        end
        results.uniq { |r| r[:url] }
      end

      def format_results(results)
        return "No results found." if results.empty?

        results.each_with_index.map do |r, i|
          line = "#{i + 1}. #{r[:title]}"
          line += "\n   #{r[:url]}"
          line += "\n   #{r[:content]}" if r[:content] && !r[:content].empty?
          line
        end.join("\n\n")
      end
    end
  end
end

Ask::Tools.register(Ask::Tools::WebSearch) if defined?(Ask::Tools)
