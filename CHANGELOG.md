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
