require "spec_helper"

describe ::ActiveSupport::Cache::RedisClusterStore do
  # A redis client whose connection-checkout methods always raise, used to drive
  # the store's failsafe paths without coupling the test to which internal proxy
  # method (`with` on < 7.1, `then` on >= 7.1) or command a given Rails uses.
  class RaisingClient
    def with(*)
      raise ::Redis::CommandError, "ERR simulated failure"
    end

    def then(*)
      raise ::Redis::CommandError, "ERR simulated failure"
    end
  end

  # Use pool: false to avoid connection_pool 3.0 compatibility issues with Rails 7.1
  let(:options) { { redis: Redis.new, pool: false } }
  let(:redis) { subject.redis }

  subject { described_class.new(**options) }

  describe "store registration" do
    it "is a RedisCacheStore" do
      expect(described_class.ancestors).to include(::ActiveSupport::Cache::RedisCacheStore)
    end

    it "resolves through the documented :redis_cluster_store symbol" do
      store = ::ActiveSupport::Cache.lookup_store(:redis_cluster_store, **options)
      expect(store).to be_a(described_class)
    end
  end

  describe "reading and writing" do
    it "round-trips a string value" do
      expect(subject.write("greeting", "hello")).to be_truthy
      expect(subject.read("greeting")).to eq("hello")
    end

    it "round-trips a marshaled object" do
      value = { "a" => 1, "b" => [1, 2, 3] }
      subject.write("obj", value)
      expect(subject.read("obj")).to eq(value)
    end

    it "returns nil for a missing key" do
      expect(subject.read("nope")).to be_nil
    end

    it "overwrites an existing value" do
      subject.write("k", "one")
      subject.write("k", "two")
      expect(subject.read("k")).to eq("two")
    end

    it "supports raw values" do
      subject.write("raw", "payload", raw: true)
      expect(subject.read("raw", raw: true)).to eq("payload")
    end

    it "reports existence" do
      subject.write("present", "1")
      expect(subject.exist?("present")).to be(true)
      expect(subject.exist?("absent")).to be(false)
    end

    it "deletes a key" do
      subject.write("temp", "v")
      # 7.0 returns the raw redis DEL count (1); 7.1+ returns a boolean.
      expect(subject.delete("temp")).to be_truthy
      expect(subject.read("temp")).to be_nil
    end
  end

  describe "#fetch" do
    it "runs the block and writes on a miss" do
      calls = 0
      result = subject.fetch("computed") { calls += 1; "value" }
      expect(result).to eq("value")
      expect(subject.read("computed")).to eq("value")
      expect(calls).to eq(1)
    end

    it "returns the cached value on a hit without running the block" do
      subject.write("computed", "cached")
      calls = 0
      result = subject.fetch("computed") { calls += 1; "fresh" }
      expect(result).to eq("cached")
      expect(calls).to eq(0)
    end

    it "re-runs the block when force: true" do
      subject.write("computed", "cached")
      result = subject.fetch("computed", force: true) { "fresh" }
      expect(result).to eq("fresh")
    end
  end

  describe "expiry" do
    it "applies expires_in as a TTL on the underlying key" do
      subject.write("ttl-key", "v", expires_in: 5.minutes)
      expect(redis.ttl("ttl-key")).to be_between(1, 300)
    end
  end

  describe "namespacing" do
    subject { described_class.new(redis: Redis.new, namespace: "ns", pool: false) }

    it "prefixes the underlying key with the namespace" do
      subject.write("k", "v")
      expect(redis.exists?("ns:k")).to be(true)
      expect(subject.read("k")).to eq("v")
    end
  end

  describe "compression" do
    it "round-trips a large value with compression enabled" do
      value = "x" * 10_000
      subject.write("big", value, compress: true, compress_threshold: 1)
      expect(subject.read("big")).to eq(value)
    end
  end

  describe "#increment" do
    it "returns an Integer new value (not the pipelined array) when given a ttl" do
      result = subject.increment("counter", 1, expires_in: 5.minutes)
      expect(result).to eq(1)
      expect(result).to be_a(Integer)
    end

    it "returns cumulative values" do
      expect(subject.increment("counter", 1, expires_in: 5.minutes)).to eq(1)
      expect(subject.increment("counter", 5, expires_in: 5.minutes)).to eq(6)
    end

    it "increments a key that does not exist yet" do
      expect(subject.increment("fresh", 3)).to eq(3)
    end

    it "accepts a negative amount" do
      subject.increment("counter", 10)
      expect(subject.increment("counter", -4)).to eq(6)
    end

    it "does not set a ttl when none is given (key is persistent)" do
      subject.increment("no-ttl", 1)
      expect(redis.ttl("no-ttl")).to eq(-1)
    end

    it "sets a ttl when expires_in is given" do
      subject.increment("with-ttl", 1, expires_in: 5.minutes)
      expect(redis.ttl("with-ttl")).to be_between(1, 300)
    end

    it "honors the store namespace" do
      store = described_class.new(redis: Redis.new, namespace: "ns", pool: false)
      store.increment("counter", 1, expires_in: 5.minutes)
      expect(Redis.new.exists?("ns:counter")).to be(true)
    end

    it "supports the expires_in, expire_in and expire_after ttl aliases" do
      { expires_in: "a", expire_in: "b", expire_after: "c" }.each do |option, key|
        subject.increment(key, 1, option => 60)
        expect(redis.ttl(key)).to be_between(1, 60)
      end
    end
  end

  describe "#decrement" do
    # decrement is not overridden by this gem; pin the inherited behavior so an
    # upstream change is caught.
    it "decrements a counter" do
      subject.increment("counter", 10)
      expect(subject.decrement("counter", 3)).to eq(7)
    end

    it "does not set a ttl" do
      subject.increment("counter", 10)
      subject.decrement("counter", 1)
      expect(redis.ttl("counter")).to eq(-1)
    end
  end

  describe "failsafe behavior when redis raises" do
    let(:options) { { redis: RaisingClient.new, pool: false } }

    it "read returns nil" do
      expect(subject.read("k")).to be_nil
    end

    it "write returns a falsey value" do
      # 7.2+ returns nil, earlier versions return false; both mean "not written".
      expect(subject.write("k", "v")).to be_falsey
    end

    it "delete returns false" do
      expect(subject.delete("k")).to eq(false)
    end
  end

  describe "operations unsupported on a redis cluster" do
    it "#delete_matched raises" do
      expect { subject.delete_matched("*") }
        .to raise_error(::NotImplementedError, /matcher is not supported/)
    end

    it "#read_multi raises" do
      expect { subject.read_multi("a", "b") }
        .to raise_error(::NotImplementedError, /MGET is not supported/)
    end

    it "#write_multi raises" do
      expect { subject.write_multi("a" => 1, "b" => 2) }
        .to raise_error(::NotImplementedError, /MSET is not supported/)
    end

    it "#fetch_multi raises" do
      expect { subject.fetch_multi("a", "b") }
        .to raise_error(::NotImplementedError)
    end
  end
end
