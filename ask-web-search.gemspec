require_relative "lib/ask/web_search/version"

Gem::Specification.new do |spec|
  spec.name = "ask-web-search"
  spec.version = Ask::WebSearch::VERSION
  spec.authors = ["Kaka Ruto"]
  spec.email = ["kaka@myrrlabs.com"]

  spec.summary = "Web search tool for the ask-rb ecosystem"
  spec.description = "Provides Ask::Tools::WebSearch, a tool that searches the web " \
                     "via DuckDuckGo (no API key required). Works with any ask-rb " \
                     "chat or agent. Swap to Brave/Firecrawl/etc. via the adapter interface."
  spec.homepage = "https://github.com/ask-rb/ask-web-search"
  spec.license = "MIT"

  spec.required_ruby_version = ">= 3.2"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/master/CHANGELOG.md"

  spec.files = Dir["lib/**/*", "LICENSE", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "ask-tools", ">= 0.1"

  spec.add_development_dependency "minitest", "~> 5.25"
  spec.add_development_dependency "rake", "~> 13.0"
end
