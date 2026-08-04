# frozen_string_literal: true
#
# Writes build/tables.json — the DynamoDB schema, read straight off the Dynamoid
# models so infra never restates what the app already declares.
#
#   bundle exec ruby script/dump_schema.rb
#
# script/package_from_manifest.rb runs this, so packaging emits both halves of
# what the stack needs: units.json (topology, from the Foobara manifest) and
# tables.json (storage, from the models). The stack reads files and stays free
# of Foobara, Dynamoid and the app.
#
# This exists because the stack previously hand-wrote four tables with keys only
# and NO indexes, while Post declares two GSIs and Comment one. The deployed feed
# therefore 500'd on every request: Query on posts_by_recency was refused, and
# CDK compounded it by omitting index ARNs from the IAM grant — it adds
# `/index/*` only when the table declares an index, so a missing GSI silently
# costs the permission too.
#
# The reading is dynamoid-cdk-schema's job, the same gem the Rails app uses. It
# assumed the CDK app could load the models; it now also dumps to JSON, which is
# what lets synthesis here stay app-free (Schema.dump / Schema.table_from, 0.2.0).

require "json"
require "dynamoid/cdk/schema"

require_relative "../config/boot"

# Two names per table, and the distinction matters.
#
#   key — how the stack refers to a table when granting access. Stable forever.
#   id  — the CloudFormation logical id. Changing it REPLACES the table.
#
# They were the same string until Posts needed both its GSIs at once:
# CloudFormation allows only one GSI creation or deletion per table per update,
# so adding two to a live table is impossible in a single deploy ("Cannot
# perform more than one GSI creation or deletion in a single update"). Deploying
# twice would work; replacing the table does it in one, which is the right trade
# only because these tables are empty. On a table with data, deploy twice.
#
# Keeping `key` separate means a future replacement is a one-line change here
# and the stack's grants are untouched.
MODELS = {
  "Posts"     => { model: Post,     id: "PostsV2",   env: "POSTS_TABLE" },
  "Comments"  => { model: Comment,  id: "Comments",  env: "COMMENTS_TABLE" },
  "Reactions" => { model: Reaction, id: "Reactions", env: "REACTIONS_TABLE" },
  "Profiles"  => { model: Profile,  id: "Profiles",  env: "PROFILES_TABLE" }
}.freeze

tables = MODELS.map do |key, spec|
  { "key" => key, "id" => spec.fetch(:id), "env" => spec.fetch(:env),
    "schema" => Dynamoid::CDK::Schema.dump(spec.fetch(:model)) }
end

out = File.expand_path("../build/tables.json", __dir__)
Dir.mkdir(File.dirname(out)) unless Dir.exist?(File.dirname(out))
File.write(out, JSON.pretty_generate(tables))

summary = tables.map { |t| "#{t['id']}(#{t['schema']['global_secondary_indexes'].length} gsi)" }.join(", ")
puts "wrote #{out}: #{summary}"
