$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "ask-web-search"

require "minitest/autorun"

require "vcr"
require "webmock/minitest"

VCR.configure do |c|
  c.cassette_library_dir = File.expand_path("fixtures/vcr_cassettes", __dir__)
  c.hook_into :webmock
  c.ignore_localhost = false
  c.filter_sensitive_data("<SEARXNG_HOST>") { "localhost" }
  c.default_cassette_options = {
    record: :once,
    allow_playback_repeats: true,
    match_requests_on: [:method, :uri]
  }
end
