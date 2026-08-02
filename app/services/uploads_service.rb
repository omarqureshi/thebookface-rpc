# frozen_string_literal: true

# UploadsController → the `uploads` service.
#
# Hands the browser a presigned POST so it can upload one image straight to S3,
# scoped to the viewer's own prefix — they can only ever write their own keys.
# The bytes never pass through Lambda.
#
# It's a `mutation` rather than a `query` despite reading nothing: it mints a
# credential, so it must not be cached, batched with reads, or retried blindly.
# `query` in Prospect implies GET-able and cacheable (§5 there), which this is
# emphatically not.

module Bookface
  class UploadsService < Prospect::Router
    path :uploads
    context Context

    # Pure signing — no store access, so the smallest useful size.
    deploy memory_size: 512, timeout: 10

    authenticated do
      mutation :presign, input: Schema::PresignInput, output: Schema::PresignedUpload,
               errors: [Schema::Errors::UnsupportedMediaType] do |input, ctx|
        viewer = ctx.authenticated!

        unless MediaStorage.allowed_type?(input.content_type)
          # Rails: `render json: { error: "unsupported type" }, status: :unprocessable_entity`
          raise Schema::Errors::UnsupportedMediaType.new(content_type: input.content_type)
        end

        presigned = MediaStorage.presigned_upload(
          user_sub: viewer.sub, content_type: input.content_type
        )

        Schema::PresignedUpload.new(
          url:    presigned.fetch(:url),
          fields: presigned.fetch(:fields).transform_keys(&:to_s),
          key:    presigned.fetch(:key)
        )
      end
    end
  end
end
