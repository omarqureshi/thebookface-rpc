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

# Local personas, as on the Prospect branch: no Cognito, so identity is a
# header. The authenticator returns whatever object the app wants as its
# current_user.
Viewer = Struct.new(:sub, :name)

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
    Thread.current[:bookface_viewer] =
      sub && Viewer.new(sub, env["HTTP_X_DEV_NAME"] || sub)
    @app.call(env)
  ensure
    Thread.current[:bookface_viewer] = nil
  end
end

# The authenticator is the gate for requires_authentication commands; the
# middleware above supplies identity to public ones, which the connector never
# authenticates. Both read the same headers.
def viewer_from(env)
  sub = env["HTTP_X_DEV_SUB"]
  sub && Viewer.new(sub, env["HTTP_X_DEV_NAME"] || sub)
end

connector = Foobara::CommandConnectors::Http::Rack.new(
  # instance_exec'd against the request: no argument, `self` is the request.
  authenticator: -> { viewer_from(env) }
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
run connector
