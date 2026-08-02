# frozen_string_literal: true

# The shared plumbing every service needs. In Rails most of this lived in
# ApplicationController as before_actions, rescue_from handlers and helpers;
# with no controller superclass to inherit from, it becomes explicit
# collaborators the procedures call.
#
# That is arguably an improvement: `rescue_from CanCan::AccessDenied` acting at a
# distance is replaced by `Authorize.call`, which is visible at the call site.

module Bookface
  # Loads, converting the store's "missing" into a contract error. Replaces the
  # `rescue Dynamoid::Errors::RecordNotFound → redirect_to root_path` that
  # appeared in four controllers.
  module Find
    module_function

    def post(id)
      Post.find(id)
    rescue Dynamoid::Errors::RecordNotFound
      raise Schema::Errors::NotFound.new(resource: "post", id: id)
    end

    def comment(post_id, path)
      Comment.find(post_id, range_key: path)
    rescue Dynamoid::Errors::RecordNotFound
      raise Schema::Errors::NotFound.new(resource: "comment", id: "#{post_id}/#{path}")
    end
  end

  # Persist or raise a typed validation error. Replaces the
  # `if @post.save … else render :edit, status: :unprocessable_entity` branch.
  module Save
    module_function

    def call(record)
      return record if record.save

      raise Schema::Errors::ValidationFailed.new(
        errors: record.errors.to_hash.transform_keys(&:to_s)
                      .transform_values { |msgs| Array(msgs).map(&:to_s) }
      )
    end
  end

  # CanCanCan, unchanged — authentication moved to the edge, authorization did
  # not. DESIGN.md §3.
  module Authorize
    module_function

    def call(ctx, action, record)
      return record if ctx.ability.can?(action, record)

      raise Schema::Errors::Forbidden.new(
        action: action.to_s,
        resource: record.class.name.downcase
      )
    end
  end

  # The denormalized author snapshot stamped onto new posts and comments, kept in
  # step afterwards by the profile reconcile job. Was
  # ApplicationController#author_attributes.
  module Author
    module_function

    def snapshot_for(viewer)
      profile = Profile.for(viewer.sub)
      {
        author_sub:    viewer.sub,
        author_name:   profile.display_name.presence || viewer.name,
        author_avatar: profile.avatar_key
      }
    end
  end

  # Model → wire type. The allowlist boundary: everything a client sees passes
  # through here, so a new Dynamoid field can never leak by accident.
  #
  # `editable`/`deletable` are computed here rather than shipping author_sub and
  # letting clients re-derive Ability. DESIGN.md §4.
  module Present
    module_function

    def post(record, ctx)
      Schema::Post.new(
        id:              record.id,
        body:            record.body,
        author:          author(record),
        media:           record.media_items.map { |m| media(m) },
        reaction_counts: record.reaction_counts,
        comment_count:   record.comment_count,
        # .to_time is load-bearing: Dynamoid hands back a DateTime and T::Struct
        # will not coerce it to Time. See DESIGN.md §6.5.
        created_at:      record.created_at.to_time,
        editable:        ctx.ability.can?(:update, record),
        deletable:       ctx.ability.can?(:destroy, record)
      )
    end

    def comment(record, ctx)
      Schema::Comment.new(
        path:            record.path,
        depth:           record.depth,
        body:            record.body,
        author:          (author(record) unless record.deleted?),
        deleted:         record.deleted?,
        reaction_counts: record.reaction_counts,
        # .to_time is load-bearing: Dynamoid hands back a DateTime and T::Struct
        # will not coerce it to Time. See DESIGN.md §6.5.
        created_at:      record.created_at.to_time,
        editable:        ctx.ability.can?(:update, record),
        deletable:       ctx.ability.can?(:destroy, record)
      )
    end

    def profile(record)
      Schema::Profile.new(
        display_name: record.display_name,
        bio:          record.bio,
        avatar_key:   record.avatar_key
      )
    end

    def author(record)
      Schema::Author.new(name: record.author_name.to_s, avatar_key: record.author_avatar)
    end

    def media(item)
      Schema::MediaItem.new(
        key:          item["key"],
        content_type: item["content_type"],
        width:        item["width"],
        height:       item["height"]
      )
    end
  end
end
