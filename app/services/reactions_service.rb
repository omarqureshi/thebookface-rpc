# frozen_string_literal: true

# ReactionsController → the `reactions` service.
#
# The Rails action returned a Turbo Stream that replaced one reactions bar in
# the DOM. Here it returns the data that bar needs — counts plus the viewer's own
# emoji — and rendering is the client's problem. The `respond_to` block, the
# partial, and `helpers.reactions_dom_id` all disappear.

module Bookface
  class ReactionsService < Prospect::Router
    path :reactions
    context Context

    # Reaction.toggle is a small transactional write and `mine` is a single
    # Query, so this service is cheaper than posts or comments.
    deploy memory_size: 512, timeout: 10

    # The viewer's own reactions across a whole thread: { target => emoji }, one
    # Query. Batched alongside posts.get and comments.thread for a post view
    # (DESIGN.md §2). Returns empty rather than erroring when signed out, which
    # is what the Rails view did with `current_user&.reactions(post) || {}`.
    query :mine, input: Schema::ThreadInput, output: Schema::MyReactions do |input, ctx|
      viewer = ctx.viewer
      next Schema::MyReactions.new unless viewer

      Schema::MyReactions.new(by_target: Reaction.mine_for_post(input.post_id, viewer.sub))
    end

    authenticated do
      # One entry point for add / switch / remove, as in the Rails action.
      mutation :toggle, input: Schema::ToggleReactionInput, output: Schema::ReactionState,
               errors: [Schema::Errors::NotFound,
                        Schema::Errors::UnsupportedReaction] do |input, ctx|
        viewer = ctx.authenticated!
        post = Find.post(input.post_id)

        begin
          Reaction.toggle(
            post_id: post.id, target: input.target,
            user_sub: viewer.sub, emoji: input.emoji
          )
        rescue ArgumentError
          # Rails: `redirect_back alert: "That reaction isn't allowed."`
          raise Schema::Errors::UnsupportedReaction.new(emoji: input.emoji)
        end

        # Reload the subject so its cached counts are fresh — the post itself, or
        # the comment addressed by "comment#<path>".
        subject = if input.target == "post"
                    Find.post(post.id)
                  else
                    Find.comment(post.id, input.target.delete_prefix("comment#"))
                  end

        Schema::ReactionState.new(
          target:          input.target,
          reaction_counts: subject.reaction_counts,
          mine:            Reaction.mine_for_post(post.id, viewer.sub)[input.target]
        )
      end
    end
  end
end
