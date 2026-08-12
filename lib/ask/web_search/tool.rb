# frozen_string_literal: true

require "ask-tools"

module Ask
  module Tools
    # The native agent tool for web search — the Ask::Tool framing of the
    # library. Consumed WITHOUT MCP by agent frameworks (ask-agent's
    # `tool: :web_search`, ask-app-server, llm-proxy) that resolve tools
    # from the Ask::Tools registry. A pure adapter: the capability
    # (search, parsing, formatting) lives in Ask::WebSearch, and this file
    # loads only when ask-tools is present (see lib/ask/web_search.rb).
    class WebSearch < Ask::Tool
      def self.searxng_url
        Ask::WebSearch.searxng_url
      end

      def self.searxng_url=(url)
        Ask::WebSearch.searxng_url = url
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
        Ask::Result.ok(data: Ask::WebSearch.search(query))
      end
    end
  end
end

Ask::Tools.register(Ask::Tools::WebSearch)
