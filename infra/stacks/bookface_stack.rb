# frozen_string_literal: true

require "aws-cdk-lib"
require "prospect/cdk"
require_relative "../../app/app_router"

# The whole deployment. Note what is NOT here: no per-function definitions, no
# route wiring, no handler paths. `Prospect::CDK::Service` reads AppRouter's IR
# *in this process at synth time* and synthesises one Lambda per service plus the
# routes to reach them (Prospect DESIGN.md §6).
#
# Adding a procedure is a one-line change in a service file. This stack does not
# change.
#
# Artifacts must be built first — the construct reads `code_root`, it does not
# create it:
#
#   bundle exec ruby script/package.rb
#   cd infra && bundle exec cdk deploy
class BookfaceStack < AWSCDK::Stack
  # `stage` is a separate keyword rather than a props key: AWSCDK::StackProps is
  # strict and rejects unknown keys, so app config cannot ride along inside it.
  def initialize(scope, id, props = nil, stage: "staging")
    super(scope, id, props)

    posts     = table(id: "Posts",     partition: "id")
    comments  = table(id: "Comments",  partition: "post_id", sort: "path")
    # Sort key is `sk` ("<user_sub>#<target>"), matching Reaction's `range :sk`.
    # An earlier draft said `target_user`, which would have made every reaction
    # write fail against the deployed table.
    reactions = table(id: "Reactions", partition: "post_id", sort: "sk")
    profiles  = table(id: "Profiles",  partition: "sub")

    media = AWSCDK::S3::Bucket.new(self, "Media", {
      removal_policy: AWSCDK::RemovalPolicy::DESTROY,
      cors: [{
        allowed_methods: [AWSCDK::S3::HttpMethods::POST],
        allowed_origins: ["*"],
        allowed_headers: ["*"]
      }]
    })

    # Cognito stays the identity provider, but the OIDC dance leaves the API —
    # API Gateway verifies the JWT before Lambda is ever invoked, so no service
    # carries OmniAuth or a session secret. DESIGN.md §3.
    pool   = AWSCDK::Cognito::UserPool.new(self, "Users", { self_sign_up_enabled: false })
    client = pool.add_client("Web", { generate_secret: false })

    api = Prospect::CDK::Service.new(self, "Api", {
      router:       Bookface::AppRouter,
      granularity:  :per_router,        # one Lambda per service — the brief
      architecture: AWSCDK::Lambda::Architecture.X86_64,
      runtime:      AWSCDK::Lambda::Runtime.RUBY_4_0,

      # Built by script/package.rb. The construct reads this; it does not build.
      code_root: File.expand_path("../../build", __dir__),

      # Measured, not guessed: 1024MB roughly halves cold start against 512MB at
      # near-identical GB-seconds. Prospect DESIGN.md §6.
      defaults: { memory_size: 1024, timeout_seconds: 10 },

      authorizer: {
        # :lambda, not :jwt. An API Gateway JWT authorizer cannot express
        # optional auth: a route without one receives no verified claims at all,
        # so `posts.get` would report editable: false even for the author and
        # `reactions.mine` would always be empty. The Lambda authorizer decides
        # per procedure from rawPath, which also lets routes stay greedy.
        kind:     :lambda,
        issuer:   pool.user_pool_provider_url,
        audience: [client.user_pool_client_id],
        # Public reads, matching Ability's `can :read, [Post, Comment]`.
        #
        # Public, but still viewer-aware when a token is present.
        anonymous: %w[posts.feed posts.get comments.thread reactions.mine]
      },

      environment: {
        "BOOKFACE_ENV"    => stage,
        "POSTS_TABLE"     => posts.table_name,
        "COMMENTS_TABLE"  => comments.table_name,
        "REACTIONS_TABLE" => reactions.table_name,
        "PROFILES_TABLE"  => profiles.table_name,
        "MEDIA_BUCKET"    => media.bucket_name
      }
    })

    # Least-privilege per service, which is the payoff for one Lambda per
    # controller: `uploads` can sign S3 URLs but cannot read a post, and
    # `reactions` never touches the media bucket.
    posts.grant_read_write_data(api.function(:posts))
    posts.grant_read_data(api.function(:comments))
    posts.grant_read_data(api.function(:reactions))
    comments.grant_read_write_data(api.function(:comments))
    comments.grant_read_write_data(api.function(:posts))    # destroy_with_thread!
    reactions.grant_read_write_data(api.function(:reactions))
    reactions.grant_read_write_data(api.function(:posts))   # destroy_with_thread!
    profiles.grant_read_write_data(api.function(:profiles))
    profiles.grant_read_data(api.function(:posts))          # author snapshot
    profiles.grant_read_data(api.function(:comments))
    media.grant_put(api.function(:uploads))
    media.grant_delete(api.function(:posts))                # reap on delete

    site = deploy_site(api)

    AWSCDK::CfnOutput.new(self, "ApiUrl", { value: api.url })
    AWSCDK::CfnOutput.new(self, "SiteUrl", { value: "https://#{site.distribution_domain_name}" })
    AWSCDK::CfnOutput.new(self, "UserPoolId", { value: pool.user_pool_id })
    AWSCDK::CfnOutput.new(self, "UserPoolClientId", { value: client.user_pool_client_id })
  end

  private

  # The SPA on S3 behind CloudFront, with the API on the SAME distribution at
  # /rpc/*. Two things fall out of that, both of which matter:
  #
  #   * The client is same-origin, so there is no CORS and no preflight. That
  #     matters specifically because every request carries X-Prospect-Schema,
  #     a custom header — which would otherwise make each one non-simple and
  #     add an OPTIONS round trip.
  #   * `createClient({ url: "/rpc" })` needs no build-time configuration. The
  #     bundle is identical in every environment, which is also why the local
  #     Vite proxy points /rpc at the API: dev and production agree.
  #
  # Assets must be built first, the same way Lambda artifacts must be:
  #
  #   cd web && npm run build
  def deploy_site(api)
    bucket = AWSCDK::S3::Bucket.new(self, "Site", {
      removal_policy: AWSCDK::RemovalPolicy::DESTROY,
      auto_delete_objects: true
    })

    # The API Gateway URL is https://<id>.execute-api.<region>.amazonaws.com/ —
    # CloudFront wants the bare host.
    api_domain = AWSCDK::Fn.select(2, AWSCDK::Fn.split("/", api.url))

    distribution = AWSCDK::CloudFront::Distribution.new(self, "Site" + "Cdn", {
      default_root_object: "index.html",

      default_behavior: {
        origin: AWSCDK::CloudFrontOrigins::S3BucketOrigin.with_origin_access_control(bucket),
        viewer_protocol_policy: AWSCDK::CloudFront::ViewerProtocolPolicy::REDIRECT_TO_HTTPS
      },

      additional_behaviors: {
        # Never cached, all methods forwarded, and the Host header dropped —
        # API Gateway rejects a request whose Host is the CloudFront domain.
        # ALL_VIEWER_EXCEPT_HOST_HEADER also forwards Authorization and
        # X-Prospect-Schema, which the authorizer and the drift check need.
        "/rpc/*" => {
          origin: AWSCDK::CloudFrontOrigins::HttpOrigin.new(api_domain),
          viewer_protocol_policy: AWSCDK::CloudFront::ViewerProtocolPolicy::HTTPS_ONLY,
          allowed_methods: AWSCDK::CloudFront::AllowedMethods.ALLOW_ALL,
          cache_policy: AWSCDK::CloudFront::CachePolicy.CACHING_DISABLED,
          origin_request_policy:
            AWSCDK::CloudFront::OriginRequestPolicy.ALL_VIEWER_EXCEPT_HOST_HEADER
        }
      },

      # THE HISTORY FALLBACK. /posts/:id is a client route with no object behind
      # it, so S3 answers 403 (404 only when ListBucket is granted, which OAC
      # does not). Both are rewritten to index.html with a 200 so the router can
      # read the path. Without this a cold load or a refresh of any route below
      # / returns an error page.
      error_responses: [
        { http_status: 403, response_http_status: 200,
          response_page_path: "/index.html", ttl: AWSCDK::Duration.seconds(0) },
        { http_status: 404, response_http_status: 200,
          response_page_path: "/index.html", ttl: AWSCDK::Duration.seconds(0) }
      ]
    })

    dist = File.expand_path("../../web/dist", __dir__)
    if Dir.exist?(dist)
      AWSCDK::S3Deployment::BucketDeployment.new(self, "SiteAssets", {
        sources: [AWSCDK::S3Deployment::Source.asset(dist)],
        destination_bucket: bucket,
        distribution: distribution,
        # index.html must never be cached, or a deploy leaves browsers holding
        # a bundle that references hashed assets which no longer exist.
        distribution_paths: ["/index.html", "/"]
      })
    else
      AWSCDK::Annotations.of(self).add_warning(
        "web/dist not found — the site bucket will be empty. Run `cd web && npm run build`."
      )
    end

    distribution
  end

  def table(id:, partition:, sort: nil)
    props = {
      partition_key:  { name: partition, type: AWSCDK::DynamoDB::AttributeType::STRING },
      removal_policy: AWSCDK::RemovalPolicy::DESTROY
    }
    props[:sort_key] = { name: sort, type: AWSCDK::DynamoDB::AttributeType::STRING } if sort
    AWSCDK::DynamoDB::TableV2.new(self, id, props)
  end
end
