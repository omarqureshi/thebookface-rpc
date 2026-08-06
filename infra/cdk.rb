# frozen_string_literal: true
require "aws-cdk-lib"
require_relative "stacks/bookface_stack"

# NOTE the absence of `require_relative "../config/boot"`, which the Prospect
# version needed: the stack read the router's IR at synth time, so synthesis
# had to load the whole app. This one reads build/units.json, so it needs
# neither the app nor Foobara — only what the packager already wrote.

# `cdk synth` runs entirely offline: no HostedZone.from_lookup, no context
# lookups, no credentials. That keeps synth deterministic and lets CI diff the
# template without an AWS account.
stage = ENV.fetch("STAGE", "staging")

# outdir is explicit so `ruby cdk.rb` works standalone. The CDK CLI normally
# supplies it via CDK_OUTDIR; without it, synth silently writes nothing.
app = AWSCDK::App.new({ outdir: ENV.fetch("CDK_OUTDIR", "cdk.out") })
BookfaceStack.new(app, "BookfaceRpc-#{stage}", {
  env: AWSCDK::Environment.new(
    account: ENV["CDK_DEFAULT_ACCOUNT"] || "000000000000",
    # us-east-1 because that is where the imported Cognito pool lives. The
    # default matters: forgetting the variable used to mean synthesising for
    # eu-west-2 and, on a deploy, standing up a second stack in the wrong
    # region with an authorizer pointed at an issuer that does not exist.
    region: ENV.fetch("CDK_DEFAULT_REGION", "us-east-1")
  )
}, stage: stage)
app.synth
