# ask-web-search

[![Gem Version](https://badge.fury.io/rb/ask-web-search.svg)](https://badge.fury.io/rb/ask-web-search)

A web search tool for the ask-rb ecosystem. It provides
`Ask::Tools::WebSearch`, which searches the web and returns numbered
markdown results for LLM consumption. It has no Rails dependencies; it
depends only on ask-tools.

## Backends

Two interchangeable backends, chosen automatically at call time:

1. **TinyFish (recommended — no self-hosting).** Get a free API key at
   [agent.tinyfish.ai](https://agent.tinyfish.ai/api-keys) and export it:

   ```sh
   export TINYFISH_API_KEY=...
   ```

   That's the whole setup — no Docker, no SearXNG instance. Live
   browser-rendered results, freshness windows, and the news /
   research-paper verticals all work out of the box.

2. **SearXNG (self-hosted).** For users who want queries to stay local,
   and as the automatic fallback when TinyFish fails: a running
   [SearXNG](https://docs.searxng.org/) instance, default
   `http://localhost:8888`. Start one with Docker:

   ```sh
   docker run -d --name searxng -p 8888:8080 searxng/searxng
   ```

   Or use the provided `docker-compose.yml` in the `searxng` directory of
   this repository.

Routing rules:

- `TINYFISH_API_KEY` set → TinyFish primary; if TinyFish fails **and** a
  SearXNG endpoint is explicitly configured, the call falls back to
  SearXNG automatically (combined errors surface both failures).
- No key → SearXNG only, exactly as in 0.6.x.
- `TINYFISH_SEARCH=0` disables TinyFish outright (SearXNG only, even
  with a key).

## Installation

```ruby
gem "ask-web-search"
```

## Configuration

```sh
export TINYFISH_API_KEY=...   # TinyFish (recommended): free key, instant search
export SEARXNG_URL=http://localhost:8888   # SearXNG endpoint (default shown)
```

The SearXNG endpoint can also be set in code: `Ask::WebSearch.searxng_url=`.
TinyFish reads `TINYFISH_API_KEY` from the environment only.
`Ask::WebSearch.max_retries = 0` disables the retry-with-backoff loop.

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

- **`time_range:`** restricts results to a freshness window — `day`,
  `week`, `month`, or `year`. Anything else raises `ArgumentError`
  naming the valid values. When a windowed search comes back cleanly
  empty, the result says so — "No results found within the day freshness
  window. Retry with a broader time_range or without one." — instead of a
  bare "No results found.", and engine-failure diagnostics suggest a
  broader window. TinyFish maps this to its `recency_minutes` and
  honors it properly. Caveat on the **SearXNG backend**: SearXNG
  delegates date filtering to the engines, and as of SearXNG 2026.6.x
  every date-capable engine returns zero results under a date filter, so
  windows there fail soft with that message. No gem change is needed
  when the engines are fixed upstream.
- **`categories:`** scopes the search to a vertical — `news`, `science`
  (research papers), or general web (default). Accepts a string or
  anything Array-able (`[:news, :science]` → `news,science`). TinyFish
  maps the first recognized value to its `domain_type`
  (general→web, news→news, science→research_paper; unknown categories
  are omitted so TinyFish defaults to web). On the **SearXNG backend**
  values pass through unvalidated: instances configure their own
  category set, and an unknown category degrades to a clean empty
  result rather than a failure. The instance must have vertical engines
  enabled — the `searxng/` compose config in this repository enables
  bing news + google news (news) and arxiv + pubmed (science); without
  them SearXNG silently resolves the request against the general
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
