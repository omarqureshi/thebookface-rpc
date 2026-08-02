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
