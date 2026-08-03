# frozen_string_literal: true

# DynamoDB test setup, ported almost unchanged from the Rails suite — the models
# came across intact, so this did too. Tables are created once, then every item
# is purged before each scenario: cheaper than dropping and recreating.
MODELS = [Post, Comment, Reaction, Profile].freeze

MODELS.each do |model|
  model.create_table(sync: true)
rescue Dynamoid::Errors::Error, Aws::DynamoDB::Errors::ResourceInUseException
  # already there
end

Before do
  MODELS.each { |model| model.each(&:delete) }
  # The dev object store is filesystem-backed, so images survive a purge unless
  # we clear them too — which would make "the stored image is gone" pass for the
  # wrong reason.
  FileUtils.rm_rf(Dir[File.join(MediaStorage.local_dir, "*")])
end

# Identity is persisted in localStorage so it survives a page load, which means
# it also survives between scenarios unless we clear it.
Before do
  visit "/"
  page.execute_script("localStorage.clear()")
rescue StandardError
  # First scenario, before the browser has a document — nothing to clear.
end
