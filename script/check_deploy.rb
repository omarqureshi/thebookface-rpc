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

require "foobara/aws/check"

# The connector, not build/plan.json: the check should assert what the code says
# is public, not what the last packaging run happened to record. If those two
# disagree, that is exactly the drift worth catching — and this catches it as a
# failed check against the deployment.
require_relative "../config/connector"

url = ARGV[0] || abort("usage: check_deploy.rb <url>")
plan = Foobara::AWS.plan_from_connector(BOOKFACE_CONNECTOR, mount: "/run")

result = Foobara::AWS::Check.new(url: url, plan: plan).run
puts result.report
exit(result.ok? ? 0 : 1)
