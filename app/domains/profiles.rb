# frozen_string_literal: true

# Singular by nature: every command acts on the viewer's own profile, keyed by
# their subject, so there is no id and no ownership check to get wrong.
module Profiles
  foobara_domain!

  class ProfileModel < Foobara::Model
    attributes do
      display_name :string
      bio :string
      avatar_key :string
      avatar_url :string
      # The name to show — chosen display name, else the identity provider's.
      # Computed server-side so every client agrees on the fallback.
      shown_name :string, :required
    end
  end

  module Present
    module_function

    def profile(record, viewer)
      { shown_name: record.shown_name.presence || viewer&.name.to_s }.tap do |h|
        h[:display_name] = record.display_name if record.display_name.present?
        h[:bio]          = record.bio if record.bio.present?
        if record.avatar_key.present?
          h[:avatar_key] = record.avatar_key
          h[:avatar_url] = MediaStorage.public_url(record.avatar_key)
        end
      end
    end
  end

  class GetProfile < Foobara::Command
    result ProfileModel

    def execute
      viewer = Shared::Viewer.require!
      Present.profile(Profile.for(viewer.sub), viewer)
    end
  end

  class UpdateProfile < Foobara::Command
    inputs do
      display_name :string
      bio :string
      # Honoured only if it sits under the viewer's own upload prefix; all
      # presigning ever let them write. Otherwise the existing avatar stands.
      avatar_key :string
    end
    result ProfileModel

    def execute
      viewer = Shared::Viewer.require!
      profile = Profile.for(viewer.sub)

      profile.display_name = display_name
      profile.bio = bio
      profile.avatar_key = accepted_avatar_key(profile, viewer)
      profile.name = viewer.name
      profile.save

      # Denormalized author snapshots are rewritten asynchronously. The consumer
      # is a Lambda but not a command — an event handler stays outside the
      # connector, as it stayed outside the router.
      ProfileReconciliation.enqueue(viewer.sub)

      Present.profile(profile, viewer)
    end

    private

    def accepted_avatar_key(profile, viewer)
      return profile.avatar_key if avatar_key.blank?

      MediaStorage.owned_by?(avatar_key, viewer.sub) ? avatar_key : profile.avatar_key
    end
  end
end
