# frozen_string_literal: true

# Cold-start scope. Built once per process (or per Lambda execution
# environment) and reused across requests.

require "securerandom"
require "time"
require "dynamoid"
require "cancancan"
require "foobara/all"
require "foobara/aws/handler"
require "foobara/aws/lambda"
require "foobara/aws/sqs_connector"

TABLE_DEFAULTS = {
  "POSTS_TABLE"     => "bookface_posts",
  "COMMENTS_TABLE"  => "bookface_comments",
  "REACTIONS_TABLE" => "bookface_reactions",
  "PROFILES_TABLE"  => "bookface_profiles"
}.freeze
TABLE_DEFAULTS.each { |k, v| ENV[k] ||= v }

Dynamoid.configure do |config|
  config.region     = ENV.fetch("AWS_REGION", "us-east-1")
  config.namespace  = nil
  config.timestamps = true

  if (endpoint = ENV["DYNAMODB_ENDPOINT"])
    config.endpoint = endpoint
    config.access_key = "local"
    config.secret_key = "local"
  end
end

require_relative "../app/models/media_storage"
require_relative "../app/models/profile_reconciliation"
require_relative "../app/models/post"
require_relative "../app/models/comment"
require_relative "../app/models/reaction"
require_relative "../app/models/profile"
require_relative "../app/models/ability"

# Who a set of verified claims IS, for this app. The generated Lambda handler
# and config.ru both call this, so identity is built in exactly one place.
Viewer = Struct.new(:sub, :name)
Foobara::AWS.caller_builder = lambda do |claims|
  sub = claims["sub"]
  sub && Viewer.new(sub, claims["name"] || claims["email"] || sub)
end

require_relative "../app/domains/shared"
require_relative "../app/domains/posts"
require_relative "../app/domains/comments"
require_relative "../app/domains/reactions"
require_relative "../app/domains/profiles"
require_relative "../app/domains/uploads"

# The queue connector lives HERE, not in config/connector.rb, because connecting
# a command generates the <Command>Async that other commands call — so it has to
# exist wherever the domain is loaded, not only where HTTP is served.
#
# It did not, and a packaged unit found out at runtime: the generated handler
# requires this file but not config/connector.rb, so UpdateProfile referenced a
# constant that had never been defined. Locally config.ru loaded both, which is
# exactly the kind of divergence that only shows up deployed.
#
# No queue URL means enqueuing runs the command inline, which is what local work
# and the cucumber suite exercise.
BOOKFACE_QUEUE = Foobara::AWS::SQSConnector.new(queue_url: ENV.fetch("RECONCILE_QUEUE_URL", nil))
BOOKFACE_QUEUE.connect(Profiles::ReconcileAuthorSnapshot)
# Nothing in this app enqueues it — S3 does, through EventBridge. Connecting it
# is still what makes it reachable by name from a message, which is all the
# event handler needs.
BOOKFACE_QUEUE.connect(Uploads::VerifyUpload)

# The name foobara-aws's generated event handler looks for.
FOOBARA_EVENT_CONNECTOR = BOOKFACE_QUEUE
