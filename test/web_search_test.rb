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

  describe "SearXNG JSON parsing" do
    it "extracts results from JSON response" do
      data = {
        "results" => [
          { "url" => "https://example.com/1", "title" => "Result One", "content" => "Description one" },
          { "url" => "https://example.com/2", "title" => "Result Two", "content" => "Description two" }
        ]
      }
      results = @tool.send(:parse_results, data)
      _(results.length).must_equal 2
      _(results[0][:url]).must_equal "https://example.com/1"
      _(results[0][:title]).must_equal "Result One"
    end

    it "extracts infoboxes from JSON response" do
      data = {
        "results" => [],
        "infoboxes" => [
          { "id" => "https://wiki.example.com", "infobox" => "Topic", "content" => "Description" }
        ]
      }
      results = @tool.send(:parse_results, data)
      _(results.length).must_equal 1
      _(results[0][:url]).must_equal "https://wiki.example.com"
      _(results[0][:title]).must_equal "Topic"
    end

    it "deduplicates by URL" do
      data = {
        "results" => [
          { "url" => "https://example.com", "title" => "First", "content" => "" },
          { "url" => "https://example.com", "title" => "First (dup)", "content" => "" },
          { "url" => "https://other.com", "title" => "Other", "content" => "" }
        ]
      }
      results = @tool.send(:parse_results, data)
      _(results.length).must_equal 2
    end

    it "handles empty results" do
      data = { "results" => [] }
      results = @tool.send(:parse_results, data)
      _(results).must_be :empty?
    end

    it "handles missing results key" do
      results = @tool.send(:parse_results, {})
      _(results).must_be :empty?
    end

    it "handles nil values in results" do
      data = {
        "results" => [
          { "url" => nil, "title" => nil, "content" => nil }
        ]
      }
      results = @tool.send(:parse_results, data)
      _(results.length).must_equal 1
      assert_nil results[0][:url]
    end

    it "handles missing fields in results" do
      data = {
        "results" => [
          { "url" => "https://example.com" }
        ]
      }
      results = @tool.send(:parse_results, data)
      _(results.length).must_equal 1
      assert_nil results[0][:title]
    end
  end

  describe "formatting" do
    it "formats results as numbered list with URLs" do
      results = [
        { url: "https://example.com", title: "Example", content: "" },
        { url: "https://test.com", title: "Test", content: "" }
      ]
      formatted = @tool.send(:format_results, results)
      _(formatted).must_equal "1. Example\n   https://example.com\n\n2. Test\n   https://test.com"
    end

    it "includes content when present" do
      results = [
        { url: "https://example.com", title: "Example", content: "An example site" }
      ]
      formatted = @tool.send(:format_results, results)
      _(formatted).must_include "An example site"
    end

    it "returns no results message for empty list" do
      formatted = @tool.send(:format_results, [])
      _(formatted).must_equal "No results found."
    end
  end

  describe "search" do
    it "returns results from SearXNG with URLs" do
      result = @tool.call("query" => "ruby programming language")
      _(result).must_be_kind_of Ask::Result
      _(result.output).must_be_kind_of String
      _(result.output).wont_equal "No results found."
      _(result.output).must_match(%r{https?://})
    end
  end
end
