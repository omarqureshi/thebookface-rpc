# frozen_string_literal: true

# Cold-start scope. Everything here is built once per process (or per Lambda
# execution environment) and reused across requests. Nothing request-specific
# may be memoized here — see Prospect DESIGN.md §6 on the two lifecycles.

require "securerandom"
require "dynamoid"
require "cancancan"
require "prospect"

TABLE_DEFAULTS = {
  "POSTS_TABLE"     => "bookface_posts",
  "COMMENTS_TABLE"  => "bookface_comments",
  "REACTIONS_TABLE" => "bookface_reactions",
  "PROFILES_TABLE"  => "bookface_profiles"
}.freeze
TABLE_DEFAULTS.each { |k, v| ENV[k] ||= v }

Dynamoid.configure do |config|
  config.region     = ENV.fetch("AWS_REGION", "us-east-1")
  config.namespace  = nil                      # table names are explicit
  config.timestamps = true                     # created_at / updated_at

  # Local DynamoDB. In Lambda these are absent and the SDK uses the real
  # endpoint with the function's execution role.
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

require_relative "../app/app_router"
