require_relative "lib/ask/web_search/version"

Gem::Specification.new do |spec|
  spec.name = "ask-web-search"
  spec.version = Ask::WebSearch::VERSION
  spec.authors = ["Kaka Ruto"]
  spec.email = ["kaka@myrrlabs.com"]

  spec.summary = "Web search library for the ask-rb ecosystem"
  spec.description = "Web search returning results as clean numbered markdown. " \
                     "Two backends: TinyFish's hosted API (primary with " \
                     "TINYFISH_API_KEY — no self-hosting) and a local SearXNG " \
                     "instance (SEARXNG_URL, also the automatic fallback). The " \
                     "capability layer (WebSearch.search); the native " \
                     "Ask::Tools::WebSearch agent tool is an optional " \
                     "integration that registers when ask-tools is present."
  spec.homepage = "https://github.com/ask-rb/ask-web-search"
  spec.license = "MIT"

  spec.required_ruby_version = ">= 3.2"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/master/CHANGELOG.md"

  spec.files = Dir["lib/**/*", "LICENSE", "README.md"]
  spec.require_paths = ["lib"]

  # ask-tools is an OPTIONAL runtime integration (the native agent tool
  # registers only when it is present); it is a dev dependency so the
  # gem's own suite exercises the tool.
  spec.add_development_dependency "ask-tools", ">= 0.1"

  # ask-auth is likewise an OPTIONAL runtime integration — the TinyFish
  # key resolves through Ask::Auth when present (env → credentials file),
  # raw ENV otherwise; a dev dependency so the suite exercises the chain.
  spec.add_development_dependency "ask-auth", ">= 0.3"

  spec.add_development_dependency "vcr", "~> 6.0"
  spec.add_development_dependency "webmock", "~> 3.26"
  spec.add_development_dependency "minitest", "~> 5.25"
  spec.add_development_dependency "rake", "~> 13.0"
end
