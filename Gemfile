source "https://rubygems.org"

# Foobara replaces Prospect on this branch: commands and domains instead of a
# router and procedures, with the manifest as the machine-readable description
# that clients and (we hope) packaging are both driven from.
gem "foobara"
gem "foobara-rack-connector"
# Foobara's own TypeScript SDK generator — the counterpart to Prospect's
# emitter, and the honest comparison for the client half.
gem "foobara-typescript-remote-command-generator", group: :development

gem "dynamoid", "~> 3.10"
gem "aws-sdk-dynamodb", "~> 1"
gem "cancancan", "~> 3.6"
gem "rack", "~> 3.0"
gem "rackup"
gem "puma"

group :test do
  gem "cucumber", "~> 9.2"
  gem "capybara", "~> 3.40"
  gem "cuprite", "~> 0.15"
  gem "rspec-expectations", "~> 3.13"
end
