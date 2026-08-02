# frozen_string_literal: true

# PostsController → the `posts` service. One Lambda, routed at
# /rpc/posts/{proxy+}. Five REST actions become three mutations plus two
# queries; `new` and `edit` had no server-side work to do and are gone.

module Bookface
  class PostsService < Prospect::Router
    path :posts
    context Context

    deploy memory_size: 1024, timeout: 10

    # --- reads (public — Ability grants :read to everyone) ------------------

    # PostsController#index. Adds cursor pagination, which the Rails action
    # didn't need and an API does. See DESIGN.md §6.3.
    query :feed, input: Schema::FeedInput, output: Schema::FeedPage do |input, ctx|
      posts, cursor = Post.page(limit: input.limit, cursor: input.cursor)
      Schema::FeedPage.new(
        posts: posts.map { |p| Present.post(p, ctx) },
        next_cursor: cursor
      )
    end

    # PostsController#show, minus the comment thread and the viewer's reactions —
    # those belong to their own services and the client batches all three into
    # one round trip. DESIGN.md §2.
    query :get, input: Schema::PostId, output: Schema::Post,
          errors: [Schema::Errors::NotFound] do |input, ctx|
      Present.post(Find.post(input.id), ctx)
    end

    # --- writes ------------------------------------------------------------

    # Everything below requires a signed-in viewer. Replaces
    # `before_action :require_login`.
    #
    # NOTE (DESIGN.md §6.1): block-scoped middleware is a proposal, not settled
    # Prospect DSL. It reads well but hides its own extent in a long file.
    authenticated do
      # PostsController#create. The media JSON parsing that AttachedMedia did is
      # gone — input.media is already typed.
      mutation :create, input: Schema::CreatePostInput, output: Schema::Post,
               errors: [Schema::Errors::ValidationFailed] do |input, ctx|
        viewer = ctx.authenticated!
        post = Post.new(
          body: input.body,
          media: input.media.map(&:serialize),
          **Author.snapshot_for(viewer)
        )
        Save.call(post)
        Present.post(post, ctx)
      end

      mutation :update, input: Schema::UpdatePostInput, output: Schema::Post,
               errors: [Schema::Errors::NotFound, Schema::Errors::Forbidden,
                        Schema::Errors::ValidationFailed] do |input, ctx|
        post = Find.post(input.id)
        Authorize.call(ctx, :update, post)
        post.body = input.body
        Save.call(post)
        Present.post(post, ctx)
      end

      # Cascading delete across posts, comments and reactions, then S3. Slower
      # and burstier than the rest of the service, so it takes its own Lambda.
      #
      # `granularity: :dedicated` matters here rather than being decoration:
      # without it this procedure shares the posts function and drags the whole
      # service — including the hot `feed` path — up to 1769MB, because the
      # construct takes the largest requested memory for a shared unit.
      # Confirmed by synthesising it both ways.
      mutation :destroy, input: Schema::PostId, output: Schema::Empty,
               errors: [Schema::Errors::NotFound, Schema::Errors::Forbidden],
               deploy: { memory_size: 1769, timeout_seconds: 60,
                         granularity: :dedicated } do |input, ctx|
        post = Find.post(input.id)
        Authorize.call(ctx, :destroy, post)
        post.destroy_with_thread!
        Schema::Empty.new
      end
    end
  end
end
