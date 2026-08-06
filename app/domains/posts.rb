# frozen_string_literal: true

# The Posts domain. Where the Prospect branch had a router of procedures, this
# is a Foobara domain of commands — and the domain is what a deployment unit
# will be derived from, since `connect(Posts)` registers exactly these.
module Posts
  foobara_domain!

  # The caller comes from Shared::Viewer — see config.ru.

  # Wire types, declared in Foobara's type DSL rather than as Sorbet structs.
  # Same allowlist discipline: nothing here comes from the Dynamoid model
  # automatically, so a new persisted field cannot leak.
  class PostModel < Foobara::Model
    attributes do
      id :string, :required
      body :string
      author Shared::Author, :required
      media [Shared::MediaItem], default: []
      # Emoji => count. Foobara's associative_array is the analogue of the IR's
      # `map` node: keys are data, not field names.
      reaction_counts [Shared::ReactionCount], default: []
      comment_count :integer, :required
      created_at :string, :required
      editable :boolean, default: false
      deletable :boolean, default: false
    end
  end

  # One page of the feed. A model rather than a bare list because the cursor has
  # to travel with the posts — Post.page returns both, and dropping the cursor
  # would end pagination at the first page.
  class PostPage < Foobara::Model
    attributes do
      posts [PostModel], :required
      next_cursor :string
    end
  end

  module Present
    module_function

    def post(record, viewer)
      ability = Ability.new(viewer)
      {
        id: record.id,
        **(record.body ? { body: record.body } : {}),
        author: Shared::Present.author(record),
        media: record.media_items.map { |m| Shared::Present.media(m) },
        reaction_counts: Shared::Present.reaction_counts(record),
        comment_count: record.comment_count,
        created_at: Shared::Present.timestamp(record.created_at),
        editable: ability.can?(:update, record),
        deletable: ability.can?(:destroy, record)
      }
    end
  end

  class ListPosts < Foobara::Command
    description "The feed, newest first."

    inputs do
      limit :integer, default: 25
      cursor :string
    end
    result PostPage

    def execute
      posts, next_cursor = Post.page(limit:, cursor:)
      viewer = Shared::Viewer.current
      { posts: posts.map { |p| Present.post(p, viewer) }, **(next_cursor ? { next_cursor: } : {}) }
    end
  end

  class GetPost < Foobara::Command
    inputs do
      id :string, :required
    end
    result PostModel
    possible_error :not_found, context: { id: :string }

    def execute
      record = Post.find(id)
      Present.post(record, Shared::Viewer.current)
    rescue Dynamoid::Errors::RecordNotFound
      add_runtime_error :not_found, "No such post", id:
    end
  end

  class CreatePost < Foobara::Command
    inputs do
      body :string
      media [Shared::MediaUpload], default: []
    end
    result PostModel

    def execute
      viewer = Shared::Viewer.require!
      profile = Profile.for(viewer.sub)
      record = Post.new(
        body:,
        media: media.map(&:to_h),
        author_sub: viewer.sub,
        # shown_name, not display_name: ProfileReconciliation rewrites this
        # field to profile.shown_name on the next profile save, so stamping
        # anything else here means the name silently changes later. They differ
        # whenever the identity claim has moved on from what the last profile
        # save stamped.
        author_name: profile.shown_name.presence || viewer.name,
        author_avatar: profile.avatar_key
      )
      record.save
      Present.post(record, Shared::Viewer.current)
    end
  end

  class UpdatePost < Foobara::Command
    inputs do
      id :string, :required
      body :string, :required
    end
    result PostModel
    possible_error :not_found, context: { id: :string }
    possible_error :forbidden, context: { id: :string }

    def execute
      viewer = Shared::Viewer.require!
      record = Post.find(id)
      return add_runtime_error(:forbidden, "Not yours", id:) unless Ability.new(viewer).can?(:update, record)

      record.body = body
      record.save
      Present.post(record, viewer)
    rescue Dynamoid::Errors::RecordNotFound
      add_runtime_error :not_found, "No such post", id:
    end
  end

  class DestroyPost < Foobara::Command
    # Deployment metadata on the command, carried through the manifest into the
    # plan — this used to be a SIZING constant in the CDK stack, out-of-band
    # from the thing that knows why it is needed.
    extend Foobara::AWS::Lambda
    # destroy_with_thread! deletes a post, its whole comment tree and every
    # reaction on any of them. One vCPU (Lambda allocates CPU by memory; 1769MB
    # is the point where a function gets a full one) and room to finish.
    aws_lambda vcpu: 1, timeout: 60
    description "Cascading delete across posts, comments and reactions, then images."
    inputs do
      id :string, :required
    end
    result :boolean
    possible_error :not_found, context: { id: :string }
    possible_error :forbidden, context: { id: :string }

    def execute
      viewer = Shared::Viewer.require!
      record = Post.find(id)
      return add_runtime_error(:forbidden, "Not yours", id:) unless Ability.new(viewer).can?(:destroy, record)

      record.destroy_with_thread!
      true
    rescue Dynamoid::Errors::RecordNotFound
      add_runtime_error :not_found, "No such post", id:
    end
  end
end
