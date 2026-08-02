# frozen_string_literal: true
# Creates the DynamoDB tables and GSIs against whatever endpoint is configured.
#   bundle exec ruby script/create_tables.rb
require_relative "../config/boot"

[Post, Comment, Reaction, Profile].each do |model|
  if Dynamoid.adapter.list_tables.include?(model.table_name)
    puts "  exists  #{model.table_name}"
  else
    model.create_table(sync: true)
    puts "  created #{model.table_name}"
  end
end
