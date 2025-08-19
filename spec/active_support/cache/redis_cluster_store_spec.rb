require "spec_helper"

describe ::ActiveSupport::Cache::RedisClusterStore do
  let(:options) { {} }
  let(:redis) { subject.redis }
  let(:redis_proxy_method) do
    if Gem::Version.new(ActiveSupport.version) >= Gem::Version.new("7.1.0")
      :then
    else
      :with
    end
  end

  subject { described_class.new(*options) }

  describe "#delete_matched" do
    it "is not supported with redis cluster" do
      expect{ subject.delete_matched(nil, nil) }.to raise_error(::NotImplementedError, "Deleting keys with a matcher is not supported with redis cluster")
    end
  end

  describe "#fetch_multi" do
    it "is not supported with redis cluster" do
      expect{ subject.fetch_multi(nil) }.to raise_error(::NotImplementedError)
    end
  end

  describe "#increment" do
    let(:fake_client) { Redis.new }
    before { allow(subject).to receive(:redis).and_return(fake_client) }

    it "only returns the new value after being incremented with ttl" do
      expect(subject.increment("testing", 1, :expires_in => 5.minutes)).to eq(1)
      expect(subject.increment("testing", 5, :expires_in => 5.minutes)).to eq(6)
    end

    it "can increment without a ttl" do
      expect(fake_client).to_not receive(:pipelined).and_call_original
      expect(subject.increment("testing")).to eq(1)
    end

    it "can increment with a ttl" do
      expect(fake_client).to receive(:pipelined).and_yield
      expect(fake_client).to receive(:incrby).with("testing", 1)
      expect(fake_client).to receive(:expire).with("testing", 300)
      subject.increment("testing", 1, :expires_in => 5.minutes)
    end
  end

  describe "#write_entry" do
    it "returns false when a known error is raised" do
      expect(redis).to receive(redis_proxy_method).and_raise(::Redis::CommandError, "ERR Proxy error")
      expect(subject.write("test", "yolo")).to eq(false)
    end
  end

  describe "#read_entry" do
    it "returns false when a known error is raised" do
      expect(redis).to receive(redis_proxy_method).and_raise(::Redis::CommandError, "ERR Proxy error")
      expect(subject.read("test")).to eq(nil)
    end
  end

  describe "#delete_entry" do
    it "returns false when a known error is raised" do
      expect(redis).to receive(redis_proxy_method).and_raise(::Redis::CommandError, "ERR Proxy error")
      expect(subject.delete("test")).to eq(false)
    end
  end
end
