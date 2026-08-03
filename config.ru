# frozen_string_literal: true

# Local transport: the whole router in ONE process, every service mounted.
# Deployed, these same procedures sit in seven separate Lambdas — but both go
# through Prospect::Dispatcher, so behaviour cannot drift between them.
#
#   script/dev.sh up
#
# There is no API Gateway locally and therefore no authorizer, so identity comes
# from X-Dev-* headers. This mirrors the Rails app's `sessions#dev_create`
# escape hatch, which was likewise local-only. See DESIGN.md §3.

require_relative "config/boot"
require "fileutils"

# Dev-only object store, so the image flow works end to end without S3 or
# LocalStack. MediaStorage#presigned_upload points the browser here; the bytes
# land on disk and are served back. Deployed, both of these are S3 and none of
# this exists.
MEDIA_DIR = File.expand_path("tmp/media", __dir__)
FileUtils.mkdir_p(MEDIA_DIR)

dev_media = lambda do |env|
  req = Rack::Request.new(env)
  # path_info, not path: under `map` the latter still carries "/media". And
  # unescaped, because a persona sub contains "|", which the browser percent-
  # encodes — so the stored filename would never match.
  key = Rack::Utils.unescape(req.path_info).sub(%r{\A/}, "")

  case req.request_method
  when "POST"
    # Mimics a presigned S3 POST: the key travels in the form, not the path.
    key = req.params["key"].to_s
    return [400, {}, ["missing key"]] if key.empty?

    file = req.params["file"]
    bytes = file.respond_to?(:[]) ? file[:tempfile].read : file.to_s
    path = File.join(MEDIA_DIR, key.tr("/", "_"))
    File.binwrite(path, bytes)
    [204, { "access-control-allow-origin" => "*" }, []]
  when "GET"
    path = File.join(MEDIA_DIR, key.tr("/", "_"))
    return [404, {}, ["not found"]] unless File.exist?(path)

    [200, { "content-type" => "image/jpeg" }, [File.binread(path)]]
  when "OPTIONS"
    [204, { "access-control-allow-origin" => "*",
            "access-control-allow-headers" => "*",
            "access-control-allow-methods" => "POST, GET, OPTIONS" }, []]
  else
    [405, {}, []]
  end
end

rpc = Prospect::RackApp.new(
  Bookface::AppRouter,
  # Warn by default; PROSPECT_SCHEMA_POLICY=reject to fail stale callers hard.
  # Rejecting by default would break every browser holding a cached bundle the
  # moment the contract changed.
  on_schema_mismatch: ENV.fetch("PROSPECT_SCHEMA_POLICY", "warn").to_sym,
  context_builder: lambda { |env|
    headers = env.each_with_object({}) do |(k, v), acc|
      acc[k.delete_prefix("HTTP_").split("_").map(&:capitalize).join("-")] = v if k.start_with?("HTTP_X_DEV")
    end
    Bookface::Context.from_dev_headers(headers)
  }
)

run(Rack::Builder.app do
  map("/media") { run dev_media }
  run rpc
end)
