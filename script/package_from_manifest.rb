# frozen_string_literal: true
#
# Builds one deployable artifact per domain, plus the authorizer, from the
# manifest a running connector serves.
#
#   script/dev.sh serve    # then
#   bundle exec ruby script/package_from_manifest.rb
#
# This was 250 lines: unit derivation, handler generation, Docker bundling,
# bundle sharing, the authorizer unit. All of it is foobara-aws now, and none of
# it was ever bookface-specific — which is the whole argument of FOOBARA.md,
# made concrete.
#
# What remains here is what genuinely IS this app's: where its sources live, and
# the DynamoDB schema (a different concern, and a different gem).

require "json"
require "net/http"

require "foobara/aws/packager"

ROOT = File.expand_path("..", __dir__)

# Fetched live from the running connector, not from a snapshot on disk: a stale
# manifest fails as a packaging bug rather than as an old file, which cost real
# time when this script read /tmp.
MANIFEST_URL = ENV.fetch("BOOKFACE_MANIFEST", "http://localhost:9292/manifest")
manifest = JSON.parse(Net::HTTP.get(URI(MANIFEST_URL)))

plan = Foobara::AWS.plan(manifest, mount: "/run")

built = Foobara::AWS::Packager.new(
  plan: plan,
  root: ROOT,
  # The authorizer gets none of these — it verifies a token and answers yes or
  # no, so the domain model would be dead weight on every authenticated request.
  sources: %w[app config],
  # foobara-aws is a path gem until it is published, and the build container
  # sees only the app root — so its location has to be mounted too. Bundler
  # bakes an absolute load path for a path gem; the packager copies it in and
  # rewrites that, or the artifact would boot here and LoadError in Lambda.
  mounts: [File.expand_path("../foobara-aws", ROOT)],
  authorizer: {}
).build

built.each { |unit| puts "built #{unit[:name]}: #{unit[:commands]} commands" }
plan.units.each { |u| puts "  #{u.name.ljust(10)} #{u.route.ljust(26)} public #{u.public_commands.length}" }
puts "wrote #{File.join(ROOT, "build", "plan.json")}"

# The other half the stack reads: the DynamoDB schema, from the Dynamoid models.
# A subprocess because this script does not boot the app — it reads the manifest
# over HTTP — and booting it here would drag Dynamoid into packaging's load path.
abort "schema dump failed" unless system(RbConfig.ruby, File.expand_path("dump_schema.rb", __dir__))
