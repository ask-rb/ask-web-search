require_relative "test_helper"

describe Ask::Tools::WebSearch do
  before do
    @tool = Ask::Tools::WebSearch.new
  end

  it "has the correct name" do
    _(@tool.name).must_equal "web_search"
  end

  it "has a description" do
    _(@tool.description).wont_be_nil
    _(@tool.description).wont_be :empty?
  end

  it "has a query parameter" do
    schema = @tool.params_schema
    _(schema).wont_be_nil
    _(schema["required"]).must_include "query"
    _(schema.dig("properties", "query", "type")).must_equal "string"
  end

  it "registers itself in the tool registry" do
    tool = Ask::Tools["web_search"]
    _(tool).wont_be_nil
    _(tool).must_be_kind_of Ask::Tools::WebSearch
  end

  describe "parsing" do
    it "extracts links from DDG lite HTML" do
      html = <<~HTML
        <a rel="nofollow" href="https://example.com/page1">Result One</a>
        <a rel="nofollow" href="https://example.com/page2">Result Two</a>
      HTML
      results = @tool.send(:parse_results, html)
      _(results.length).must_equal 2
      _(results[0][:url]).must_equal "https://example.com/page1"
      _(results[0][:title]).must_equal "Result One"
    end

    it "filters out DDG internal links" do
      html = <<~HTML
        <a href="https://duckduckgo.com/about">About</a>
        <a rel="nofollow" href="https://example.com">Real Result</a>
        <a href="#top">Top</a>
      HTML
      results = @tool.send(:parse_results, html)
      _(results.length).must_equal 1
      _(results[0][:url]).must_equal "https://example.com"
    end

    it "deduplicates by URL" do
      html = <<~HTML
        <a rel="nofollow" href="https://example.com">First</a>
        <a rel="nofollow" href="https://example.com">First (dup)</a>
        <a rel="nofollow" href="https://other.com">Other</a>
      HTML
      results = @tool.send(:parse_results, html)
      _(results.length).must_equal 2
    end
  end

  describe "formatting" do
    it "formats results as numbered list with URLs" do
      results = [
        { url: "https://example.com", title: "Example" },
        { url: "https://test.com", title: "Test" }
      ]
      formatted = @tool.send(:format_results, results)
      _(formatted).must_equal "1. Example\n   https://example.com\n\n2. Test\n   https://test.com"
    end

    it "returns no results message for empty list" do
      formatted = @tool.send(:format_results, [])
      _(formatted).must_equal "No results found."
    end
  end

  describe "search" do
    it "returns results from duckduckgo with URLs" do
      result = @tool.execute(query: "ruby programming language")
      _(result).must_be_kind_of String
      skip "DuckDuckGo rate-limited this test run" if result == "No results found."
      _(result).must_match(%r{https?://})
    end
  end
end
