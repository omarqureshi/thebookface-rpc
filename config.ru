# frozen_string_literal: true

# Local transport: the whole router in ONE process, every service mounted.
# Deployed, these same procedures sit in five separate Lambdas — but both go
# through Prospect::Dispatcher, so behaviour cannot drift between them.
#
#   bundle exec rackup -p 9292
#
# There is no API Gateway locally and therefore no JWT authorizer, so identity
# comes from X-Dev-* headers. This mirrors the Rails app's `sessions#dev_create`
# escape hatch, which was likewise local-only. See bookface-rpc DESIGN.md §3.

require_relative "config/boot"

run Prospect::RackApp.new(
  Bookface::AppRouter,
  context_builder: lambda { |env|
    headers = env.each_with_object({}) do |(k, v), acc|
      acc[k.delete_prefix("HTTP_").split("_").map(&:capitalize).join("-")] = v if k.start_with?("HTTP_X_DEV")
    end
    Bookface::Context.from_dev_headers(headers)
  }
)
