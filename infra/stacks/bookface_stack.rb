# frozen_string_literal: true

require "json"
require "aws-cdk-lib"
require "constructs"

# The whole deployment, driven by build/units.json.
#
# On the Prospect branch this stack passed `router: Bookface::AppRouter` to
# Prospect::CDK::Service, which read the router's IR *in this process* and
# synthesised the functions and routes from it. That construct cannot be reused
# here, because its input is a Prospect router — but almost nothing in it was
# actually about Prospect. Swapping the router for the manifest is the same
# exercise as script/package_from_manifest.rb, and it lands in the same place:
# the topology is "units, routes, and a handler per unit", and that is all a
# deployment needs to know.
#
# So this reads the description the packager emits rather than an IR. That has
# a property the router-driven version did not: synthesis depends only on what
# was built, so `cdk synth` cannot create a route to a Lambda whose code is
# missing, and it needs neither a running server nor the app's bundle.
#
#   script/dev.sh serve                              # serves /manifest
#   bundle exec ruby script/package_from_manifest.rb # writes build/ + units.json
#   cd infra && bundle exec cdk deploy
class BookfaceStack < AWSCDK::Stack
  BUILD = File.expand_path("../../build", __dir__)

  # The ONE thing the manifest cannot supply.
  #
  # Prospect declared this per procedure — `deploy memory: 1769, timeout: 60` on
  # posts.destroy, which fans out across a whole thread — and the construct took
  # the largest value in a unit. Foobara's manifest has no place for deployment
  # metadata: it describes what a command IS, not how it should be run, which is
  # a defensible line to draw and a real gap for this use. Absent a Foobara
  # extension, it has to live somewhere out-of-band, so it lives here where it
  # is at least visible rather than in a heuristic.
  SIZING = {
    # destroy_with_thread! deletes a post, its whole comment tree and every
    # reaction on any of them, so it is the one unit that needs headroom.
    "posts" => { memory_size: 1769, timeout_seconds: 60 }
  }.freeze
  DEFAULT_SIZING = { memory_size: 1024, timeout_seconds: 10 }.freeze

  # `stage` is a separate keyword rather than a props key: AWSCDK::StackProps is
  # strict and rejects unknown keys, so app config cannot ride along inside it.
  def initialize(scope, id, props = nil, stage: "staging")
    super(scope, id, props)

    @plan = JSON.parse(File.read(File.join(BUILD, "units.json")))

    posts     = table(id: "Posts",     partition: "id")
    comments  = table(id: "Comments",  partition: "post_id", sort: "path")
    # Sort key is `sk` ("<user_sub>#<target>"), matching Reaction's `range :sk`.
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

    # Cognito stays the identity provider, and the OIDC dance still leaves the
    # API: the authorizer verifies the JWT before any command Lambda is
    # invoked, so no unit carries OmniAuth or a session secret. Foobara's
    # `requires_authentication` is the in-process gate; this is the edge one,
    # and both are fed by the same manifest field.
    pool   = AWSCDK::Cognito::UserPool.new(self, "Users", { self_sign_up_enabled: false })
    client = pool.add_client("Web", { generate_secret: false })

    environment = {
      "BOOKFACE_ENV"    => stage,
      "POSTS_TABLE"     => posts.table_name,
      "COMMENTS_TABLE"  => comments.table_name,
      "REACTIONS_TABLE" => reactions.table_name,
      "PROFILES_TABLE"  => profiles.table_name,
      "MEDIA_BUCKET"    => media.bucket_name
    }

    # The API and its functions hang off a child construct rather than the stack
    # itself, which is what Prospect::CDK::Service gave for free: at stack level
    # the `comments` function and the `Comments` table both want the logical id
    # "Comments" and synthesis fails. Nesting also keeps the generated ids
    # (Api/Posts, Api/Comments) matching the Prospect branch's template.
    @scope = Constructs::Construct.new(self, "Api")

    @api = AWSCDK::APIGatewayv2::HttpAPI.new(@scope, "Api", {})
    authorizer = build_authorizer(pool, client)

    @functions = {}
    @plan.fetch("units").each { |unit| add_unit(unit, environment, authorizer) }

    # Least-privilege per unit, which is the payoff for one Lambda per domain:
    # `uploads` can sign S3 URLs but cannot read a post, and `reactions` never
    # touches the media bucket. This is the part that stays hand-written under
    # either framework — the manifest says which commands a unit serves, not
    # which tables they touch. Foobara's `depends_on` describes command-to-
    # command dependencies, which is a different graph.
    posts.grant_read_write_data(function("posts"))
    posts.grant_read_data(function("comments"))
    posts.grant_read_data(function("reactions"))
    comments.grant_read_write_data(function("comments"))
    comments.grant_read_write_data(function("posts"))    # destroy_with_thread!
    reactions.grant_read_write_data(function("reactions"))
    reactions.grant_read_write_data(function("posts"))   # destroy_with_thread!
    profiles.grant_read_write_data(function("profiles"))
    profiles.grant_read_data(function("posts"))          # author snapshot
    profiles.grant_read_data(function("comments"))
    media.grant_put(function("uploads"))
    media.grant_delete(function("posts"))                # reap on delete

    site = deploy_site

    AWSCDK::CfnOutput.new(self, "ApiUrl", { value: @api.url })
    AWSCDK::CfnOutput.new(self, "SiteUrl", { value: "https://#{site.distribution_domain_name}" })
    AWSCDK::CfnOutput.new(self, "UserPoolId", { value: pool.user_pool_id })
    AWSCDK::CfnOutput.new(self, "UserPoolClientId", { value: client.user_pool_client_id })
  end

  def function(name) = @functions.fetch(name)

  private

  def add_unit(unit, environment, authorizer)
    name = unit.fetch("name")
    fn = build_function(name, environment)
    @functions[name] = fn

    @api.add_routes({
      # One greedy route per unit. That is only possible because the authorizer
      # is a LAMBDA authorizer, which sees rawPath and so decides per command; a
      # JWT authorizer attaches per route, and a unit mixing public and
      # authenticated commands (posts has both) would have to be split into one
      # exact route per command.
      path: unit.fetch("route"),
      methods: [AWSCDK::APIGatewayv2::HttpMethod::ANY],
      integration: AWSCDK::APIGatewayv2Integrations::HttpLambdaIntegration.new(
        "#{logical(name)}Integration", fn
      ),
      authorizer: authorizer
    })
  end

  def build_function(name, environment)
    sizing = SIZING.fetch(name, DEFAULT_SIZING)

    AWSCDK::Lambda::Function.new(@scope, logical(name), {
      runtime: AWSCDK::Lambda::Runtime.RUBY_4_0,
      # x86_64 by default: building arm64 artifacts on an x86_64 host runs under
      # qemu and measured 41x slower (prospect/DESIGN.md §6).
      architecture: AWSCDK::Lambda::Architecture.X86_64,
      handler: "handler.handle",
      code: AWSCDK::Lambda::Code.from_asset(File.join(BUILD, name)),
      # Measured, not guessed: 1024MB roughly halves cold start against 512MB at
      # near-identical GB-seconds.
      memory_size: sizing.fetch(:memory_size),
      timeout: AWSCDK::Duration.seconds(sizing.fetch(:timeout_seconds)),
      environment: environment
    })
  end

  # :lambda, not :jwt. An API Gateway v2 JWT authorizer is all-or-nothing: it
  # rejects a request with no token, and a route WITHOUT one receives no
  # verified claims at all, so there is no "verify if present". Four commands
  # here are public but viewer-aware — Posts::GetPost computes `editable`,
  # Reactions::MyReactions returns the caller's own reactions — and under a JWT
  # authorizer they could never see a signed-in caller.
  #
  # Prospect::Authorizer is reused unchanged. It is the one piece of Prospect
  # this branch still depends on, and reasonably so: optional auth is a property
  # of API Gateway rather than of whatever framework sits behind it.
  def build_authorizer(pool, client)
    fn = AWSCDK::Lambda::Function.new(@scope, "Authorizer", {
      runtime: AWSCDK::Lambda::Runtime.RUBY_4_0,
      architecture: AWSCDK::Lambda::Architecture.X86_64,
      handler: "handler.handle",
      code: AWSCDK::Lambda::Code.from_asset(File.join(BUILD, "authorizer")),
      memory_size: 512,
      timeout: AWSCDK::Duration.seconds(10),
      environment: {
        "PROSPECT_ISSUER"   => pool.user_pool_provider_url,
        "PROSPECT_AUDIENCE" => client.user_pool_client_id,
        # Derived from the manifest's requires_authentication, via units.json.
        # There is no hand-maintained list of public commands anywhere in this
        # repo — declaring `connect(command, requires_authentication: …)` in
        # config.ru is what puts a command in or out of it.
        "PROSPECT_ANONYMOUS" => @plan.fetch("anonymous").join(","),
        "PROSPECT_MOUNT"     => @plan.fetch("mount")
      }
    })

    AWSCDK::APIGatewayv2Authorizers::HttpLambdaAuthorizer.new(
      "ApiAuth", fn,
      { response_types: [AWSCDK::APIGatewayv2Authorizers::HttpLambdaResponseType::SIMPLE],
        # Cached per (identity source, route). An anonymous request carries no
        # Authorization header and so is never cached — every one invokes this.
        results_cache_ttl: AWSCDK::Duration.seconds(300),
        identity_source: ["$request.header.Authorization"] }
    )
  end

  # The SPA on S3 behind CloudFront, with the API on the SAME distribution at
  # /run/*. Two things fall out of that:
  #
  #   * The client is same-origin, so there is no CORS and no preflight.
  #   * The bundle needs no build-time API URL — RemoteCommand.urlBase = "" in
  #     web/src/api/index.ts. It is identical in every environment, which is
  #     also why the Vite dev proxy points /run at the API: dev and production
  #     agree. Same-origin is doing more work here than on the Prospect branch,
  #     because the generated SDK sends credentials: "include" and offers no
  #     hook for a custom header.
  #
  # Assets must be built first, the same way Lambda artifacts must be:
  #
  #   cd web && npm run build
  def deploy_site
    bucket = AWSCDK::S3::Bucket.new(self, "Site", {
      removal_policy: AWSCDK::RemovalPolicy::DESTROY,
      auto_delete_objects: true
    })

    # The API Gateway URL is https://<id>.execute-api.<region>.amazonaws.com/ —
    # CloudFront wants the bare host.
    api_domain = AWSCDK::Fn.select(2, AWSCDK::Fn.split("/", @api.url))

    distribution = AWSCDK::CloudFront::Distribution.new(self, "SiteCdn", {
      default_root_object: "index.html",

      default_behavior: {
        origin: AWSCDK::CloudFrontOrigins::S3BucketOrigin.with_origin_access_control(bucket),
        viewer_protocol_policy: AWSCDK::CloudFront::ViewerProtocolPolicy::REDIRECT_TO_HTTPS
      },

      additional_behaviors: {
        # /run/*, not /rpc/* — the connector's own paths. Never cached, all
        # methods forwarded, and the Host header dropped, because API Gateway
        # rejects a request whose Host is the CloudFront domain.
        # ALL_VIEWER_EXCEPT_HOST_HEADER also forwards Authorization, which the
        # authorizer needs, and Cookie.
        "/run/*" => {
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
        # index.html must never be cached, or a deploy leaves browsers holding a
        # bundle that references hashed assets which no longer exist.
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

  # CloudFormation logical ids must be alphanumeric.
  def logical(name) = name.to_s.split(/[._-]/).map(&:capitalize).join
end
