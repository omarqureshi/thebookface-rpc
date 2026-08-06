# frozen_string_literal: true

# S3 media, kept deliberately thin.
#
# Locally there is no S3: presigning points at the dev object store in config.ru
# so the browser really stores bytes and the image renders, and the ownership
# rule (a *security* check, not an integration) runs for real either way.
#
# Deployed, this talks to S3. aws-sdk-s3 is required lazily rather than in
# config/boot: only the units that touch media carry it (see units/*.gemfile),
# and requiring it up front would break comments and reactions on boot.
require "fileutils"

module MediaStorage
  ALLOWED_TYPES = %w[image/jpeg image/png image/gif image/webp].freeze

  # Signed into the upload policy, so these are enforced by S3 rather than by
  # the browser being polite.
  MAX_UPLOAD_BYTES = 10 * 1024 * 1024
  UPLOAD_WINDOW = 300 # seconds

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
      # A presigned POST, not a PUT: the browser submits a form, which is what
      # makes the dev object store in config.ru the same shape as S3 and lets
      # web/src/upload.ts be identical in both.
      #
      # The conditions are the point. They are signed, so the browser cannot
      # widen them: it may write this exact key and no other (so a caller cannot
      # write outside its own prefix), with this content type, up to this size,
      # for the next five minutes.
      # Required BEFORE the constant is mentioned, not inside s3_client: Ruby
      # resolves Aws::S3::PresignedPost before evaluating the arguments, so a
      # require hidden in one of them runs too late.
      require "aws-sdk-s3"

      post = Aws::S3::PresignedPost.new(
        s3_client.config.credentials,
        s3_client.config.region,
        bucket,
        key: key,
        content_type: content_type,
        content_length_range: 1..MAX_UPLOAD_BYTES,
        signature_expiration: Time.now + UPLOAD_WINDOW
      )

      { url: post.url, fields: post.fields, key: key }
    end
  end

  # What the bytes actually are, regardless of what the uploader claimed.
  #
  # The presigned POST signs the DECLARED Content-Type and a size range, so S3
  # enforces those — but nothing checks the bytes. A caller can therefore store
  # anything it likes as image/png, and CloudFront will serve it from our own
  # domain. Sniffing is how that gets caught.
  MAGIC = {
    "image/jpeg" => ->(b) { b.start_with?("\xFF\xD8\xFF".b) },
    "image/png" => ->(b) { b.start_with?("\x89PNG\r\n\x1A\n".b) },
    "image/gif" => ->(b) { b.start_with?("GIF87a".b) || b.start_with?("GIF89a".b) },
    # RIFF....WEBP — the four bytes between are the file size.
    "image/webp" => ->(b) { b.start_with?("RIFF".b) && b[8, 4] == "WEBP".b }
  }.freeze

  # Enough for the longest signature above (RIFF + size + WEBP).
  SNIFF_BYTES = 12

  def sniff(bytes)
    return nil if bytes.nil? || bytes.empty?

    MAGIC.find { |_type, matches| matches.call(bytes.b) }&.first
  end

  # Nil when the object is not there. That is not an error: an upload can be
  # reaped between being stored and being checked.
  def first_bytes(key, count = SNIFF_BYTES)
    if local?
      File.binread(path_for(key), count)
    else
      s3_client.get_object(bucket: bucket, key: key.to_s, range: "bytes=0-#{count - 1}").body.read
    end
  rescue Errno::ENOENT
    nil
  rescue StandardError => e
    # aws-sdk raises NoSuchKey, but only once aws-sdk-s3 is loaded, so this
    # cannot name the class without forcing the require on every unit.
    raise unless e.class.name.to_s.end_with?("NoSuchKey", "NotFound")

    nil
  end

  # Locally this really deletes, so "deleting a post reaps its images" is a
  # behaviour the suite can assert rather than a claim in a comment.
  def delete_objects(keys)
    return if keys.empty?

    unless local?
      # Batched: deleting a post reaps every image on it, and one call per key
      # would make deleting a photo-heavy post slow enough to matter.
      keys.each_slice(1000) do |batch|
        s3_client.delete_objects(
          bucket: bucket, delete: { objects: batch.map { |k| { key: k.to_s } } }
        )
      end
      return
    end

    keys.each { |k| FileUtils.rm_f(path_for(k)) }
  end

  def bucket = ENV.fetch("MEDIA_BUCKET")

  def s3_client
    require "aws-sdk-s3"
    # Memoised at cold-start scope: building a client per request costs a
    # credential lookup and an endpoint resolve for no benefit.
    @s3_client ||= Aws::S3::Client.new
  end


  # Where the dev object store keeps bytes. config.ru serves from here.
  def local_dir = ENV.fetch("BOOKFACE_MEDIA_DIR", File.expand_path("../../tmp/media", __dir__))

  def path_for(key) = File.join(local_dir, key.to_s.tr("/", "_"))

  # Deployed, BOOKFACE_MEDIA_URL is this app's own /media path on CloudFront —
  # so the bucket stays private (CloudFront reads it through an Origin Access
  # Control) and images are same-origin. Locally it is the dev object store.
  def public_url(key) = "#{ENV.fetch('BOOKFACE_MEDIA_URL', 'http://localhost:9292/media')}/#{key}"

  def local? = ENV.fetch("BOOKFACE_ENV", "local") == "local"
end
