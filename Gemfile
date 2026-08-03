source "https://rubygems.org"

# Local dev runs every service in one process, so it needs the union of the
# per-unit gemfiles in units/. Deployed, each Lambda installs only its own slice
# via BUNDLE_GEMFILE=units/<service>.gemfile (prospect/DESIGN.md §6).
gem "prospect", path: "../../prospect"
gem "sorbet-runtime"
gem "dynamoid", "~> 3.10"
gem "aws-sdk-dynamodb", "~> 1"
gem "cancancan", "~> 3.6"
gem "rack", "~> 3.0"
gem "rackup"
gem "puma"

group :test do
  # Plain cucumber, NOT cucumber-rails: there is no Rails, and no server-rendered
  # HTML to drive with rack_test. Every scenario runs against the real SPA in a
  # real browser, which is the only honest way to test a client that does its
  # rendering in JavaScript.
  gem "cucumber", "~> 9.2"
  gem "capybara", "~> 3.40"
  gem "cuprite", "~> 0.15"
  gem "rspec-expectations", "~> 3.13"
end
