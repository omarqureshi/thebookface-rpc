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

# Fetched live from the running connector by default, for the same reason
# script/generate_ts.rb does: a manifest snapshot on disk goes stale silently,
# and the failure looks like a packaging bug rather than an old file. Pass a
# path to use a snapshot deliberately.
#
#   script/dev.sh serve    # then
#   bundle exec ruby script/package_from_manifest.rb
manifest =
  if ARGV[0]
    JSON.parse(File.read(ARGV[0]))
  else
    require "net/http"
    url = URI(ENV.fetch("BOOKFACE_MANIFEST", "http://localhost:9292/manifest"))
    JSON.parse(Net::HTTP.get(url))
  end

# --- units, derived entirely from the manifest -------------------------------
app_commands = manifest["command"].reject { |_, c| c["domain"].to_s.start_with?("Foobara", "global") }
# A domain with no commands (Shared holds only types) yields no unit — units
# come from commands, not from domains.
units = app_commands.group_by { |_, c| c["domain"] }.map do |domain, cmds|
  { name: domain.downcase,
    domain: domain,
    commands: cmds.map(&:first),
    # The route has to match what the connector actually serves, which is
    # /run/<Domain>/<Command> — the command's scoped_full_path under the
    # connector's prefix. Prospect's /rpc/<service>/<procedure> was the same
    # shape by coincidence, not by agreement, so this is derived rather than
    # assumed.
    route: "/run/#{domain}/{proxy+}",
    # Straight from the manifest: no hand-maintained anonymous: list.
    #
    # `requires_authentication`, NOT `authenticator` — the latter says which
    # authenticator applies, which is a different question and is absent
    # entirely when identity comes from middleware.
    public: cmds.reject { |_, c| c["requires_authentication"] }.map(&:first) }
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

    # Both are needed, and this is the optional-auth gap made concrete:
    #
    #   the authenticator is the GATE. requires_authentication: true calls it,
    #   and without one the connector raises on nil.
    #   the thread-local is IDENTITY for public commands, which the connector
    #   skips authenticating entirely — so a public but viewer-aware command
    #   would otherwise never learn who is calling.
    #
    # They read the same headers. Deployed, both would read the authorizer's
    # verified claims instead.
    module BookfaceAuth
      VIEWER = Struct.new(:sub, :name)

      def self.viewer_from(env)
        sub  = env["HTTP_X_DEV_SUB"]
        name = env["HTTP_X_DEV_NAME"]
        unless sub
          cookies = Rack::Utils.parse_cookies(env)
          sub  = cookies["dev_sub"]
          name = cookies["dev_name"]
        end
        sub && VIEWER.new(sub, name || sub)
      end
    end

    CONNECTOR = Foobara::CommandConnectors::Http::Rack.new(
      # instance_exec'd against the request, so this takes no argument and
      # `self` is the request itself.
      authenticator: -> { BookfaceAuth.viewer_from(env) }
    )
    #{unit[:domain]}.foobara_all_command.each do |command|
      CONNECTOR.connect(
        command,
        requires_authentication: !#{unit[:public].inspect}.include?(command.full_command_name)
      )
    end

    def handle(event:, context:)
      # An API Gateway v2 event, adapted to a Rack env for the connector.
      env = {
        "REQUEST_METHOD" => event.dig("requestContext", "http", "method") || "POST",
        # Passed through unchanged. Prospect mounted each service at its own
        # prefix and stripped it; here the route IS the connector's own path
        # (/run/<Domain>/<Command>), so stripping would break dispatch.
        "PATH_INFO"      => event["rawPath"] || "",
        "QUERY_STRING"   => event["rawQueryString"].to_s,
        "rack.input"     => StringIO.new(event["body"].to_s),
        "rack.errors"    => $stderr
      }
      (event["headers"] || {}).each { |k, v| env["HTTP_" + k.upcase.tr("-", "_")] = v }

      # Identity extraction has to be generated too: it is connector wiring, not
      # domain logic, and locally it lives in Rack middleware that a Lambda
      # handler does not inherit. Deployed this would read the authorizer's
      # claims rather than dev headers.
      Thread.current[:bookface_viewer] = BookfaceAuth.viewer_from(env)

      begin
        status, headers, body = CONNECTOR.call(env)
        { "statusCode" => status, "headers" => headers, "body" => body.join }
      ensure
        Thread.current[:bookface_viewer] = nil
      end
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
