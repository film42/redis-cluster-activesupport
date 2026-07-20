require "active_support"

module ActiveSupport
  module Cache
    class RedisClusterStore < RedisCacheStore
      def delete_matched(matcher, options = nil)
        fail ::NotImplementedError, "Deleting keys with a matcher is not supported with redis cluster"
      end

      def read_multi(*names)
        fail ::NotImplementedError, "Reading multiple keys with MGET is not supported with redis cluster because the keys may live on different shards"
      end

      def write_multi(hash, options = nil)
        fail ::NotImplementedError, "Writing multiple keys with MSET is not supported with redis cluster because the keys may live on different shards"
      end

      def fetch_multi(*names)
        fail ::NotImplementedError, "The default implementation uses MULTI which isn't supported. This can be changed to use MSET and work."
      end

      def increment(key, amount = 1, options = {})
        options = merged_options(options)
        ttl = _expires_in(options)
        normalized_key = normalize_key(key, options)
        instrument(:increment, key, :amount => amount) do
          redis.with do |c|
            if ttl
              new_value, _ = c.pipelined do
                c.incrby normalized_key, amount
                c.expire normalized_key, ttl
              end
              new_value
            else
              c.incrby normalized_key, amount
            end
          end
        end
      end

      private

      def _expires_in(options)
        if options
          # Rack::Session           Merb                    Rails/Sinatra
          options[:expire_after] || options[:expires_in] || options[:expire_in]
        end
      end
    end
  end
end
