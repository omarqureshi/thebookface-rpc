# frozen_string_literal: true

module Reactions
  foobara_domain!

  # What a reactions bar needs to repaint. The Rails action returned a Turbo
  # Stream; this returns the data and rendering is the client's problem.
  class ReactionState < Foobara::Model
    attributes do
      target :string, :required
      reaction_counts :associative_array,
                      key_type_declaration: :string,
                      value_type_declaration: :integer,
                      default: {}
      mine :string
    end
  end

  class MyReactions < Foobara::Command
    description "The viewer's own reactions across a thread: target => emoji."
    inputs do
      post_id :string, :required
    end
    # Public but viewer-dependent — the case Foobara's connector cannot
    # authenticate for, since it only authenticates commands that require it.
    # See config.ru.
    result :associative_array, key_type_declaration: :string, value_type_declaration: :string

    def execute
      viewer = Shared::Viewer.current
      return {} unless viewer

      Reaction.mine_for_post(post_id, viewer.sub)
    end
  end

  class ToggleReaction < Foobara::Command
    description "Add, switch or remove the viewer's reaction. One entry point."
    inputs do
      post_id :string, :required
      target :string, :required   # "post" or "comment#<path>"
      emoji :string, :required
    end
    result ReactionState
    possible_error :not_found, context: { post_id: :string }
    possible_error :unsupported_reaction, context: { emoji: :string }

    def execute
      viewer = Shared::Viewer.require!
      post = Post.find(post_id)

      begin
        Reaction.toggle(post_id: post.id, target:, user_sub: viewer.sub, emoji:)
      rescue ArgumentError
        return add_runtime_error(:unsupported_reaction, "Not an allowed reaction", emoji:)
      end

      subject = if target == "post"
                  Post.find(post.id)
                else
                  Comment.find(post.id, range_key: target.delete_prefix("comment#"))
                end

      { target:, reaction_counts: subject.reaction_counts }.tap do |h|
        mine = Reaction.mine_for_post(post.id, viewer.sub)[target]
        h[:mine] = mine if mine
      end
    rescue Dynamoid::Errors::RecordNotFound
      add_runtime_error :not_found, "No such post", post_id:
    end
  end
end
