# frozen_string_literal: true

# Wire types. Hand-written on purpose — these are NOT derived from the Dynamoid
# models. Deriving a contract from a persistence model is how internal fields
# (author_sub, feed_pk, raw caches) leak to clients; an allowlist is the whole
# safety property. See DESIGN.md §4.

module Bookface
  module Schema
    # One attached image. Only an S3 reference — the bytes live in S3, uploaded
    # straight from the browser via uploads.presign.
    class MediaItem < T::Struct
      const :key,          String
      # Where to actually fetch it. Sent rather than derived, so the client
      # never has to know the store's layout — and so moving to CloudFront is a
      # server change, not a client release.
      const :url,          String
      const :content_type, String
      const :width,        T.nilable(Integer)
      const :height,       T.nilable(Integer)
    end

    # The denormalized author snapshot stamped onto a post/comment at write time.
    # Note what's absent: author_sub. See DESIGN.md §4 — ownership is expressed
    # as `editable`, computed server-side, rather than shipping the Cognito
    # subject and asking every client to re-derive Ability.
    class Author < T::Struct
      const :name,       String
      const :avatar_key, T.nilable(String)
      # Same reasoning as MediaItem#url: the client renders what it is given
      # rather than reconstructing a URL from a key.
      const :avatar_url, T.nilable(String)
    end

    class Post < T::Struct
      const :id,         String
      const :body,       T.nilable(String)   # nil is legal: an image-only post
      const :author,     Author
      const :media,      T::Array[MediaItem], default: []

      # Emoji => count. A *map*, not a struct: the keys are user data and must
      # survive the TS client's snake_case→camelCase transform untouched.
      # This is the concrete case Prospect §7 warns about.
      const :reaction_counts, T::Hash[String, Integer], default: {}

      const :comment_count, Integer
      const :created_at,    Time

      # Viewer-dependent. Keeps Ability on the server.
      const :editable,   T::Boolean, default: false
      const :deletable,  T::Boolean, default: false
    end

    # A node in a post's comment thread.
    #
    # Deliberately FLAT rather than a nested tree: `path` is the materialized
    # path and `depth` is its separator count, so the client indents by depth in
    # one pass. Mirrors how the DynamoDB Query already returns pre-ordered rows,
    # and avoids a recursive wire type that Prospect's IR handles poorly.
    class Comment < T::Struct
      const :path,   String        # materialized path, e.g. "0001-ab/0002-cd"
      const :depth,  Integer       # path.count("/") — indentation level
      const :body,   T.nilable(String)   # nil when soft-deleted
      const :author, T.nilable(Author)   # nil when soft-deleted

      # A soft-deleted comment keeps its node so the subtree stays threaded, but
      # renders as "[deleted]".
      const :deleted, T::Boolean, default: false

      const :reaction_counts, T::Hash[String, Integer], default: {}
      const :created_at,      Time
      const :editable,        T::Boolean, default: false
      const :deletable,       T::Boolean, default: false
    end

    # A whole thread, flat and pre-ordered. Wrapped in a struct rather than
    # returning a bare array so fields (total, truncated, …) can be added later
    # without a breaking change to the output type.
    class CommentList < T::Struct
      const :comments, T::Array[Comment]
    end

    class Profile < T::Struct
      const :display_name, T.nilable(String)
      const :bio,          T.nilable(String)
      const :avatar_key,   T.nilable(String)
      const :avatar_url,   T.nilable(String)
      # The name to show: the chosen display name, else the identity provider's.
      # Computed server-side so every client agrees on the fallback.
      const :shown_name,   String
    end

    # A cursor-paginated feed page.
    #
    # The Rails app has no pagination — Post.recent returns every post. That's
    # tolerable for a server-rendered page and not for an API, so the contract
    # adds it. See DESIGN.md §6.3: this shape recurs enough that Prospect may
    # want it in the IR rather than each app reinventing it.
    class FeedPage < T::Struct
      const :posts,       T::Array[Post]
      const :next_cursor, T.nilable(String)
    end

    # The viewer's own reaction on each target in a thread: { target => emoji },
    # where target is "post" or "comment#<path>". Another genuine map.
    class MyReactions < T::Struct
      const :by_target, T::Hash[String, String], default: {}
    end

    # What reactions.toggle gives back: enough to repaint one reactions bar.
    # Replaces the Turbo Stream the Rails action rendered.
    class ReactionState < T::Struct
      const :target,          String
      const :reaction_counts, T::Hash[String, Integer], default: {}
      const :mine,            T.nilable(String)
    end

    # A presigned S3 POST for one image upload, scoped to the viewer's prefix.
    class PresignedUpload < T::Struct
      const :url,    String
      const :fields, T::Hash[String, String]
      const :key,    String
    end
  end
end
