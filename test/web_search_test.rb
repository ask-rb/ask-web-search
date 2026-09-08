require_relative "test_helper"

describe Ask::WebSearch do
  describe "SearXNG JSON parsing" do
    it "extracts results from JSON response" do
      data = {
        "results" => [
          { "url" => "https://example.com/1", "title" => "Result One", "content" => "Description one" },
          { "url" => "https://example.com/2", "title" => "Result Two", "content" => "Description two" }
        ]
      }
      results = Ask::WebSearch.send(:parse_results, data)
      _(results.length).must_equal 2
      _(results[0][:url]).must_equal "https://example.com/1"
    end

    it "extracts infoboxes from JSON response" do
      data = { "results" => [], "infoboxes" => [{ "id" => "https://wiki.example.com", "infobox" => "Topic", "content" => "Desc" }] }
      results = Ask::WebSearch.send(:parse_results, data)
      _(results.length).must_equal 1
      _(results[0][:url]).must_equal "https://wiki.example.com"
    end

    it "deduplicates by URL" do
      data = { "results" => [
        { "url" => "https://example.com", "title" => "First", "content" => "" },
        { "url" => "https://example.com", "title" => "Dup", "content" => "" },
        { "url" => "https://other.com", "title" => "Other", "content" => "" }
      ]}
      results = Ask::WebSearch.send(:parse_results, data)
      _(results.length).must_equal 2
    end

    it "handles empty results" do
      results = Ask::WebSearch.send(:parse_results, { "results" => [] })
      _(results).must_be :empty?
    end

    it "handles missing results key" do
      results = Ask::WebSearch.send(:parse_results, {})
      _(results).must_be :empty?
    end

    it "handles nil values in results" do
      data = { "results" => [{ "url" => nil, "title" => nil, "content" => nil }] }
      results = Ask::WebSearch.send(:parse_results, data)
      _(results.length).must_equal 1
      assert_nil results[0][:url]
    end

    it "handles missing fields in results" do
      data = { "results" => [{ "url" => "https://example.com" }] }
      results = Ask::WebSearch.send(:parse_results, data)
      _(results.length).must_equal 1
      assert_nil results[0][:title]
    end
  end

  describe "formatting" do
    it "formats as numbered list with URLs" do
      results = [
        { url: "https://example.com", title: "Example", content: "" },
        { url: "https://test.com", title: "Test", content: "" }
      ]
      formatted = Ask::WebSearch.send(:format_results, results)
      _(formatted).must_equal "1. Example\n   https://example.com\n\n2. Test\n   https://test.com"
    end

    it "includes content when present" do
      results = [{ url: "https://example.com", title: "Example", content: "An example site" }]
      formatted = Ask::WebSearch.send(:format_results, results)
      _(formatted).must_include "An example site"
    end

    it "returns no results message for empty list" do
      formatted = Ask::WebSearch.send(:format_results, [])
      _(formatted).must_equal "No results found."
    end
  end

  describe "search with VCR" do
    before do
      VCR.insert_cassette("searxng_results")
    end

    after do
      VCR.eject_cassette
    end

    it "returns formatted markdown" do
      markdown = Ask::WebSearch.search("ruby programming language")
      _(markdown).must_be_kind_of String
      _(markdown).wont_equal "No results found."
    end

    it "returns numbered results with URLs" do
      markdown = Ask::WebSearch.search("ruby programming language")
      _(markdown).must_match(%r{https?://})
      _(markdown).must_match(/^1\./)
    end

    it "returns multiple results" do
      markdown = Ask::WebSearch.search("ruby programming language")
      numbered = markdown.split("\n").count { |l| l.match?(/^\d+\./) }
      _(numbered).must_be :>=, 2
    end

    it "includes content descriptions" do
      markdown = Ask::WebSearch.search("ruby programming language")
      descriptions = markdown.split("\n").select { |l| l.start_with?("   ") && !l.start_with?("   http") }
      _(descriptions.length).must_be :>=, 1
    end

    it "allows multiple calls via playback repeats" do
      r1 = Ask::WebSearch.search("ruby programming language")
      r2 = Ask::WebSearch.search("ruby programming language")
      _(r1).must_equal r2
    end
  end

  describe "connection errors" do
    before do
      WebMock.disable_net_connect!
      Ask::WebSearch.max_retries = 0
    end

    after do
      WebMock.reset!
      Ask::WebSearch.max_retries = Ask::WebSearch::DEFAULT_MAX_RETRIES
    end

    it "raises on connection refused" do
      stub_request(:get, /localhost/).to_raise(Errno::ECONNREFUSED.new)
      _(-> { Ask::WebSearch.search("test") }).must_raise Errno::ECONNREFUSED
    end

    it "raises on HTTP error" do
      stub_request(:get, /localhost/).to_return(status: 500, body: "error")
      _(-> { Ask::WebSearch.search("test") }).must_raise RuntimeError
    end
  end

  describe "retry behavior" do
    before do
      WebMock.disable_net_connect!
    end

    after do
      WebMock.reset!
      Ask::WebSearch.max_retries = Ask::WebSearch::DEFAULT_MAX_RETRIES
    end

    it "retries on connection refused and succeeds on second attempt" do
      call_count = 0
      stub_request(:get, /localhost/).to_return do
        call_count += 1
        if call_count == 1
          raise Errno::ECONNREFUSED
        else
          { status: 200, body: '{"results": [{"url": "https://example.com", "title": "Example", "content": "Test"}]}' }
        end
      end

      result = Ask::WebSearch.search("test")
      _(result).must_include "Example"
      _(call_count).must_equal 2
    end

    it "retries on HTTP 500 and succeeds on second attempt" do
      call_count = 0
      stub_request(:get, /localhost/).to_return do
        call_count += 1
        if call_count == 1
          { status: 500, body: "error" }
        else
          { status: 200, body: '{"results": [{"url": "https://example.com", "title": "Example", "content": "Test"}]}' }
        end
      end

      result = Ask::WebSearch.search("test")
      _(result).must_include "Example"
      _(call_count).must_equal 2
    end

    it "gives up after max_retries exhausted" do
      Ask::WebSearch.max_retries = 2
      stub_request(:get, /localhost/).to_raise(Errno::ECONNREFUSED.new)

      _(-> { Ask::WebSearch.search("test") }).must_raise Errno::ECONNREFUSED
    end

    it "does not retry when max_retries is 0" do
      Ask::WebSearch.max_retries = 0
      call_count = 0
      stub_request(:get, /localhost/).to_return do
        call_count += 1
        raise Errno::ECONNREFUSED
      end

      _(-> { Ask::WebSearch.search("test") }).must_raise Errno::ECONNREFUSED
      _(call_count).must_equal 1
    end

    it "retries up to max_retries times" do
      Ask::WebSearch.max_retries = 3
      call_count = 0
      stub_request(:get, /localhost/).to_return do
        call_count += 1
        raise Errno::ECONNREFUSED
      end

      _(-> { Ask::WebSearch.search("test") }).must_raise Errno::ECONNREFUSED
      _(call_count).must_equal 4 # 1 initial + 3 retries
    end
  end
end

# The native agent tool — Ask::Tool framing of the library. Runs only
# when ask-tools is present (it is, in the gem's dev bundle); the tool
# itself is an optional integration for agent-framework consumers.
if defined?(Ask::Tools)
  describe Ask::Tools::WebSearch do
    before do
      @tool = Ask::Tools::WebSearch.new
    end

    it "has the tool framing: name, description, query param" do
      _(@tool.name).must_equal "web_search"
      _(@tool.description).wont_be_nil
      _(@tool.description).wont_be :empty?
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

    it "delegates the endpoint configuration to the library" do
      Ask::Tools::WebSearch.searxng_url = "http://searxng.test"
      _(Ask::WebSearch.searxng_url).must_equal "http://searxng.test"
    ensure
      Ask::WebSearch.searxng_url = nil
    end

    describe "search with VCR" do
      before do
        VCR.insert_cassette("searxng_results")
      end

      after do
        VCR.eject_cassette
      end

      it "returns an Ask::Result with formatted output" do
        result = @tool.call("query" => "ruby programming language")
        _(result).must_be_kind_of Ask::Result
        _(result.ok?).must_equal true
        _(result.output).must_be_kind_of String
        _(result.output).must_match(%r{https?://})
      end
    end

    describe "connection errors" do
      before do
        WebMock.disable_net_connect!
      end

      after do
        WebMock.reset!
      end

      it "wraps a failed search in a failed result" do
        stub_request(:get, /localhost/).to_raise(Errno::ECONNREFUSED.new)
        result = @tool.call("query" => "test")
        _(result).must_be_kind_of Ask::Result
        _(result.ok?).must_equal false
      end
    end
  end
end
