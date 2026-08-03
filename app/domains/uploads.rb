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
end
