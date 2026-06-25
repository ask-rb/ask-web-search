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
