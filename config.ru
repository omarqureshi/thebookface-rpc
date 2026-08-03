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

connector = Foobara::CommandConnectors::Http::Rack.new

# One line per deployment unit. A packaging step would generate exactly this,
# with the domain chosen per unit.
connector.connect(Posts)

use ExtractViewer
run connector
