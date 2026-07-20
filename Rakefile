require "bundler/gem_tasks"
require "rspec/core/rake_task"

# Fast unit specs (fakeredis) — this is what runs by default and excludes the
# integration suite via .rspec's --exclude-pattern.
RSpec::Core::RakeTask.new(:spec)

# Integration specs that run against a real Redis Cluster. Requires a running
# cluster (see `bin/redis-cluster`) or REDIS_CLUSTER_NODES.
RSpec::Core::RakeTask.new(:integration) do |t|
  t.pattern = "spec/integration/**/*_spec.rb"
  t.rspec_opts = "--exclude-pattern ''"
end

task :default => :spec
