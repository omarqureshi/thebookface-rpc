# frozen_string_literal: true

# Async fan-out that rewrites the denormalized author snapshot on a user's posts
# and comments after they change their display name or avatar.
#
# Deliberately NOT a Prospect service: it's an SQS event handler, not a
# procedure. Keeping it out of the router is the point — a Lambda is not
# automatically an RPC endpoint. See bookface-rpc DESIGN.md §5.
module ProfileReconciliation
  module_function

  def enqueue(user_sub)
    if local?
      # Run inline locally: no SQS, and it keeps the local loop honest about
      # what the user will actually see after saving a profile.
      perform(user_sub)
    else
      raise NotImplementedError, "SQS enqueue not wired in the skeleton"
    end
  end

  # Rewrite the author snapshot everywhere this user has written. Both GSIs are
  # keys-only, so this reads ids then updates — no Scan.
  def perform(user_sub)
    profile = Profile.for(user_sub)
    name    = profile.shown_name
    avatar  = profile.avatar_key

    Post.where(author_sub: user_sub).each do |stub|
      post = Post.find(stub.id, raise_error: false) or next
      post.update_attributes(author_name: name, author_avatar: avatar)
    end

    Comment.where(author_sub: user_sub).each do |stub|
      comment = Comment.find(stub.post_id, range_key: stub.path, raise_error: false) or next
      comment.update_attributes(author_name: name, author_avatar: avatar)
    end
  end

  def local? = ENV.fetch("BOOKFACE_ENV", "local") == "local"
end
