require "ask/tools"
require "net/http"
require "uri"

module Ask
  module Tools
    class WebSearch < Ask::Tool
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
        format_results(results)
      end

      private

      def search(query)
        uri = URI("https://lite.duckduckgo.com/lite/")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        req = Net::HTTP::Post.new(uri)
        req.set_form_data("q" => query)
        req["User-Agent"] = "Mozilla/5.0"
        res = http.request(req)
        parse_results(res.body.force_encoding("UTF-8"))
      end

      def parse_results(html)
        results = []

        html.scan(/<a[^>]*href="([^"]+)"[^>]*>([^<]+)<\/a>/m) do |url, title|
          next if url.start_with?("#")
          next if url.include?("duckduckgo.com")
          clean_title = title.strip
          next if clean_title.empty?
          results << { url: url, title: clean_title }
        end

        results.uniq { |r| r[:url] }
      end

      def format_results(results)
        return "No results found." if results.empty?

        results.each_with_index.map do |r, i|
          "#{i + 1}. #{r[:title]}\n   #{r[:url]}"
        end.join("\n\n")
      end
    end
  end
end

Ask::Tools.register(Ask::Tools::WebSearch) if defined?(Ask::Tools)
