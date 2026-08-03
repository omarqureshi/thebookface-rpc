# frozen_string_literal: true

# S3 media, kept deliberately thin. Locally there is no S3 — presigning returns
# a fake target so `uploads.presign` is exercisable without LocalStack, and the
# ownership rule (which is a *security* check, not an integration) runs for real.
require "fileutils"

module MediaStorage
  ALLOWED_TYPES = %w[image/jpeg image/png image/gif image/webp].freeze

  module_function

  def allowed_type?(content_type) = ALLOWED_TYPES.include?(content_type)

  # Every key a user may ever write lives under their own prefix. This is what
  # makes trusting a client-supplied avatar_key safe (ProfilesService).
  def prefix_for(user_sub) = "u/#{user_sub}/"

  def owned_by?(key, user_sub) = key.to_s.start_with?(prefix_for(user_sub))

  def presigned_upload(user_sub:, content_type:)
    ext = content_type.split("/").last
    key = "#{prefix_for(user_sub)}#{SecureRandom.uuid}.#{ext}"

    if local?
      # Points at the dev object store in config.ru, so the browser's upload
      # actually stores bytes and the image renders. Same shape as a presigned
      # S3 POST: the key travels in the form fields, not the URL.
      { url: "#{ENV.fetch('BOOKFACE_MEDIA_URL', 'http://localhost:9292/media')}",
        fields: { "key" => key, "Content-Type" => content_type },
        key: key }
    else
      raise NotImplementedError, "real S3 presigning not wired in the skeleton"
    end
  end

  # Locally this really deletes, so "deleting a post reaps its images" is a
  # behaviour the suite can assert rather than a claim in a comment.
  def delete_objects(keys)
    return if keys.empty?
    unless local?
      raise NotImplementedError, "real S3 delete not wired in the skeleton"
    end

    keys.each { |k| FileUtils.rm_f(path_for(k)) }
  end

  # Where the dev object store keeps bytes. config.ru serves from here.
  def local_dir = ENV.fetch("BOOKFACE_MEDIA_DIR", File.expand_path("../../tmp/media", __dir__))

  def path_for(key) = File.join(local_dir, key.to_s.tr("/", "_"))

  def public_url(key) = "#{ENV.fetch('BOOKFACE_MEDIA_URL', 'http://localhost:9292/media')}/#{key}"

  def local? = ENV.fetch("BOOKFACE_ENV", "local") == "local"
end
