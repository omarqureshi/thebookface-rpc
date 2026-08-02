# frozen_string_literal: true
# Builds a deployable artifact per service. Docker required.
#   bundle exec ruby script/package.rb [--dry-run]
require_relative "../config/boot"

ROOT = File.expand_path("..", __dir__)

plan = Prospect::Package.plan(
  router: Bookface::AppRouter,
  router_const: "Bookface::AppRouter",
  context_builder: "Bookface::Context.method(:from_event)",
  root: ROOT,
  out: File.join(ROOT, "build"),
  sources: %w[app config],
  granularity: :per_router,
  # prospect is a path gem during development, and lives outside this app.
  # Once it's published this mount disappears.
  mounts: [File.expand_path("../../prospect", ROOT)]
)

if ARGV.include?("--dry-run")
  puts JSON.pretty_generate(plan.to_h)
  puts "\n#{plan.units.length} units, #{plan.builds.length} distinct gem sets"
  exit
end

units = Prospect::Package.build(plan)
puts "built #{units.length} units into #{plan.out}"
