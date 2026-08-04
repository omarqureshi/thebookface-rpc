# frozen_string_literal: true
#
# Checks a DEPLOYED api against the plan it was deployed from.
#
#   bundle exec ruby script/check_deploy.rb https://staging.thebookface.net
#
# This is the thing the cucumber suite structurally cannot do. That suite runs
# against one process with no API Gateway, no CloudFront and no IAM, so every
# defect that lives at the edge — an authorizer that refuses anonymous callers, a
# CDN rewriting API errors into HTML — passes it and fails in production. See
# FOOBARA.md.

require "json"
require "foobara/aws/check"

url = ARGV[0] || abort("usage: check_deploy.rb <url>")
plan = Foobara::AWS::Plan.load(JSON.parse(File.read(File.expand_path("../build/plan.json", __dir__))))

result = Foobara::AWS::Check.new(url: url, plan: plan).run
puts result.report
exit(result.ok? ? 0 : 1)
