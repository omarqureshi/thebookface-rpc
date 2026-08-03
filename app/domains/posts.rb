# frozen_string_literal: true

# The Posts domain. Where the Prospect branch had a router of procedures, this
# is a Foobara domain of commands — and the domain is what a deployment unit
# will be derived from, since `connect(Posts)` registers exactly these.
module Posts
  foobara_domain!

  # See config.ru: the caller is a thread-local for this spike, not Foobara's
  # current_user, because that is scoped to authorization rules.
  def self.viewer = Thread.current[:bookface_viewer]

  # Wire types, declared in Foobara's type DSL rather than as Sorbet structs.
  # Same allowlist discipline: nothing here comes from the Dynamoid model
  # automatically, so a new persisted field cannot leak.
  class Author < Foobara::Model
    attributes do
      name :string, :required
      avatar_url :string
    end
  end

  class MediaItem < Foobara::Model
    attributes do
      key :string, :required
      url :string, :required
      content_type :string, :required
      width :integer
      height :integer
    end
  end

  class PostModel < Foobara::Model
    attributes do
      id :string, :required
      body :string
      author Author, :required
      media [MediaItem], default: []
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
        # Foobara validates the RESULT too, and an optional attribute means
        # "may be absent", not "may be nil" — so omit rather than pass nil.
        # Prospect's IR never checked outputs at all.
        author: { name: record.author_name.to_s }.tap { |a|
          a[:avatar_url] = MediaStorage.public_url(record.author_avatar) if record.author_avatar.present?
        },
        media: record.media_items.map { |m|
          { key: m["key"], url: MediaStorage.public_url(m["key"]),
            content_type: m["content_type"] }.tap { |h|
              h[:width]  = m["width"].to_i  if m["width"]
              h[:height] = m["height"].to_i if m["height"]
            }
        },
        reaction_counts: record.reaction_counts,
        comment_count: record.comment_count,
        created_at: record.created_at.to_time.utc.iso8601,
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
      posts.map { |p| Present.post(p, Posts.viewer) }
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
      Present.post(record, Posts.viewer)
    rescue Dynamoid::Errors::RecordNotFound
      add_runtime_error :not_found, "No such post", id:
    end
  end

  class CreatePost < Foobara::Command
    inputs do
      body :string
      media [MediaItem], default: []
    end
    result PostModel

    def execute
      viewer = Posts.viewer
      profile = Profile.for(viewer.sub)
      record = Post.new(
        body:,
        media: media.map(&:to_h),
        author_sub: viewer.sub,
        author_name: profile.display_name.presence || viewer.name,
        author_avatar: profile.avatar_key
      )
      record.save
      Present.post(record, Posts.viewer)
    end
  end
end
