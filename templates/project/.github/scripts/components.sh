#!/usr/bin/env bash
# The project's components from .factory/config.yaml (factory docs/architecture.md,
# "Components"): what each part of the service is, where it is in the repository,
# where it runs. Validates them against what the factory supports and the host
# descriptors in hosts/<host>.yaml. Needs Ruby: runs in the workflows and on the
# host, not in the container.
#
#   components.sh <command> [config]     config defaults to the .factory/config.yaml
#                                        next to this script's .github/; "-" is stdin
#   list       one line per component: <name> <kind> <host> <path>
#   frontend   the frontend's <host> <spa>
#   owned      what the implementer owns besides the root rules: "<path>/" for a
#              component directory, "<path>" for a host's file
#   listed     host files whose changes are listed by line for "Where to look"
#   database   the database components' paths
#   deno       the paths of components tested with Deno
#
# Exits 1 with a message on a configuration the factory does not support.
set -euo pipefail

cmd="${1:?command}"
dir="$(cd "$(dirname "$0")" && pwd)"
config="${2:-$dir/../../.factory/config.yaml}"
[ "$config" = - ] || [ -f "$config" ] || { echo "no $config" >&2; exit 1; }

exec ruby -ryaml -e '
  cmd, config, dir = ARGV
  def die(m); abort("components: #{m} (factory docs/architecture.md, \"Components\")"); end
  begin
  c = YAML.safe_load(config == "-" ? STDIN.read : File.read(config))
  die "no configuration" unless c.is_a?(Hash)
  die "deploy is replaced by components.<name>.host and .spa" if c.key?("deploy")
  comps = c["components"]
  die "no components" unless comps.is_a?(Hash) && !comps.empty?
  hosts = {}
  list = comps.map do |name, v|
    die "#{name}: not a map" unless name.to_s.match?(/\A[a-z0-9-]+\z/) && v.is_a?(Hash)
    bad = v.keys - %w[kind host path spa]
    die "#{name}: unknown key #{bad.first}" unless bad.empty?
    kind, host, path = v.values_at("kind", "host", "path").map(&:to_s)
    die "#{name}: kind #{kind.inspect}, not frontend, api or database" unless %w[frontend api database].include?(kind)
    die "#{name}: host #{host.inspect}" unless host.match?(/\A[a-z0-9-]+\z/)
    die "#{name}: path #{path.inspect}" unless path == "." || (path.match?(%r{\A[a-z0-9][a-z0-9_./-]*\z}) && !path.split("/").include?("..") && !path.end_with?("/"))
    die "#{name}: spa is for a frontend" if v.key?("spa") && kind != "frontend"
    die "#{name}: spa is true or false" unless [nil, true, false].include?(v["spa"])
    if kind == "frontend"
      die "#{name}: a frontend is at path ." unless path == "."
      die "#{name}: no deploy script for host #{host}" unless File.file?("#{dir}/deploy/#{host}.sh")
    else
      f = "#{dir}/hosts/#{host}.yaml"
      die "#{name}: host #{host} has no #{kind}" unless File.file?(f)
      hosts[host] ||= YAML.safe_load(File.read(f))
      want = hosts[host].dig("paths", kind)
      die "#{name}: host #{host} has no #{kind}" unless want
      die "#{name}: a #{kind} on #{host} is at path #{want}" unless path == want
    end
    { name: name, kind: kind, host: host, path: path, spa: v["spa"] == true }
  end
  %w[frontend api database].each do |k|
    n = list.count { |x| x[:kind] == k }
    die "exactly one frontend" if k == "frontend" && n != 1
    die "at most one #{k}" if n > 1
  end
  other = list.reject { |x| x[:kind] == "frontend" }
  out = case cmd
    when "list" then list.map { |x| x.values_at(:name, :kind, :host, :path).join(" ") }
    when "frontend" then list.select { |x| x[:kind] == "frontend" }.map { |x| "#{x[:host]} #{x[:spa]}" }
    when "owned" then (other.map { |x| "#{x[:path]}/" } + other.flat_map { |x| hosts[x[:host]]["implementer_files"] || [] }).uniq
    when "listed" then other.flat_map { |x| hosts[x[:host]]["listed_files"] || [] }.uniq
    when "database" then other.select { |x| x[:kind] == "database" }.map { |x| x[:path] }
    when "deno" then other.select { |x| (hosts[x[:host]]["deno"] || []).include?(x[:kind]) }.map { |x| x[:path] }
    else die "unknown command #{cmd}"
  end
  rescue Psych::Exception, NoMethodError, TypeError => e
    die "unreadable: #{e.message.lines.first.strip}"
  end
  puts out
' "$cmd" "$config" "$dir"
