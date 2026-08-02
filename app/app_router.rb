# frozen_string_literal: true

# The whole API surface. This is the object the CDK stack reads at synth time to
# decide what to deploy (Prospect DESIGN.md §6) and the object the emitters read
# to generate clients — one router, consumed three ways.

require_relative "context"
require_relative "support"
require_relative "schema/types"
require_relative "schema/inputs"
require_relative "schema/errors"
require_relative "services/posts_service"
require_relative "services/comments_service"
require_relative "services/reactions_service"
require_relative "services/profiles_service"
require_relative "services/uploads_service"

module Bookface
  class AppRouter < Prospect::Router
    mount PostsService
    mount CommentsService
    mount ReactionsService
    mount ProfilesService
    mount UploadsService
  end
end

# Procedure surface, for reference:
#
#   posts.feed        query     public
#   posts.get         query     public
#   posts.create      mutation  authed
#   posts.update      mutation  authed + owner
#   posts.destroy     mutation  authed + owner   (own Lambda — see deploy:)
#   comments.thread   query     public
#   comments.create   mutation  authed
#   comments.update   mutation  authed + owner
#   comments.destroy  mutation  authed + owner
#   reactions.mine    query     public (empty when signed out)
#   reactions.toggle  mutation  authed
#   profiles.get      query     authed
#   profiles.update   mutation  authed
#   uploads.presign   mutation  authed
#
# 14 procedures across 5 services, from 7 controllers and 21 routes.
