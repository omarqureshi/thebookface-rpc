# frozen_string_literal: true

require "json"
require "aws-cdk-lib"
require "constructs"
# Builds the tables from build/tables.json. The gem's other half reads the
# Dynamoid models (script/dump_schema.rb); this half needs neither Dynamoid nor
# the app, which is why synthesis still depends only on what was built.
require "dynamoid/cdk/schema"
# The API topology: one Lambda per domain, its route, and the public list —
# all read from the connector — see the note below on why synthesis loads the app.
require "foobara/aws/cdk/service"
# Loads the app. See the note above on why synthesis is allowed to be slow.
require_relative "../../config/connector"

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

  # NOTE what is no longer here: a SIZING constant. Deployment metadata was
  # out-of-band because the manifest had nowhere for it; commands now declare
  # `aws_lambda` themselves (see Posts::DestroyPost) and it travels through the
  # manifest into the plan.

  # Custom domain per stage, committed rather than passed in. It was an env var
  # (BOOKFACE_DOMAIN), and a deploy that forgot it silently produced a stack with
  # no certificate, no records and no alias — which then also means a LATER
  # deploy would delete them. Config that only exists in a shell history is not
  # config. BOOKFACE_DOMAIN still overrides, for a throwaway deploy.
  #
  # Only the SITE gets a domain, not the API: the API is already behind the same
  # distribution at /run/*, which is what makes the client same-origin and lets
  # the bundle ship with no environment-specific URL in it. A separate API
  # Gateway custom domain would undo that.
  DOMAINS = { "staging" => "staging.thebookface.net" }.freeze
  # Looked up by attributes rather than HostedZone.from_lookup: a lookup needs
  # AWS credentials at synth time, which makes `cdk synth` non-deterministic and
  # breaks it offline and in CI.
  ZONE_ID   = ENV.fetch("BOOKFACE_ZONE_ID", "Z0430301186RRIJICRS18")
  ZONE_NAME = ENV.fetch("BOOKFACE_ZONE_NAME", "thebookface.net")

  # The Rails app's pool, imported rather than recreated — it already carries the
  # Google IdP and the hosted UI, and Google's own OAuth client is registered
  # against that hosted-UI domain, not against this app's hostname.
  USER_POOL_ID = ENV.fetch("BOOKFACE_USER_POOL_ID", "us-east-1_lz3Tif7pC")
  HOSTED_UI    = ENV.fetch(
    "BOOKFACE_COGNITO_DOMAIN",
    "https://the-bookface-staging-339713138084.auth.us-east-1.amazoncognito.com"
  )

  # `stage` is a separate keyword rather than a props key: AWSCDK::StackProps is
  # strict and rejects unknown keys, so app config cannot ride along inside it.
  def initialize(scope, id, props = nil, stage: "staging")
    super(scope, id, props)

    @domain = ENV["BOOKFACE_DOMAIN"] || DOMAINS[stage]
    @plan = Foobara::AWS.plan_from_connector(BOOKFACE_CONNECTOR, mount: "/run")
    @tables_plan = JSON.parse(File.read(File.join(BUILD, "tables.json")))

    # Tables come from build/tables.json, which script/dump_schema.rb reads off
    # the Dynamoid models. They used to be hand-written here with keys only and
    # no indexes, while Post declares two GSIs and Comment one — so the deployed
    # feed 500'd on every request, and CDK made it worse by omitting index ARNs
    # from the grant (it adds `/index/*` only when the table declares an index).
    # Restating a schema in infra is how the two drift; this is the same reason
    # the topology comes from the manifest.
    # Keyed by `key`, not by the CloudFormation logical `id` — they differ when
    # a table has had to be replaced (see script/dump_schema.rb), and the grants
    # below should not have to care.
    tables = {}
    @tables_plan.each { |spec| tables[spec.fetch("key")] = table(spec) }
    posts, comments, reactions, profiles =
      tables.values_at("Posts", "Comments", "Reactions", "Profiles")

    media = AWSCDK::S3::Bucket.new(self, "Media", {
      removal_policy: AWSCDK::RemovalPolicy::DESTROY,
      # Both, or neither. DESTROY alone is a trap: the bucket is empty today so
      # a teardown works, but the first uploaded image would make `cdk destroy`
      # fail on a non-empty bucket — discovered at exactly the wrong moment.
      # Uploads here are as disposable as the tables; production would use
      # RETAIN for both.
      auto_delete_objects: true,
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
    #
    # The pool is IMPORTED, not created. It belongs to TheBookface-staging,
    # which configured the Google IdP and the hosted UI on it — recreating
    # either here would mean a second Google OAuth client and a second hosted-UI
    # domain for the same users. Importing also means this stack never mutates
    # the pool: it only adds a client of its own.
    pool = AWSCDK::Cognito::UserPool.from_user_pool_id(self, "Users", USER_POOL_ID)

    # Our own app client rather than the Rails one. That client is a
    # confidential client whose callback is a Rails route
    # (/auth/cognito/callback) whichhandles the exchange server-side; a static
    # SPA has nowhere to keep a secret, so it needs a PUBLIC client using
    # Authorization Code + PKCE, with the callback pointing at the SPA itself.
    #
    # Adding a client does not touch the Rails client, so both apps can use the
    # same pool and the same Google identities at once.
    client = pool.add_client("WebSpa", {
      generate_secret: false,
      # `.GOOGLE` not `::GOOGLE`: in these bindings a static PROPERTY is a method
      # call, while a true enum member is a constant. Same for OAuthScope below.
      supported_identity_providers: [
        AWSCDK::Cognito::UserPoolClientIdentityProvider.GOOGLE
      ],
      o_auth: {
        flows: { authorization_code_grant: true },
        scopes: [
          AWSCDK::Cognito::OAuthScope.OPENID,
          AWSCDK::Cognito::OAuthScope.EMAIL,
          AWSCDK::Cognito::OAuthScope.PROFILE
        ],
        callback_urls: oauth_urls,
        logout_urls: oauth_urls
      }
    })

    # Env var names come from the same file, so adding a model is a change in one
    # place rather than three.
    environment = { "BOOKFACE_ENV" => stage, "MEDIA_BUCKET" => media.bucket_name }
    @tables_plan.each { |spec| environment[spec.fetch("env")] = tables.fetch(spec.fetch("key")).table_name }

    # One construct, driven by the plan. It hangs the API and its functions off a
    # child scope, which also avoids the logical-id collision between the
    # `comments` function and the `Comments` table.
    api = Foobara::AWS::CDK::Service.new(
      self, "Api",
      plan: @plan,
      code_root: BUILD,
      environment: environment,
      # X-Ray, for cold starts: a cold invocation gets an Initialization
      # subsegment, so boot cost is visible rather than inferred.
      tracing: :active,
      authorizer: {
        id: "Authorizer",
        code: File.join(BUILD, "authorizer"),
        environment: {
          # Built from the pool id rather than read off the construct: an
          # IMPORTED pool exposes user_pool_id but not user_pool_provider_url.
          "FOOBARA_ISSUER" => "https://cognito-idp.#{region}.amazonaws.com/#{USER_POOL_ID}",
          "FOOBARA_AUDIENCE" => client.user_pool_client_id
        }
      }
    )

    @api = api.api
    @functions = @plan.units.to_h { |unit| [unit.name, api.function(unit.name)] }

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

    # Dynamoid checks table existence via dynamodb:ListTables on its first
    # write. That is an account-level action with no resource-level scoping, so
    # grant_read_write_data above cannot include it and every write 500'd with
    # AccessDeniedException. Granted explicitly on "*" because AWS permits no
    # narrower resource — the Rails stack carries the identical statement for
    # the identical reason.
    @functions.each_value do |fn|
      fn.add_to_role_policy(
        AWSCDK::IAM::PolicyStatement.new({ actions: ["dynamodb:ListTables"], resources: ["*"] })
      )
    end

    site = deploy_site(client, media)

    # Set after the fact rather than in `environment`: the value depends on the
    # distribution, which depends on the functions. add_environment breaks that
    # cycle — the same shape as the Rails stack handing its function the Cognito
    # client id after the client exists.
    media_url = @domain ? "https://#{@domain}/media" : "https://#{site.distribution_domain_name}/media"
    @functions.each_value { |fn| fn.add_environment("BOOKFACE_MEDIA_URL", media_url) }

    AWSCDK::CfnOutput.new(self, "ApiUrl", { value: @api.url })
    AWSCDK::CfnOutput.new(self, "SiteUrl",
                          { value: @domain ? "https://#{@domain}" : "https://#{site.distribution_domain_name}" })
    AWSCDK::CfnOutput.new(self, "UserPoolId", { value: pool.user_pool_id })
    AWSCDK::CfnOutput.new(self, "UserPoolClientId", { value: client.user_pool_client_id })
  end

  def function(name) = @functions.fetch(name)

  private

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
  def deploy_site(client, media)
    bucket = AWSCDK::S3::Bucket.new(self, "Site", {
      removal_policy: AWSCDK::RemovalPolicy::DESTROY,
      auto_delete_objects: true
    })

    # The API Gateway URL is https://<id>.execute-api.<region>.amazonaws.com/ —
    # CloudFront wants the bare host.
    api_domain = AWSCDK::Fn.select(2, AWSCDK::Fn.split("/", @api.url))

    # Rewrites client routes to index.html. /posts/:id is a route with no object
    # behind it, so S3 would answer 403 (404 only when ListBucket is granted,
    # which OAC does not) and a cold load or refresh of any route below / would
    # fail. Anything with a dot is treated as a real file and passed through.
    spa_router = AWSCDK::CloudFront::Function.new(self, "SpaRouter", {
      # `.JS_2_0`, a static property, not an enum constant — the same
      # distinction as Architecture.X86_64 and OAuthScope.OPENID above.
      runtime: AWSCDK::CloudFront::FunctionRuntime.JS_2_0,
      code: AWSCDK::CloudFront::FunctionCode.from_inline(<<~JS)
        function handler(event) {
          var uri = event.request.uri
          if (uri.indexOf('.') === -1) { event.request.uri = '/index.html' }
          return event.request
        }
      JS
    })

    media_router = AWSCDK::CloudFront::Function.new(self, "MediaRouter", {
      runtime: AWSCDK::CloudFront::FunctionRuntime.JS_2_0,
      code: AWSCDK::CloudFront::FunctionCode.from_inline(<<~JS)
        function handler(event) {
          event.request.uri = event.request.uri.replace(/^\\/media/, '')
          return event.request
        }
      JS
    })

    zone = domain_zone
    # us-east-1 is not a choice here: CloudFront only accepts certificates from
    # that region. This stack happens to deploy there anyway; from any other
    # region the cert would need a us-east-1 sub-stack.
    certificate =
      if zone
        AWSCDK::CertificateManager::Certificate.new(self, "SiteCert", {
          domain_name: @domain,
          validation: AWSCDK::CertificateManager::CertificateValidation.from_dns(zone)
        })
      end

    props = {
      default_root_object: "index.html",

      default_behavior: {
        origin: AWSCDK::CloudFrontOrigins::S3BucketOrigin.with_origin_access_control(bucket),
        viewer_protocol_policy: AWSCDK::CloudFront::ViewerProtocolPolicy::REDIRECT_TO_HTTPS,
        # The history fallback, attached to THIS behaviour only — see below.
        function_associations: [{
          function: spa_router,
          event_type: AWSCDK::CloudFront::FunctionEventType::VIEWER_REQUEST
        }]
      },

      additional_behaviors: {
        # Images come off the same distribution, so the media bucket needs no
        # public access at all — CloudFront reads it through an Origin Access
        # Control, exactly as the site bucket is read. Uploads still go straight
        # to S3 with a presigned POST; only reads come through here.
        "/media/*" => {
          origin: AWSCDK::CloudFrontOrigins::S3BucketOrigin.with_origin_access_control(media),
          viewer_protocol_policy: AWSCDK::CloudFront::ViewerProtocolPolicy::REDIRECT_TO_HTTPS,
          # Strips the /media prefix: the object key is "u/<sub>/<uuid>.jpeg",
          # while the request path is "/media/u/<sub>/<uuid>.jpeg". Without this
          # CloudFront would ask S3 for an object called "media/u/...".
          function_associations: [{
            function: media_router,
            event_type: AWSCDK::CloudFront::FunctionEventType::VIEWER_REQUEST
          }]
        },
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

      # NOTE the absence of error_responses. The history fallback used to be
      # `403 -> /index.html 200` and `404 -> /index.html 200`, which is the usual
      # recipe and is WRONG here: custom error responses apply to the whole
      # DISTRIBUTION, including /run/*. So the API's own 403s and 404s came back
      # as a 200 serving the HTML page. Measured: POST /run/Posts/CreatePost with
      # an invalid token returned 200 and an index.html body through CloudFront,
      # where API Gateway had answered 403.
      #
      # That would have hidden Prospect's `forbidden` (403) and `not_found` (404)
      # entirely; Foobara answers 422, so only API Gateway's own refusals were
      # masked here — still enough to make a refused request look like a success.
      #
      # The fallback now lives in a viewer-request function on the default
      # behaviour, which /run/* does not share.
    }

    if certificate
      props[:domain_names] = [@domain]
      props[:certificate]  = certificate
    end

    distribution = AWSCDK::CloudFront::Distribution.new(self, "SiteCdn", props)

    if zone
      # A and AAAA both: CloudFront answers on IPv6, and a browser on an
      # IPv6-only network that finds only an A record never reaches it.
      target = AWSCDK::Route53::RecordTarget.from_alias(
        AWSCDK::Route53Targets::CloudFrontTarget.new(distribution)
      )
      AWSCDK::Route53::ARecord.new(self, "SiteAlias",
                                   { zone: zone, record_name: @domain, target: target })
      AWSCDK::Route53::AaaaRecord.new(self, "SiteAliasV6",
                                      { zone: zone, record_name: @domain, target: target })
    end

    dist = File.expand_path("../../web/dist", __dir__)
    if Dir.exist?(dist)
      AWSCDK::S3Deployment::BucketDeployment.new(self, "SiteAssets", {
        sources: [
          AWSCDK::S3Deployment::Source.asset(dist),
          # Deploy-time config rather than build-time. The client id is only
          # known once this stack has synthesised, and baking it into the bundle
          # would mean a different bundle per environment — the same reason the
          # API is same-origin at /run/* instead of an absolute URL.
          #
          # None of this is secret: a public OIDC client is identified, not
          # authenticated. What stops someone else's app using it is Cognito's
          # callback-URL allowlist.
          AWSCDK::S3Deployment::Source.json_data("config.json", {
            "userPoolId" => USER_POOL_ID,
            "clientId"   => client.user_pool_client_id,
            "hostedUi"   => HOSTED_UI
          })
        ],
        destination_bucket: bucket,
        distribution: distribution,
        # index.html must never be cached, or a deploy leaves browsers holding a
        # bundle that references hashed assets which no longer exist. config.json
        # likewise, or a client-id change would not reach a returning browser.
        distribution_paths: ["/index.html", "/", "/config.json"]
      })
    else
      AWSCDK::Annotations.of(self).add_warning(
        "web/dist not found — the site bucket will be empty. Run `cd web && npm run build`."
      )
    end

    distribution
  end

  # Where Cognito is allowed to send the browser back to. The deployed origin,
  # plus the Vite dev server so the real flow can be exercised locally against
  # the same pool — neither is a secret, and an unregistered redirect_uri is
  # refused by Cognito, which is what makes the list the security boundary.
  def oauth_urls
    ["https://#{@domain}/", "http://localhost:5173/"]
  end

  def domain_zone
    return nil unless @domain

    AWSCDK::Route53::HostedZone.from_hosted_zone_attributes(
      self, "Zone", { hosted_zone_id: ZONE_ID, zone_name: ZONE_NAME }
    )
  end

  # Keys and indexes come from the model via the dumped schema; everything the
  # model does not describe — removal policy, billing, PITR — stays here, which
  # is the split the gem draws.
  def table(spec)
    Dynamoid::CDK::Schema.table_from(
      self, spec.fetch("id"), spec.fetch("schema"),
      removal_policy: AWSCDK::RemovalPolicy::DESTROY
    )
  end

  # CloudFormation logical ids must be alphanumeric.
  def logical(name) = name.to_s.split(/[._-]/).map(&:capitalize).join
end
