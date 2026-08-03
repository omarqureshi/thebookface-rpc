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
      reaction_counts :associative_array,
                      key_type_declaration: :string,
                      value_type_declaration: :integer,
                      default: {}
      comment_count :integer, :required
      created_at :string, :required
      editable :boolean, default: false
      deletable :boolean, default: false
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
        reaction_counts: record.reaction_counts,
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
    result [PostModel]

    def execute
      posts, = Post.page(limit:, cursor:)
      posts.map { |p| Present.post(p, Shared::Viewer.current) }
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
      media [Shared::MediaItem], default: []
    end
    result PostModel

    def execute
      viewer = Shared::Viewer.require!
      profile = Profile.for(viewer.sub)
      record = Post.new(
        body:,
        media: media.map(&:to_h),
        author_sub: viewer.sub,
        author_name: profile.display_name.presence || viewer.name,
        author_avatar: profile.avatar_key
      )
      record.save
      Present.post(record, Shared::Viewer.current)
    end
  end
end
