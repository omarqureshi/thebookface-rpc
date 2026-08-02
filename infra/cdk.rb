# frozen_string_literal: true
require "aws-cdk-lib"
require_relative "../config/boot"
require_relative "stacks/bookface_stack"

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
    region: ENV.fetch("CDK_DEFAULT_REGION", "eu-west-2")
  )
}, stage: stage)
app.synth
