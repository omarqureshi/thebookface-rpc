# frozen_string_literal: true

# ProfilesController → the `profiles` service.
#
# Singular in Rails (`resource :profile`) because it's always the viewer's own,
# keyed by their Cognito sub. That property survives: neither procedure takes an
# id, so there is no ownership check to get wrong.

module Bookface
  class ProfilesService < Prospect::Router
    path :profiles
    context Context

    deploy memory_size: 512, timeout: 10

    authenticated do
      # show and edit collapse into one query — `edit` only rendered a form.
      query :get, input: Schema::Empty, output: Schema::Profile do |_input, ctx|
        viewer = ctx.authenticated!
        Present.profile(Profile.for(viewer.sub), viewer)
      end

      mutation :update, input: Schema::UpdateProfileInput, output: Schema::Profile,
               errors: [Schema::Errors::ValidationFailed] do |input, ctx|
        viewer  = ctx.authenticated!
        profile = Profile.for(viewer.sub)

        profile.display_name = input.display_name
        profile.bio          = input.bio
        profile.avatar_key   = accepted_avatar_key(input.avatar_key, profile, viewer)
        profile.name         = viewer.name # snapshot for the reconcile fallback

        Save.call(profile)

        # Denormalized author snapshots on this user's posts and comments are
        # rewritten asynchronously. The consumer is a Lambda but not a procedure —
        # it's an SQS event handler and stays outside the router. DESIGN.md §5.
        ProfileReconciliation.enqueue(viewer.sub)

        Present.profile(profile, viewer)
      end
    end

    # The browser uploads the avatar straight to S3 and sends back its key. Trust
    # it only if it sits under this user's own upload prefix — all presigning
    # ever let them write — otherwise keep the existing avatar. Unchanged rule
    # from ProfilesController#accepted_avatar_key.
    def self.accepted_avatar_key(key, profile, viewer)
      return profile.avatar_key if key.blank?

      MediaStorage.owned_by?(key, viewer.sub) ? key : profile.avatar_key
    end
  end
end
