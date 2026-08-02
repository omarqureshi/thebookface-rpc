# frozen_string_literal: true

# Typed errors — part of the contract, declared per procedure via `errors:`.
#
# In Rails these were all `redirect_to root_path, alert: "…"`. Control flow by
# redirect can't cross an RPC boundary, and a flash string isn't something a
# client can branch on. Declaring them puts each one in the IR, so the generated
# TypeScript gets a discriminated union and the Ruby client gets real exception
# classes. See Prospect DESIGN.md §7.

module Bookface
  module Schema
    module Errors
      # These three are Prospect's, aliased — not ours.
      #
      # They were originally redeclared here as `< Prospect::Error`, which
      # silently lost their HTTP statuses: an unauthenticated call came back 422
      # instead of 401, because a bare subclass inherits the generic default.
      # Caught by the first request the local server ever served.
      #
      # That answers DESIGN.md §6.4 — Prospect should own the errors every app
      # needs, and apps should alias rather than redeclare.
      NotFound     = Prospect::NotFound      # 404 — resource, id
      Unauthorized = Prospect::Unauthorized  # 401 — no verified JWT reached us
      Forbidden    = Prospect::Forbidden     # 403 — action, resource

      # Model validation failure — replaces `render :edit, status: :unprocessable_entity`.
      # Shape matches ActiveModel: { field => [messages] }.
      #
      # Note this is a *map*, keyed by field name. Field names are data here, not
      # struct members, so the TS emitter must not camelize the keys — the same
      # hazard as reaction_counts (DESIGN.md §4).
      class ValidationFailed < Prospect::Error
        const :errors, T::Hash[String, T::Array[String]]
      end

      # "That reaction isn't allowed." — ReactionsController rescues ArgumentError
      # from Reaction.toggle for an emoji outside the allowed set.
      class UnsupportedReaction < Prospect::Error
        const :emoji, String
      end

      # "unsupported type" — MediaStorage.allowed_type? rejected the content type.
      class UnsupportedMediaType < Prospect::Error
        const :content_type, String
      end
    end
  end
end
