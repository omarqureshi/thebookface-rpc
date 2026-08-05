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

require "foobara/aws/packager"

ROOT = File.expand_path("..", __dir__)

# The connector itself, not its manifest over HTTP. Same information, read
# straight off the objects: no server to start first, and no snapshot to go
# stale — which is a failure mode that actually happened here, silently building
# a five-command domain with three commands in it.
#
# A CONNECTOR rather than the domains, because `requires_authentication` is
# decided at connect time. config.ru builds the real one, so packaging and
# serving cannot disagree about which commands are public.
require_relative "../config/connector"

# Both connectors: the HTTP one becomes routed units, the SQS one a unit with an
# event source and no route.
plan = Foobara::AWS.plan_from_connectors(
  { http: BOOKFACE_CONNECTOR, sqs: BOOKFACE_QUEUE }, mount: "/run"
)

built = Foobara::AWS::Packager.new(
  plan: plan,
  root: ROOT,
  # The authorizer gets none of these — it verifies a token and answers yes or
  # no, so the domain model would be dead weight on every authenticated request.
  sources: %w[app config],
  authorizer: {},
  # Records which revision each unit last CHANGED at — not the revision being
  # built. An untouched unit keeps its old value, so its Lambda's configuration
  # does not churn on every commit and `cdk diff` still means something.
  # Committed, because it is only useful as a history.
  provenance: File.join(ROOT, "provenance.json")
).build

built.each { |unit| puts "built #{unit[:name]}: #{unit[:commands]} commands" }
plan.units.each { |u| puts "  #{u.name.ljust(10)} #{u.route.ljust(26)} public #{u.public_commands.length}" }
puts "wrote #{File.join(ROOT, "build", "plan.json")}"

# The other half the stack reads: the DynamoDB schema, from the Dynamoid models.
# A subprocess because this script does not boot the app — it reads the manifest
# over HTTP — and booting it here would drag Dynamoid into packaging's load path.
abort "schema dump failed" unless system(RbConfig.ruby, File.expand_path("dump_schema.rb", __dir__))
