# frozen_string_literal: true

# Wire types used by more than one domain.
#
# Worth being explicit about the consequence: a Comments-only Lambda must load
# this file, because its CommentModel references Shared::Author. Shared types
# are a coupling between deployment units, exactly as a shared gem would be.
# Keeping the set small is what keeps units independent.
module Shared
  foobara_domain!

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

  # The caller, for this spike, reaches commands through a thread-local set by
  # middleware. See config.ru — Foobara keeps the caller out of `execute` on
  # purpose, and this is the shortcut, not the idiom.
  module Viewer
    module_function

    def current = Thread.current[:bookface_viewer]

    def require!
      current || raise(Foobara::Command::UnexpectedError, "not signed in")
    end
  end

  # Model -> wire shape. The allowlist boundary, as on the Prospect branch:
  # nothing reaches a client that does not pass through here.
  module Present
    module_function

    def author(record)
      { name: record.author_name.to_s }.tap do |a|
        a[:avatar_url] = MediaStorage.public_url(record.author_avatar) if record.author_avatar.present?
      end
    end

    def media(item)
      { key: item["key"], url: MediaStorage.public_url(item["key"]),
        content_type: item["content_type"] }.tap do |h|
        h[:width]  = item["width"].to_i  if item["width"]
        h[:height] = item["height"].to_i if item["height"]
      end
    end

    def timestamp(value) = value.to_time.utc.iso8601
  end
end
