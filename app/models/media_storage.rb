# frozen_string_literal: true

# S3 media, kept deliberately thin. Locally there is no S3 — presigning returns
# a fake target so `uploads.presign` is exercisable without LocalStack, and the
# ownership rule (which is a *security* check, not an integration) runs for real.
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
      { url: "http://localhost:9000/bookface-media",
        fields: { "key" => key, "Content-Type" => content_type },
        key: key }
    else
      raise NotImplementedError, "real S3 presigning not wired in the skeleton"
    end
  end

  def delete_objects(keys)
    return if local? || keys.empty?

    raise NotImplementedError, "real S3 delete not wired in the skeleton"
  end

  def public_url(key) = "http://localhost:9000/bookface-media/#{key}"

  def local? = ENV.fetch("BOOKFACE_ENV", "local") == "local"
end
