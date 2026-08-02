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
