# frozen_string_literal: true

# Procedure inputs. Every procedure takes exactly one input struct — no
# positional args, no `params` hash, no strong-parameter permit lists. The
# struct *is* the permit list, enforced by T::Struct construction.

module Bookface
  module Schema
    # --- posts -------------------------------------------------------------

    class FeedInput < T::Struct
      const :limit,  Integer, default: 25
      const :cursor, T.nilable(String)
    end

    # What the browser can honestly report after uploading: the key it was
    # given, plus what it uploaded. Dimensions are optional because reading them
    # requires decoding the image.
    class UploadedMedia < T::Struct
      const :key,          String
      const :content_type, String
      const :width,        T.nilable(Integer)
      const :height,       T.nilable(Integer)
    end

    class PostId < T::Struct
      const :id, String
    end

    class CreatePostInput < T::Struct
      const :body,  T.nilable(String)
      # Client uploads to S3 first (uploads.presign), then sends the keys. In
      # Rails this arrived as `media_json`, a JSON string parsed by
      # AttachedMedia; here it's already typed, so that parsing disappears.
      # Only the key and content type come from the client; `url` is filled in
      # by the server on the way out.
      const :media, T::Array[UploadedMedia], default: []
    end

    class UpdatePostInput < T::Struct
      const :id,   String
      const :body, String
    end

    # --- comments ----------------------------------------------------------

    class ThreadInput < T::Struct
      const :post_id, String
    end

    class CreateCommentInput < T::Struct
      const :post_id, String
      const :body,    String
      # Blank/nil means a top-level comment on the post; otherwise the reply
      # nests under the comment at this path. No Base64 — see DESIGN.md §1.
      const :parent_path, T.nilable(String)
    end

    class UpdateCommentInput < T::Struct
      const :post_id, String
      const :path,    String
      const :body,    String
    end

    class CommentRef < T::Struct
      const :post_id, String
      const :path,    String
    end

    # --- reactions ---------------------------------------------------------

    class ToggleReactionInput < T::Struct
      const :post_id, String
      # "post" or "comment#<path>" — the reaction's address within the thread.
      const :target,  String
      const :emoji,   String
    end

    # --- profiles ----------------------------------------------------------

    class UpdateProfileInput < T::Struct
      const :display_name, T.nilable(String)
      const :bio,          T.nilable(String)
      # Only honoured if it sits under the viewer's own upload prefix; otherwise
      # the existing avatar is kept. Same rule as ProfilesController.
      const :avatar_key,   T.nilable(String)
    end

    # --- uploads -----------------------------------------------------------

    class PresignInput < T::Struct
      const :content_type, String
    end

    # Procedures that genuinely take no arguments still take a struct, so the
    # generated clients stay uniform and adding a field later is not a breaking
    # signature change.
    class Empty < T::Struct; end
  end
end
