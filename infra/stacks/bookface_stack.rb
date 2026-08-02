# frozen_string_literal: true

require "aws-cdk-lib"
require_relative "../../app/app_router"

# The whole deployment. Note what is NOT here: no per-function definitions, no
# route wiring, no handler paths. `Prospect::CDK::Service` reads AppRouter's IR
# *in this process at synth time* and synthesises one Lambda per service plus the
# routes to reach them (Prospect DESIGN.md §6).
#
# Adding a procedure is a one-line change in a service file. This stack does not
# change.
class BookfaceStack < AWSCDK::Stack
  def initialize(scope, id, props = nil)
    super

    posts     = table(id: "Posts",     partition: "id")
    comments  = table(id: "Comments",  partition: "post_id", sort: "path")
    reactions = table(id: "Reactions", partition: "post_id", sort: "target_user")
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

      # Measured, not guessed: 1024MB roughly halves cold start against 512MB at
      # near-identical GB-seconds. Prospect DESIGN.md §6.
      defaults: { memory_size: 1024, timeout: AWSCDK::Duration.seconds(10) },

      authorizer: {
        kind:      :jwt,
        issuer:    pool.user_pool_provider_url,
        audience:  [client.user_pool_client_id],
        # Public reads: the feed and post views work signed out, matching
        # Ability's `can :read, [Post, Comment]`.
        anonymous: %w[posts.feed posts.get comments.thread reactions.mine]
      },

      environment: {
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

    # Async denormalization fan-out. A Lambda, but an event handler rather than
    # a procedure — deliberately outside the router. DESIGN.md §5.
    reconcile_queue(profiles, posts, comments)

    AWSCDK::CfnOutput.new(self, "ApiUrl", { value: api.url })
  end

  private

  def table(id:, partition:, sort: nil)
    props = {
      partition_key:  { name: partition, type: AWSCDK::DynamoDB::AttributeType::STRING },
      removal_policy: AWSCDK::RemovalPolicy::DESTROY
    }
    props[:sort_key] = { name: sort, type: AWSCDK::DynamoDB::AttributeType::STRING } if sort
    AWSCDK::DynamoDB::TableV2.new(self, id, props)
  end

  def reconcile_queue(profiles, posts, comments)
    queue = AWSCDK::SQS::Queue.new(self, "ProfileReconcile", {
      visibility_timeout: AWSCDK::Duration.seconds(120)
    })
    # ... handler wiring omitted from the skeleton; it is not a Prospect service.
    [ profiles, posts, comments ] && queue
  end
end
