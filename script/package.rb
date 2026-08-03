# frozen_string_literal: true
# Builds a deployable artifact per service. Docker required.
#   bundle exec ruby script/package.rb [--dry-run]
require "bundler"
require_relative "../config/boot"

ROOT = File.expand_path("..", __dir__)

# GitHub Packages requires a credential even for public gems. Read from the
# environment, falling back to whatever `bundle config` already holds locally,
# so the usual setup needs no extra step and CI can pass it explicitly.
def github_packages_credential
  from_env = ENV["BUNDLE_RUBYGEMS__PKG__GITHUB__COM"]
  return from_env if from_env && !from_env.empty?

  # Bundler.settings, NOT `bundle config get` — the CLI redacts credentials in
  # its output, so parsing it yields the literal string "user:[REDACTED]" and
  # the build fails complaining the brackets need CGI escaping.
  configured = Bundler.settings["rubygems.pkg.github.com"].to_s
  return configured unless configured.empty?

  abort <<~MSG
    No credential for rubygems.pkg.github.com, which is needed to fetch the
    prospect gem inside the build container. Set one with:

      bundle config set --global rubygems.pkg.github.com USER:TOKEN

    or export BUNDLE_RUBYGEMS__PKG__GITHUB__COM=USER:TOKEN
  MSG
end

plan = Prospect::Package.plan(
  router: Bookface::AppRouter,
  router_const: "Bookface::AppRouter",
  context_builder: "Bookface::Context.method(:from_event)",
  root: ROOT,
  out: File.join(ROOT, "build"),
  sources: %w[app config],
  granularity: :per_router,
  authorizer: true,
  # prospect comes from GitHub Packages now, so nothing outside this directory
  # needs mounting — but the container has to authenticate to fetch it, and it
  # inherits nothing from the host.
  env: { "BUNDLE_RUBYGEMS__PKG__GITHUB__COM" => github_packages_credential }
)

if ARGV.include?("--dry-run")
  puts JSON.pretty_generate(plan.to_h)
  puts "\n#{plan.units.length} units, #{plan.builds.length} distinct gem sets"
  exit
end

units = Prospect::Package.build(plan)
puts "built #{units.length} units into #{plan.out}"
