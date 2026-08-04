# frozen_string_literal: true

# An API Gateway v2 REQUEST authorizer that supports OPTIONAL authentication.
#
# Replaces Prospect::Authorizer, which was the last thing this branch still took
# from Prospect. The logic is the same idea, but it keys on Foobara's own command
# names rather than translating them, and it fixes the bug that made the original
# not work at all (see IDENTITY SOURCE below).
#
# WHY IT EXISTS. An API Gateway JWT authorizer is all-or-nothing: it rejects a
# request with no token, and a route without one receives no verified claims at
# all. There is no "verify if present". That breaks any command which is public
# but viewer-aware — here Posts::GetPost computes `editable`, and
# Reactions::MyReactions returns the caller's own reactions. Both are readable
# signed out, and both must know who is calling when someone is signed in.
#
# This sees rawPath, so it decides per COMMAND rather than per route. Routes stay
# greedy (/run/Posts/{proxy+}), which keeps the route count off API Gateway's
# per-API quota, and the public list is configuration rather than topology.
#
# IDENTITY SOURCE. The stack must NOT declare one. Naming an identity source
# makes it required: when the header is absent API Gateway answers 401 by itself
# and never invokes this function, so every anonymous caller is refused before
# the logic below can allow them. Prospect::CDK::Service declares
# "$request.header.Authorization" with a comment claiming the opposite; that is
# still shipped in the gem.
#
# Verification covers signature (RS256 against the issuer's JWKS), exp, iss and
# aud. JWKS is fetched once per execution environment — cold-start scope, never
# request scope.

require "json"
require "net/http"
require "uri"

module BookfaceAuthorizer
  class Unverified < StandardError; end

  class << self
    def handler(issuer:, audience:, anonymous: [], mount: "/run", jwks_url: nil)
      new_config(issuer:, audience:, anonymous:, mount:, jwks_url:)
    end

    def new_config(**) = Authorizer.new(**)
  end

  class Authorizer
    def initialize(issuer:, audience:, anonymous: [], mount: "/run", jwks_url: nil)
      @issuer = issuer.to_s.chomp("/")
      @audience = Array(audience)
      # Foobara's own full command names — "Posts::ListPosts" — so the list the
      # packager derives from the manifest travels here untranslated.
      @anonymous = Array(anonymous).map(&:to_s)
      @mount = mount
      @jwks_url = jwks_url || "#{@issuer}/.well-known/jwks.json"
    end

    # SIMPLE response format:
    #   { "isAuthorized" => bool, "context" => { ...claims } }
    # Anything in `context` reaches the command Lambda at
    # requestContext.authorizer.lambda, which is where the handler reads the
    # viewer from.
    def call(event, _lambda_context = nil)
      token = bearer(event)
      command = command_name(event)

      if token.nil?
        # No token at all. Allowed only where the command is declared public —
        # and it reaches the command with no claims, so a public viewer-aware
        # command correctly sees an anonymous caller.
        return allow({}) if anonymous?(command)

        return deny
      end

      begin
        allow(claims_from(token))
      rescue Unverified
        # A present-but-invalid token: expired, wrong audience, bad signature.
        #
        # On a public command this is treated as anonymous rather than refused —
        # someone whose session expired should still see the public feed, and
        # they gain nothing by it. On a gated command it is a refusal.
        anonymous?(command) ? allow({}) : deny
      end
    end

    private

    def allow(context) = { "isAuthorized" => true, "context" => stringify(context) }
    def deny = { "isAuthorized" => false }

    # API Gateway forwards only strings in the authorizer context.
    def stringify(claims)
      claims.to_h { |k, v| [k.to_s, v.is_a?(Array) ? v.join(",") : v.to_s] }
    end

    def anonymous?(command) = command && @anonymous.include?(command)

    # "/run/Posts/ListPosts" -> "Posts::ListPosts", which is exactly the key the
    # Foobara manifest files that command under. Deciding here rather than in
    # routing is what lets routes stay greedy.
    def command_name(event)
      path = event["rawPath"] || event.dig("requestContext", "http", "path") || ""
      parts = path.delete_prefix("#{@mount}/").split("/")
      parts.length == 2 ? parts.join("::") : nil
    end

    def bearer(event)
      headers = event["headers"] || {}
      raw = headers["authorization"] ||
            headers.find { |k, _| k.to_s.downcase == "authorization" }&.last
      return nil if raw.nil? || raw.empty?

      raw.to_s.sub(/\Abearer\s+/i, "").strip.then { |t| t.empty? ? nil : t }
    end

    def claims_from(token)
      require "jwt"

      payload, = JWT.decode(
        token, nil, true,
        algorithms: ["RS256"],
        jwks: jwks,
        iss: @issuer, verify_iss: true,
        aud: @audience, verify_aud: !@audience.empty?,
        verify_expiration: true
      )
      payload
    rescue Unverified
      raise # an unreachable JWKS is already the right failure
    rescue StandardError => e
      # Broad on purpose: the jwt gem raises several unrelated classes for
      # signature, key-lookup and claim failures, and every one of them means the
      # same thing here — this token is not trustworthy.
      raise Unverified, "#{e.class}: #{e.message}"
    end

    # Cold-start scope: fetched once per execution environment and reused across
    # invocations. Nothing request-specific may be cached here.
    def jwks
      @jwks ||= begin
        JSON.parse(Net::HTTP.get(URI(@jwks_url)), symbolize_names: true)
      rescue StandardError => e
        # An unreachable JWKS must not quietly become "everyone is anonymous".
        raise Unverified, "could not fetch JWKS from #{@jwks_url}: #{e.message}"
      end
    end
  end
end
