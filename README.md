# Redis cluster stores for ActiveSupport [![CI](https://github.com/film42/redis-cluster-activesupport/actions/workflows/ci.yml/badge.svg)](https://github.com/film42/redis-cluster-activesupport/actions/workflows/ci.yml)

This gem was an extension to [redis-activesupport](https://github.com/redis-store/redis-activesupport) that adds support
for a few features required to use `redis-store` with redis cluster. Right now there isn't an official redis cluster
client in ruby, so it's become common to use a redis cluster proxy like [corvus](https://github.com/eleme/corvus) or Envoy. When
switching there are a few things you can't do with redis cluster that you can do with a single redis server. Most of
them revolve around issuing commands with multiple keys. In redis cluster, your keys are partitioned and live on
different physical servers, operations like `KEYS` are not possible.

This is now leveraging Rails 6's built-in redis cache store with troubled commands removed.

## Usage

This gem is a small extension to `redis-activesupport`, so refer to their documentation for most configuration. Instead
of specifying `:redis_store` you must now specify `:redis_cluster_store` to load this extension.

```ruby
module MyProject
  class Application < Rails::Application
    config.cache_store = :redis_cluster_store, options
  end
end
```


## Limitations

Because keys in a redis cluster are partitioned across shards, operations that
touch **multiple keys at once** can't be executed in a single command and are
therefore not supported. These methods raise `NotImplementedError` instead of
silently returning incorrect results:

- `read_multi` (would use `MGET`)
- `write_multi` (would use `MSET`)
- `fetch_multi` (would use `MULTI`)
- `delete_matched` (would use `KEYS`/`SCAN`)

```ruby
store.read_multi("a", "b")        # => raises NotImplementedError
store.write_multi("a" => 1, "b" => 2)  # => raises NotImplementedError
```

Read and write a single key at a time instead. Single-key operations
(`read`, `write`, `fetch`, `increment`, `decrement`, `delete`, `exist?`) work
as usual.

## Installation

Add this line to your application's Gemfile:

```ruby
gem "redis-cluster-activesupport"
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install redis-cluster-activesupport

## Compatibility

Requires Ruby 3.1+ (CRuby 3.1–3.4, JRuby 9.4–10.0) and is tested against
ActiveSupport 6.0 through 8.1 (Rails 6.0–8.1). Note that Rails 6.0/6.1 only run
on Ruby 3.1–3.3, and Rails 8.0/8.1 require Ruby 3.2+. See
[`.github/workflows/ci.yml`](.github/workflows/ci.yml) for the full Ruby x Rails
support matrix.

## Development & Testing

Fast unit specs run against [fakeredis](https://github.com/guilleiguaran/fakeredis):

```sh
bundle exec rspec        # unit specs only (integration specs are excluded)
```

Integration specs exercise the store against a **real Redis Cluster**. Spin one
up locally (3 masters + 3 replicas) and run them with:

```sh
bin/redis-cluster        # boots a cluster on 127.0.0.1:7000-7005
bundle exec rake integration
bin/redis-cluster stop   # tear it down when finished
```

Point the specs at an existing cluster with `REDIS_CLUSTER_NODES`
(comma-separated seed nodes, e.g. `127.0.0.1:7000,127.0.0.1:7001`). On macOS,
port 7000 is often held by the AirPlay Receiver — use
`REDIS_CLUSTER_BASE_PORT=7010 bin/redis-cluster` and set `REDIS_CLUSTER_NODES`
accordingly.

To test against a specific Rails version, use [appraisal](https://github.com/thoughtbot/appraisal).
The supported versions are declared in [`Appraisals`](Appraisals) and the
`gemfiles/` are generated from it (and gitignored):

```sh
bundle exec appraisal generate            # (re)generate gemfiles/ from Appraisals
bundle exec appraisal install             # generate + bundle install every version
bundle exec appraisal rails81 rspec       # run unit specs against a single version
bundle exec appraisal rails81 rake integration   # integration specs (needs a cluster)
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/film42/redis-cluster-activesupport.

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
