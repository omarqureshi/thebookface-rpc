# frozen_string_literal: true
#
# Prospect::Package, with the router swapped for a Foobara manifest. The point
# is to find out how much of the packaging machinery is actually coupled to
# Prospect's IR versus to the shape of "units, routes and a handler per unit".
#
#   bundle exec ruby script/package_from_manifest.rb

require "json"
require "fileutils"
require "digest"

ROOT  = File.expand_path("..", __dir__)
OUT   = File.join(ROOT, "build")
IMAGE = "public.ecr.aws/sam/build-ruby4.0"

manifest = JSON.parse(File.read(ARGV[0] || "/tmp/bookface-manifest.json"))

# --- units, derived entirely from the manifest -------------------------------
app_commands = manifest["command"].reject { |_, c| c["domain"].to_s.start_with?("Foobara", "global") }
units = app_commands.group_by { |_, c| c["domain"] }.map do |domain, cmds|
  { name: domain.downcase,
    domain: domain,
    commands: cmds.map(&:first),
    route: "/rpc/#{domain.downcase}/{proxy+}",
    # Straight from the manifest: no hand-maintained anonymous: list.
    public: cmds.reject { |_, c| c["authenticator"] }.map(&:first) }
end

# --- one handler per unit ----------------------------------------------------
# `connect(Domain)` is what makes a unit a subset: the other domains are never
# registered, so there is nothing to refuse.
def handler_source(unit)
  <<~RUBY
    # Generated from the Foobara manifest. Do not edit.
    #
    # Serves: #{unit[:commands].join(', ')}
    require_relative "vendor/bundle/bundler/setup"
    require_relative "config/boot"
    require "foobara/rack_connector"

    CONNECTOR = Foobara::CommandConnectors::Http::Rack.new
    CONNECTOR.connect(#{unit[:domain]})

    def handle(event:, context:)
      # An API Gateway v2 event, adapted to a Rack env for the connector.
      env = {
        "REQUEST_METHOD" => event.dig("requestContext", "http", "method") || "POST",
        "PATH_INFO"      => (event["rawPath"] || "").sub(%r{\\A/rpc/[^/]+}, ""),
        "QUERY_STRING"   => event["rawQueryString"].to_s,
        "rack.input"     => StringIO.new(event["body"].to_s),
        "rack.errors"    => $stderr
      }
      (event["headers"] || {}).each { |k, v| env["HTTP_" + k.upcase.tr("-", "_")] = v }
      status, headers, body = CONNECTOR.call(env)
      { "statusCode" => status, "headers" => headers, "body" => body.join }
    end
  RUBY
end

FileUtils.mkdir_p(OUT)
units.each do |unit|
  dir = File.join(OUT, unit[:name])
  FileUtils.rm_rf(dir); FileUtils.mkdir_p(dir)
  %w[app config].each { |s| FileUtils.cp_r(File.join(ROOT, s), dir) }
  File.write(File.join(dir, "handler.rb"), handler_source(unit))

  gemfile = File.join(ROOT, "units", "#{unit[:name]}.gemfile")
  abort "no gemfile for unit #{unit[:name]}" unless File.exist?(gemfile)

  vendor = File.join(OUT, ".bundles", Digest::SHA256.hexdigest(File.read(gemfile))[0, 16])
  unless File.directory?(File.join(vendor, "bundler"))
    FileUtils.mkdir_p(vendor)
    ok = system("docker", "run", "--rm", "--platform", "linux/amd64",
                "--user", "#{Process.uid}:#{Process.gid}", "-e", "HOME=/tmp",
                "-v", "#{ROOT}:#{ROOT}", "-v", "#{vendor}:/vendor", "-w", ROOT,
                "--entrypoint", "bash", IMAGE, "-c",
                "set -e; export BUNDLE_GEMFILE=#{gemfile} BUNDLE_PATH=/vendor; " \
                "bundle install --standalone", out: File::NULL)
    abort "bundle install failed for #{unit[:name]}" unless ok
  end
  FileUtils.mkdir_p(File.join(dir, "vendor"))
  FileUtils.cp_r(vendor, File.join(dir, "vendor/bundle"))

  puts "built #{unit[:name]}: #{unit[:commands].length} commands, route #{unit[:route]}, " \
       "public #{unit[:public].length}"
end
