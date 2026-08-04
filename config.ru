# frozen_string_literal: true

# The Foobara Rack connector IS a Rack app, so the same object serves locally
# and (via an event adapter) inside Lambda.
#
# `connect(Posts)` registers exactly that domain's commands — which is how a
# per-domain deployment unit gets its subset. A unit does not have to *refuse*
# other domains' commands, as Prospect::Lambda does; it simply never registers
# them.

require_relative "config/boot"
require "foobara/rack_connector"
require "fileutils"

# Dev-only object store, carried over from the Prospect branch unchanged: the
# image flow works end to end without S3 or LocalStack. MediaStorage#presigned_upload
# points the browser here; the bytes land on disk and are served back. Deployed,
# both are S3 and none of this exists.
MEDIA_DIR = File.expand_path("tmp/media", __dir__)
FileUtils.mkdir_p(MEDIA_DIR)

DEV_MEDIA = lambda do |env|
  req = Rack::Request.new(env)
  # path_info, not path: under `map` the latter still carries "/media". And
  # unescaped, because a persona sub contains "|", which the browser percent-
  # encodes — so the stored filename would never match.
  key = Rack::Utils.unescape(req.path_info).sub(%r{\A/}, "")

  case req.request_method
  when "POST"
    # Mimics a presigned S3 POST: the key travels in the form, not the path.
    key = req.params["key"].to_s
    next [400, {}, ["missing key"]] if key.empty?

    file = req.params["file"]
    bytes = file.respond_to?(:[]) ? file[:tempfile].read : file.to_s
    File.binwrite(File.join(MEDIA_DIR, key.tr("/", "_")), bytes)
    [204, { "access-control-allow-origin" => "*" }, []]
  when "GET"
    path = File.join(MEDIA_DIR, key.tr("/", "_"))
    next [404, {}, ["not found"]] unless File.exist?(path)

    [200, { "content-type" => "image/jpeg" }, [File.binread(path)]]
  when "OPTIONS"
    [204, { "access-control-allow-origin" => "*",
            "access-control-allow-headers" => "*",
            "access-control-allow-methods" => "POST, GET, OPTIONS" }, []]
  else
    [405, {}, []]
  end
end

# Identity is extracted by middleware, not by the connector's authenticator,
# for a reason worth recording: Foobara authenticates only commands that
# declare `requires_authentication`, so a command that is PUBLIC but
# viewer-aware never learns who is calling.
#
# That is the same optional-auth gap as API Gateway's JWT authorizer, one layer
# up — and bookface has four such commands (a feed that marks your own posts
# editable, your own reactions). Middleware always runs, so the command can
# decide.
#
# The caller then reaches commands through a thread-local, which is a spike
# shortcut: Foobara keeps the caller out of `execute` on purpose, and the
# idiomatic answer is a request mutator injecting it as an input, the way the
# auth demo's SetRefreshTokenFromCookie injects a token.
class ExtractViewer
  def initialize(app) = @app = app

  def call(env)
    sub = env["HTTP_X_DEV_SUB"]
    Foobara::AWS.current_caller = BookfaceAuth.viewer_from(env)
    @app.call(env)
  ensure
    Foobara::AWS.current_caller = nil
  end
end

# The authenticator is the gate for requires_authentication commands; the
# middleware above supplies identity to public ones, which the connector never
# authenticates. Both read the same headers.
# A module, not a top-level def: config.ru is instance_eval'd by Rack::Builder,
# so a bare `def` lands on the Builder and is invisible to the authenticator,
# which is instance_exec'd against the request.
module BookfaceAuth
  def self.viewer_from(env)
    # Headers for curl and for cucumber steps that call commands directly; a
    # cookie for the browser, because the generated SDK sends
    # credentials: "include" but offers no hook for custom headers.
    sub  = env["HTTP_X_DEV_SUB"]
    name = env["HTTP_X_DEV_NAME"]

    unless sub
      cookies = Rack::Utils.parse_cookies(env)
      sub  = cookies["dev_sub"]
      name = cookies["dev_name"]
    end

    # The same builder the deployed handler uses, so local and deployed identity
    # cannot drift.
    sub && Foobara::AWS.caller_builder.call({ "sub" => sub, "name" => name })
  end
end

connector = Foobara::CommandConnectors::Http::Rack.new(
  # instance_exec'd against the request: no argument, `self` is the request.
  authenticator: -> { Foobara::AWS.current_caller }
)

# One line per deployment unit. Locally every domain is connected to one
# process; a packaged unit connects exactly one, which is what makes it a
# subset — the others are never registered, so there is nothing to refuse.
# Commands that read public data are connected open; everything that writes, or
# that acts on the viewer's own records, requires authentication. This is the
# single declaration the manifest's `authenticator` field reflects — so the
# packager derives the public list rather than being handed one.
PUBLIC_COMMANDS = [
  Posts::ListPosts, Posts::GetPost,
  Comments::ListThread,
  Reactions::MyReactions
].freeze

[Posts, Comments, Reactions, Profiles, Uploads].each do |domain|
  domain.foobara_all_command.each do |command|
    connector.connect(command, requires_authentication: !PUBLIC_COMMANDS.include?(command))
  end
end

use ExtractViewer

# /up is served here rather than by the connector: Prospect::RackApp provided
# one, and the dev and cucumber scripts poll it to know the server is ready.
run(Rack::Builder.app do
  map("/media") { run DEV_MEDIA }
  map("/up") { run ->(_env) { [200, { "content-type" => "text/plain" }, ["ok"]] } }
  run connector
end)
