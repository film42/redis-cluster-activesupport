require "integration_helper"

# End-to-end coverage against a live Redis Cluster. Each example uses a unique
# namespace so cases stay isolated without a cross-slot FLUSHALL.
describe ::ActiveSupport::Cache::RedisClusterStore, :integration do
  let(:namespace) { "rcas-int:#{SecureRandom.hex(6)}" }

  subject do
    described_class.new(
      redis: RedisClusterIntegration.new_client,
      namespace: namespace,
      pool: false
    )
  end

  # The store's own client, used to assert server-side state like TTLs on the
  # namespaced key.
  def raw_key(key)
    "#{namespace}:#{key}"
  end

  describe "read/write round-trip" do
    it "stores and fetches a value" do
      expect(subject.write("greeting", "hello")).to be_truthy
      expect(subject.read("greeting")).to eq("hello")
    end

    it "returns nil for a missing key" do
      expect(subject.read("does-not-exist")).to be_nil
    end

    it "round-trips complex objects" do
      value = { "a" => 1, "b" => [1, 2, 3] }
      subject.write("obj", value)
      expect(subject.read("obj")).to eq(value)
    end

    it "reports existence" do
      subject.write("present", "1")
      expect(subject.exist?("present")).to be(true)
      expect(subject.exist?("absent")).to be(false)
    end
  end

  describe "expiry" do
    it "applies expires_in as a TTL on the underlying key" do
      subject.write("ttl-key", "v", expires_in: 5.minutes)
      expect(subject.redis.ttl(raw_key("ttl-key"))).to be_between(1, 300)
    end
  end

  describe "#fetch" do
    it "writes and returns the block value on a miss" do
      calls = 0
      result = subject.fetch("computed") { calls += 1; "value" }
      expect(result).to eq("value")
      # Second fetch is served from the cache, block not re-run.
      result = subject.fetch("computed") { calls += 1; "other" }
      expect(result).to eq("value")
      expect(calls).to eq(1)
    end
  end

  describe "#increment" do
    it "returns only the new value when given a ttl" do
      expect(subject.increment("counter", 1, expires_in: 5.minutes)).to eq(1)
      expect(subject.increment("counter", 5, expires_in: 5.minutes)).to eq(6)
    end

    it "sets a ttl on the counter key" do
      subject.increment("counter-ttl", 1, expires_in: 5.minutes)
      expect(subject.redis.ttl(raw_key("counter-ttl"))).to be_between(1, 300)
    end

    it "increments without a ttl (persistent key)" do
      expect(subject.increment("counter-no-ttl", 2)).to eq(2)
      expect(subject.redis.ttl(raw_key("counter-no-ttl"))).to eq(-1)
    end
  end

  describe "#decrement" do
    it "decrements a counter" do
      subject.increment("dec", 10)
      expect(subject.decrement("dec", 3)).to eq(7)
    end
  end

  describe "#delete" do
    it "removes a key" do
      subject.write("to-delete", "v")
      # 7.0 returns the raw redis DEL count (1); 7.1+ returns a boolean.
      expect(subject.delete("to-delete")).to be_truthy
      expect(subject.read("to-delete")).to be_nil
    end
  end

  describe "unsupported multi-key operations" do
    # These are guarded because their keys may hash to different shards. Verify
    # against a real cluster that the guards fire rather than silently degrading
    # (e.g. read_multi's failsafe would otherwise swallow the CROSSSLOT error).
    it "raises on #delete_matched (KEYS/SCAN not supported across a cluster)" do
      expect { subject.delete_matched("*") }
        .to raise_error(::NotImplementedError)
    end

    it "raises on #read_multi (MGET across slots not supported)" do
      expect { subject.read_multi("a", "b") }
        .to raise_error(::NotImplementedError)
    end

    it "raises on #write_multi (MSET across slots not supported)" do
      expect { subject.write_multi("a" => 1, "b" => 2) }
        .to raise_error(::NotImplementedError)
    end

    it "raises on #fetch_multi (MULTI across slots not supported)" do
      expect { subject.fetch_multi("a", "b") }
        .to raise_error(::NotImplementedError)
    end
  end
end
