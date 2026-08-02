# frozen_string_literal: true

# CommentsController → the `comments` service.
#
# Two changes from Rails worth noting:
#
#   * `thread` is new. Rails had no comments#index — the thread was loaded by
#     posts#show. Splitting the services means the thread needs its own
#     procedure, which the client batches alongside posts.get (DESIGN.md §2).
#   * Comments are addressed by (post_id, path) directly. The Base64 encoding in
#     Comment#to_param existed only to survive a URL segment.

module Bookface
  class CommentsService < Prospect::Router
    path :comments
    context Context

    deploy memory_size: 1024, timeout: 10

    # One Query on the comments partition, returned pre-ordered by the path sort
    # key. Flat, with depth — the client indents. DESIGN.md §4.
    query :thread, input: Schema::ThreadInput, output: Schema::CommentList do |input, ctx|
      Schema::CommentList.new(
        comments: Comment.thread_for(input.post_id).map { |c| Present.comment(c, ctx) }
      )
    end

    authenticated do
      mutation :create, input: Schema::CreateCommentInput, output: Schema::Comment,
               errors: [Schema::Errors::NotFound, Schema::Errors::ValidationFailed] do |input, ctx|
        viewer = ctx.authenticated!
        post = Find.post(input.post_id) # 404s before writing an orphan
        comment = Comment.new(
          post_id: post.id,
          parent_path: input.parent_path,
          body: input.body,
          **Author.snapshot_for(viewer)
        )
        Save.call(comment)
        Present.comment(comment, ctx)
      end

      mutation :update, input: Schema::UpdateCommentInput, output: Schema::Comment,
               errors: [Schema::Errors::NotFound, Schema::Errors::Forbidden,
                        Schema::Errors::ValidationFailed] do |input, ctx|
        comment = Find.comment(input.post_id, input.path)
        Authorize.call(ctx, :update, comment)
        comment.body = input.body
        Save.call(comment)
        Present.comment(comment, ctx)
      end

      # Comment#remove! soft-deletes when there are replies (so the subtree stays
      # threaded) and hard-deletes otherwise. Both cases return the node, because
      # a soft-deleted comment is still rendered — as "[deleted]".
      mutation :destroy, input: Schema::CommentRef, output: Schema::Comment,
               errors: [Schema::Errors::NotFound, Schema::Errors::Forbidden] do |input, ctx|
        comment = Find.comment(input.post_id, input.path)
        Authorize.call(ctx, :destroy, comment)
        comment.remove!
        Present.comment(comment, ctx)
      end
    end
  end
end
