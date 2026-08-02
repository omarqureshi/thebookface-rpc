# frozen_string_literal: true

# Per-invocation context, built from claims the API Gateway JWT authorizer has
# *already verified* against the Cognito user pool. No token parsing, no
# signature check, no OmniAuth, no session cookie — see DESIGN.md §3.
#
# This is invocation scope, not cold-start scope (Prospect DESIGN.md §6): a warm
# container serves many users, so nothing here may be memoized across
# invocations.

module Bookface
  # The signed-in user. Survives from the Rails app nearly unchanged, because it
  # was already a value object reconstructed from Cognito claims rather than a
  # persisted record — the one model that needed no porting.
  class Viewer < T::Struct
    const :sub,   String
    const :email, T.nilable(String)
    const :name,  String

    def initials
      name.to_s.split(/\s+/).filter_map { |part| part[0] }.first(2).join.upcase.presence || "?"
    end
  end

  class Context < T::Struct
    # nil for anonymous reads (feed and post views are public, as in Ability).
    #
    # KNOWN GAP: this stays nilable even inside `authenticated do … end`, because
    # Prospect v0 has no static context narrowing. Procedures that are guaranteed
    # a user still have to satisfy the type system about one. DESIGN.md §3.
    const :viewer, T.nilable(Viewer)

    class << self
      # API Gateway v2 JWT authorizer payload:
      #   event["requestContext"]["authorizer"]["jwt"]["claims"]
      def from_event(event)
        claims = event.dig("requestContext", "authorizer", "jwt", "claims")
        new(viewer: claims && viewer_from(claims))
      end

      # Local Rack transport has no authorizer in front of it, so dev/test inject
      # claims directly. Mirrors the Rails app's `sessions#dev_create` escape
      # hatch, which was likewise local-only.
      def from_dev_headers(headers)
        sub = headers["X-Dev-Sub"]
        return new(viewer: nil) unless sub

        new(viewer: Viewer.new(sub: sub, email: headers["X-Dev-Email"],
                               name: headers["X-Dev-Name"] || sub))
      end

      private

      def viewer_from(claims)
        Viewer.new(
          sub:   claims.fetch("sub"),
          email: claims["email"],
          # Cognito federates Google; "name" may be absent, fall back to email.
          name:  claims["name"].presence || claims["email"].to_s
        )
      end
    end

    def authenticated!
      viewer || raise(Schema::Errors::Unauthorized.new)
    end

    def ability
      # CanCanCan's Ability is unchanged from the Rails app. Authentication moved
      # to the edge; authorization stays in the domain. DESIGN.md §3.
      @ability ||= Ability.new(viewer)
    end
  end
end
