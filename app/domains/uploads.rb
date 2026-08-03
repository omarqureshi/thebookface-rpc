# frozen_string_literal: true

# Hands the browser a presigned POST so it can upload one image straight to the
# store, scoped to the viewer's own prefix. The bytes never pass through here.
module Uploads
  foobara_domain!

  class PresignedUpload < Foobara::Model
    attributes do
      url :string, :required
      fields :associative_array, :required,
             key_type_declaration: :string,
             value_type_declaration: :string
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
        fields: presigned.fetch(:fields).transform_keys(&:to_s) }
    end
  end
end
