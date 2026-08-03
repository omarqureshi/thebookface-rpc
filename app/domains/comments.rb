# frozen_string_literal: true

# The Comments domain. Flat thread with a depth field, as on the Prospect
# branch: the materialized path already arrives pre-ordered, so no recursive
# wire type is needed.
module Comments
  foobara_domain!

  class CommentModel < Foobara::Model
    attributes do
      path :string, :required
      depth :integer, :required
      body :string
      author Shared::Author
      deleted :boolean, default: false
      reaction_counts :associative_array,
                      key_type_declaration: :string,
                      value_type_declaration: :integer,
                      default: {}
      created_at :string, :required
      editable :boolean, default: false
      deletable :boolean, default: false
    end
  end

  module Present
    module_function

    def comment(record, viewer)
      ability = Ability.new(viewer)
      {
        path: record.path,
        depth: record.depth,
        deleted: record.deleted?,
        reaction_counts: record.reaction_counts,
        created_at: Shared::Present.timestamp(record.created_at),
        editable: ability.can?(:update, record),
        deletable: ability.can?(:destroy, record)
      }.tap do |h|
        unless record.deleted?
          h[:body] = record.body if record.body
          h[:author] = Shared::Present.author(record)
        end
      end
    end
  end

  class ListThread < Foobara::Command
    description "A post's whole thread, in render order."
    inputs do
      post_id :string, :required
    end
    result [CommentModel]

    def execute
      Comment.thread_for(post_id).map { |c| Present.comment(c, Shared::Viewer.current) }
    end
  end

  class CreateComment < Foobara::Command
    inputs do
      post_id :string, :required
      body :string, :required
      # Blank means a top-level comment. No Base64 — that existed only to
      # survive a URL segment.
      parent_path :string
    end
    result CommentModel
    possible_error :post_not_found, context: { post_id: :string }

    def execute
      viewer = Shared::Viewer.require!
      Post.find(post_id)
      profile = Profile.for(viewer.sub)
      record = Comment.new(
        post_id:, body:, parent_path:,
        author_sub: viewer.sub,
        author_name: profile.display_name.presence || viewer.name,
        author_avatar: profile.avatar_key
      )
      record.save
      Present.comment(record, viewer)
    rescue Dynamoid::Errors::RecordNotFound
      add_runtime_error :post_not_found, "No such post", post_id:
    end
  end

  class UpdateComment < Foobara::Command
    inputs do
      post_id :string, :required
      path :string, :required
      body :string, :required
    end
    result CommentModel
    possible_error :not_found, context: { path: :string }
    possible_error :forbidden, context: { path: :string }

    def execute
      viewer = Shared::Viewer.require!
      record = Comment.find(post_id, range_key: path)
      return add_runtime_error(:forbidden, "Not yours", path:) unless Ability.new(viewer).can?(:update, record)

      record.body = body
      record.save
      Present.comment(record, viewer)
    rescue Dynamoid::Errors::RecordNotFound
      add_runtime_error :not_found, "No such comment", path:
    end
  end

  class DestroyComment < Foobara::Command
    inputs do
      post_id :string, :required
      path :string, :required
    end
    result CommentModel
    possible_error :not_found, context: { path: :string }
    possible_error :forbidden, context: { path: :string }

    def execute
      viewer = Shared::Viewer.require!
      record = Comment.find(post_id, range_key: path)
      return add_runtime_error(:forbidden, "Not yours", path:) unless Ability.new(viewer).can?(:destroy, record)

      # Soft-deletes when it has replies, so the subtree stays threaded.
      record.remove!
      Present.comment(record, viewer)
    rescue Dynamoid::Errors::RecordNotFound
      add_runtime_error :not_found, "No such comment", path:
    end
  end
end
