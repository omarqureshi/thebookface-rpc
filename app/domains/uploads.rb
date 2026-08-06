# frozen_string_literal: true

# Hands the browser a presigned POST so it can upload one image straight to the
# store, scoped to the viewer's own prefix. The bytes never pass through here.
module Uploads
  foobara_domain!

  class FormField < Foobara::Model
    attributes do
      name :string, :required
      value :string, :required
    end
  end

  class PresignedUpload < Foobara::Model
    attributes do
      url :string, :required
      # Same generator limitation: presigned form fields as pairs.
      fields [FormField], :required
      key :string, :required
    end
  end

  class Presign < Foobara::Command
    inputs do
      content_type :string, :required
    end
    result PresignedUpload
    possible_error :unsupported_media_type, context: { content_type: :string }

    def execute
      viewer = Shared::Viewer.require!
      unless MediaStorage.allowed_type?(content_type)
        return add_runtime_error(:unsupported_media_type, "Unsupported type", content_type:)
      end

      presigned = MediaStorage.presigned_upload(user_sub: viewer.sub, content_type:)
      { url: presigned.fetch(:url), key: presigned.fetch(:key),
        fields: presigned.fetch(:fields).map { |name, value| { name: name.to_s, value: value.to_s } } }
    end
  end

  # Runs after the bytes have landed, triggered by the store rather than by a
  # caller: S3 emits Object Created, EventBridge turns it into a command
  # invocation, and this consumes it from the queue.
  #
  # Presigning signs the DECLARED content type and a size range, so S3 enforces
  # those, but nothing checks the bytes. Without this a caller can store
  # anything at all as image/png and have CloudFront serve it from our own
  # domain — the upload is authenticated, so it is our user doing it, which is
  # exactly the case a signed policy cannot cover.
  #
  # Never reachable over HTTP (see QUEUE_ONLY): it deletes objects by key, and
  # the key is supplied by the trigger, not by a caller.
  class VerifyUpload < Foobara::Command
    inputs do
      key :string, :required
    end
    result :string

    def execute
      bytes = MediaStorage.first_bytes(key)
      # Gone already. An upload can be reaped between landing and being checked,
      # and a retry of this very message would see the same thing, so it is a
      # normal outcome rather than a failure to redeliver for.
      return "missing" unless bytes

      type = MediaStorage.sniff(bytes)
      return "ok" if type && MediaStorage.allowed_type?(type)

      MediaStorage.delete_objects([key])
      "deleted"
    end
  end
end
