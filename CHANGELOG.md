## [Unreleased]

### Changed

- **SearXNG is the default backend again.** Merely holding a TinyFish
  key no longer switches routing — as of 0.7.0 a resolving
  `TINYFISH_API_KEY` made TinyFish primary for everyone; now every
  setup keeps the self-hosted default unless TinyFish is explicitly
  selected (see Added). Existing `TINYFISH_SEARCH=0` users are
  unaffected (still a hard-off).

### Added

- **Explicit backend selection.** `Ask::WebSearch.backend` /
  `backend=` (code, beats env; nil falls back) or
  `SEARCH_BACKEND=searxng|tinyfish` (env), default `:searxng`.
  Invalid names raise `ArgumentError` listing the valid ones; config
  failures fail at selection time, not mid-search.
- **Onboarding error for a keyless TinyFish selection.** Choosing the
  tinyfish backend without a resolving key raises an error with the
  free-key URL and both storage options (ask-auth credentials file or
  `TINYFISH_API_KEY`) instead of a bare transport failure — and never
  sends a request.
- **ask-auth credential resolution for the TinyFish key.** When the
  ask-auth gem is present (optional integration, LoadError-guarded like
  ask-tools), the key resolves through `Ask::Auth` — env override first,
  then `~/.ask/credentials.yml` — so it lives in one canonical 0600 file
  instead of every config that spawns a server. Raw `ENV` remains the
  path when ask-auth isn't installed. New
  `Ask::WebSearch.tinyfish_api_key` returns the resolved key.

## [0.7.1] — 2026-09-22

### Fixed

- **TinyFish endpoint path.** The search call goes to the bare host root
  (`GET https://api.search.tinyfish.ai?query=...`), as in the official
  docs curl example — not the `/client.search.query` path carried on the
  marketing pages, which 404s on every request. Verified live: the root
  path answers 401 (auth-gated) for an invalid key, the old path 404s.

## [0.7.0] — 2026-09-22

### Added

- **TinyFish as the primary backend.** With `TINYFISH_API_KEY` set (free
  key, zero self-hosted infrastructure), searches route to TinyFish's
  hosted API first — the gem now works out of the box for newcomers who
  don't want to run SearXNG. When TinyFish fails and a SearXNG endpoint
  is explicitly configured (`SEARXNG_URL` or `searxng_url=`), the call
  falls back to SearXNG automatically; if both fail, one error surfaces
  both messages. No key → SearXNG only, byte-for-byte the 0.6.x
  behavior. `TINYFISH_SEARCH=0` disables TinyFish even with a key.
- Param mapping: `time_range` → TinyFish `recency_minutes`
  (day/week/month/year → 1440/10080/43200/525600) and the first
  recognized `categories` value → `domain_type` (general→web, news→news,
  science→research_paper; unknown categories omitted so TinyFish
  defaults to web).
- `Ask::WebSearch.use_tinyfish?` / `.searxng_configured?` routing
  introspection.

### Changed

- The retry-with-backoff loop was extracted into a shared private
  `with_retries` (param validation still happens before it, so an
  invalid `time_range` never sleeps and retries), and the SearXNG
  request logic moved to `searxng_search_raw`. Both backends are
  directly callable and honor `max_retries`.

## [0.6.0] — 2026-09-19

### Added

- **Freshness windows.** `search(query, time_range:)` restricts results
  to a SearXNG freshness window — `day`, `week`, `month`, `year`
  (validated up front; anything else raises `ArgumentError` listing the
  valid values). A clean zero-result search WITH a window says so —
  "No results found within the day freshness window. Retry with a
  broader time_range or without one." — so the agent widens the window
  instead of concluding the web is silent, and engine-failure
  diagnostics suggest a broader window when one was set. Known upstream
  limitation: as of SearXNG 2026.6.x every date-capable engine returns
  zero results under a date filter, so windows currently fail soft with
  that message; no gem change needed when the engines are fixed.
- **Verticals.** `search(query, categories:)` scopes the search to a
  SearXNG category — `news`, `science` (research papers), or any category
  the instance configures. Accepts a string or anything Array-able
  (`[:news, :science]` → `news,science`); values pass through
  unvalidated because instances configure their own set. Requires the
  instance to have vertical engines enabled (bing news / google news /
  arxiv / pubmed in the searxng/ compose config).
- Both parameters flow through `search_raw` / `search_results` and both
  tool framings: the native `Ask::Tools::WebSearch` (`time_range` and
  `categories` enum properties; a bad value fails the `Ask::Result`) and
  the MCP server's `ask_web_search` tool (released separately in
  ask-web-search-mcp 0.5.0).

## [0.5.0] — 2026-09-09

### Added

- **Engine failure diagnostics.** `AllEnginesFailedError` carries
  per-engine reasons (CAPTCHA, timeout, suspended) so the agent knows
  *why* a search returned nothing. `search()` raises it when SearXNG
  answered but every engine failed; "No results found." is now reserved
  for clean empty responses.
- **`search_raw()`** — exposes the full SearXNG response with
  `unresponsive_engines` for callers that need engine diagnostics.

## [0.4.0] — 2026-09-09

### Added

- **Retry with exponential backoff.** `search()` retries up to 3 times
  on connection/HTTP failures (0.5s, 1s, 2s backoff). Configurable via
  `WebSearch.max_retries`; set to 0 to disable.

## [0.3.0] - 2026-08-12

### Changed

- **A library, with the native tool as an optional integration.** The
  capability lives at the module level: `Ask::WebSearch.search(query)`
  returns the numbered markdown, `Ask::WebSearch.search_results(query)`
  the raw list, and `WebSearch.searxng_url` / `searxng_url=` configure
  the endpoint. `Ask::Tools::WebSearch` remains — a thin `Ask::Tool`
  adapter over the module, registered in the `Ask::Tools` registry — but
  it loads and registers only when ask-tools is present (LoadError-
  guarded require), so the library works standalone and consumers that
  only call `WebSearch.search` pay nothing. ask-tools is a development
  dependency, never a runtime one.

## [0.2.1] - 2026-06-25

### Changed
- Error handling edge cases: missing keys, nil values, infobox edge cases (17 tests). Infrastructure: rubocop, overcommit, bin/setup, CI matrix, gemspec test.
# Changelog

## 0.2.0 (2026-06-23)

- **Breaking**: Removed DuckDuckGo HTML fallback. SearXNG JSON API is the only backend.
- Default backend switched from DuckDuckGo lite HTML parsing to local SearXNG JSON API.
- `SEARXNG_URL` environment variable for custom endpoint configuration (default `http://localhost:8888`).
- Results include title, URL, and content in a numbered markdown format.
- Infobox extraction from SearXNG responses.
- Deduplication by URL.
- Connection timeouts: 5s open, 10s read.

## 0.1.0 (2026-06-16)

- Initial release.
- DuckDuckGo lite HTML scraping backend.
- `Ask::Tools::WebSearch` tool for ask-rb ecosystem.
