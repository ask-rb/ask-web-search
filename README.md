# ask-web-search

A web search tool for the ask-rb ecosystem. Provides `Ask::Tools::WebSearch`, which
searches the web via a local [SearXNG](https://docs.searxng.org/) instance and returns
formatted results for LLM consumption.

## Prerequisites

A running SearXNG instance. The default is `http://localhost:8888`.

Start one with Docker:

```sh
docker run -d --name searxng -p 8888:8080 searxng/searxng
```

Or use the provided `docker-compose.yml`:

```sh
cd searxng
docker compose up -d
```

## Installation

```sh
gem install ask-web-search
```

Or in your Gemfile:

```ruby
gem "ask-web-search"
```

## Configuration

Set the `SEARXNG_URL` environment variable to point to your SearXNG instance:

```sh
export SEARXNG_URL=http://localhost:8888
```

Defaults to `http://localhost:8888`.

## Usage

```ruby
require "ask/web_search"

tool = Ask::Tools::WebSearch.new
result = tool.execute(query: "ruby programming language")
puts result
# => 1. Ruby — A Programmer's Best Friend
#     https://www.ruby-lang.org
#     Ruby is a dynamic, open-source programming language...
```

### With ask-rb Chat

```ruby
chat = Ask::Agent::Chat.new(
  model: "deepseek-v4-flash",
  tools: [Ask::Tools::WebSearch.new]
)

chat.ask("What's the latest on AI? Search the web.")
```

### With ask-rb Agent

```ruby
agent = Ask::Agent.new(tools: [Ask::Tools::WebSearch])
agent.run("Find recent news about SpaceX")
```

## Output Format

Results are returned as a numbered markdown-like string:

```
1. Ruby — A Programmer's Best Friend
   https://www.ruby-lang.org
   Ruby is a dynamic, open-source programming language...

2. Ruby on Rails
   https://rubyonrails.org
   Rails is a web application framework...
```

If no results are found, returns `"No results found."`.

## Development

```sh
git clone https://github.com/ask-rb/ask-web-search
cd ask-web-search
bundle install
bundle exec rake test
```

## License

MIT
