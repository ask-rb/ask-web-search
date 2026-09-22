# ask-web-search

[![Gem Version](https://badge.fury.io/rb/ask-web-search.svg)](https://badge.fury.io/rb/ask-web-search)

A web search tool for the ask-rb ecosystem. It provides
`Ask::Tools::WebSearch`, which searches the web via a local
[SearXNG](https://docs.searxng.org/) instance and returns numbered markdown
results for LLM consumption. It has no Rails dependencies; it depends only on
ask-tools.

## Prerequisites

A running SearXNG instance. The default is `http://localhost:8888`.

Start one with Docker:

```sh
docker run -d --name searxng -p 8888:8080 searxng/searxng
```

Or use the provided `docker-compose.yml` in the `searxng` directory of this
repository:

## Installation

```ruby
gem "ask-web-search"
```

## Configuration

Set the `SEARXNG_URL` environment variable to point to your SearXNG instance:

```sh
export SEARXNG_URL=http://localhost:8888
```

Defaults to `http://localhost:8888`.

## Quick Start

```ruby
require "ask/web_search"

tool = Ask::Tools::WebSearch.new
result = tool.execute(query: "ruby programming language")
puts result
```

Results are returned as a numbered markdown-like string:

```
1. Ruby - A Programmer's Best Friend
   https://www.ruby-lang.org
   Ruby is a dynamic, open-source programming language...

2. Ruby on Rails
   https://rubyonrails.org
   Rails is a web application framework...
```

If no results are found, returns `"No results found."`.

## Freshness windows and verticals

`search` (and `search_results` / `search_raw`, and both tool framings)
accept two optional parameters:

```ruby
Ask::WebSearch.search("ruby 4.0 release notes", time_range: "month")
Ask::WebSearch.search("fed policy", categories: "news")
Ask::WebSearch.search("retrieval augmented generation", categories: "science")
```

- **`time_range:`** restricts results to a SearXNG freshness window —
  `day`, `week`, `month`, or `year`. Anything else raises `ArgumentError`
  naming the valid values. When a windowed search comes back cleanly
  empty, the result says so — "No results found within the day freshness
  window. Retry with a broader time_range or without one." — instead of a
  bare "No results found.", and engine-failure diagnostics suggest a
  broader window. Caveat: SearXNG delegates date filtering to the engines,
  and as of SearXNG 2026.6.x every date-capable engine returns zero
  results under a date filter, so windows currently fail soft with that
  message. No gem change is needed when the engines are fixed upstream.
- **`categories:`** scopes the search to a SearXNG category — `news`,
  `science` (research papers), or any category the instance configures.
  Accepts a string or anything Array-able (`[:news, :science]` →
  `news,science`). Values pass through unvalidated: instances configure
  their own category set, and an unknown category degrades to a clean
  empty result rather than a failure. The instance must have vertical
  engines enabled — the `searxng/` compose config in this repository
  enables bing news + google news (news) and arxiv + pubmed (science);
  without them SearXNG silently resolves the request against the general
  engines.

## SafeSearch and adult content

The gem returns results exactly as SearXNG produces them — it does no
content filtering of its own. Whether adult sites appear in ordinary
searches is decided entirely by the SearXNG instance's SafeSearch
setting, which SearXNG defaults to **off**. To keep adult sites out of
ordinary results, configure the instance:

```yaml
# /etc/searxng/settings.yml
preferences:
  lock:
    - safesearch

search:
  safe_search: 2
```

- `safe_search: 2` is strict filtering.
- Locking the `safesearch` preference forces that level onto every
  request, so neither this gem, the JSON API, nor the web UI can relax
  it back to 0.
- Filtering is enforced **per engine**: SearXNG forwards the level
  upstream and engines that don't implement SafeSearch (e.g.
  `duckduckgo_web`, which carries an upstream `TODO: support safesearch`)
  pass adult results through regardless of the setting. Prefer engines
  that support it (`bing`, `duckduckgo`, `google`). The `searxng/` compose
  config in this repository uses `duckduckgo` for this reason.

SafeSearch is best-effort upstream filtering — strict is reliable in
practice but not a guarantee. Consumers needing a hard guarantee should
post-filter results by domain.

## Full documentation

The full ask-rb documentation lives at https://ask-rb.github.io/ask-docs.
[Core: Web Search](https://ask-rb.github.io/ask-docs/core/web-search) covers
ask-web-search in depth, including the ask-agent integration and the MCP
server. API reference: https://ask-rb.github.io/ask-docs/reference/api.

## Development

```
bundle install
bundle exec rake test
```

## License

MIT
