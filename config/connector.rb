# frozen_string_literal: true

# THE connector: which commands exist, and which of them are public.
#
# Extracted from config.ru so that serving and packaging read the same object.
# `requires_authentication` is decided here, at connect time, and it is what the
# packager derives the deployment's public list from — so the two cannot
# disagree about which commands may be called anonymously.
#
# Requiring this boots the app. That is right for a build step and for the local
# server; it is emphatically not right for a CDK app, which is why the plan also
# travels as build/plan.json.

require_relative "boot"
require "foobara/rack_connector"

# Commands that read public data are connected open; everything that writes, or
# that acts on the viewer's own records, requires authentication. This list is
# the only declaration of it anywhere.
PUBLIC_COMMANDS = [
  Posts::ListPosts, Posts::GetPost,
  Comments::ListThread,
  Reactions::MyReactions
].freeze

BOOKFACE_CONNECTOR = Foobara::CommandConnectors::Http::Rack.new(
  # instance_exec'd against the request: no argument, `self` is the request.
  # It reads what the handler (deployed) or the middleware (locally) resolved
  # from verified claims.
  authenticator: -> { Foobara::AWS.current_caller }
)

# Locally every domain is connected to one process; a packaged unit connects
# exactly one, which is what makes it a subset — the others are never
# registered, so there is nothing to refuse.
# Everything except the queue's own command, which is not reachable over HTTP:
# it is triggered by a message, and exposing it would let anyone run another
# user's reconciliation.
QUEUE_ONLY = [Profiles::ReconcileAuthorSnapshot, Uploads::VerifyUpload].freeze

[Posts, Comments, Reactions, Profiles, Uploads].each do |domain|
  domain.foobara_all_command.each do |command|
    next if QUEUE_ONLY.include?(command)
    # The generated <Command>Async classes are commands too, and enqueuing is
    # not something a client should be able to do directly.
    next if command.name.to_s.end_with?("Async")

    BOOKFACE_CONNECTOR.connect(command, requires_authentication: !PUBLIC_COMMANDS.include?(command))
  end
end
