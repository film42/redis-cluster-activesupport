require "bundler/setup"
require "logger"
require "securerandom"
require "redis"
require "redis/cluster/activesupport"

# Integration specs run against a REAL Redis Cluster (no fakeredis). Point them at
# a running cluster with the REDIS_CLUSTER_NODES env var (comma separated host:port
# seed nodes). Locally you can start one with `bin/redis-cluster`.
#
#   REDIS_CLUSTER_NODES=127.0.0.1:7000,127.0.0.1:7001,127.0.0.1:7002 \
#     bundle exec rspec spec/integration
module RedisClusterIntegration
  DEFAULT_NODES = "127.0.0.1:7000,127.0.0.1:7001,127.0.0.1:7002".freeze

  module_function

  def node_urls
    (ENV["REDIS_CLUSTER_NODES"] || DEFAULT_NODES)
      .split(",")
      .map { |host_port| "redis://#{host_port.strip}" }
  end

  # A fresh cluster-aware client. redis-rb resolves the full topology from the
  # seed nodes and routes commands to the owning shard.
  def new_client
    Redis.new(cluster: node_urls)
  end

  def reachable?
    new_client.ping == "PONG"
  rescue StandardError
    false
  end
end

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }

  config.before(:suite) do
    unless RedisClusterIntegration.reachable?
      abort <<~MSG
        Could not reach a Redis Cluster at #{RedisClusterIntegration.node_urls.join(', ')}.
        Start one locally with `bin/redis-cluster` or set REDIS_CLUSTER_NODES.
      MSG
    end
  end
end
