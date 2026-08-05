# frozen_string_literal: true

# HOW the author snapshot is rewritten. WHAT is being asked for lives in
# Profiles::ReconcileAuthorSnapshot, which is a command; this is the storage
# work it does, kept here because it is about Dynamoid and GSIs rather than
# about the domain.
module ProfileReconciliation
  module_function

  # Rewrite the author snapshot everywhere this user has written. Both GSIs are
  # keys-only, so this reads ids then updates — no Scan.
  # Returns how many records were rewritten. Not decoration: the command that
  # wraps this declares an integer result, so Foobara refuses the outcome if this
  # returns nil — which it did, and which is how the missing count was noticed.
  def perform(user_sub)
    profile = Profile.for(user_sub)
    name    = profile.shown_name
    avatar  = profile.avatar_key
    rewritten = 0

    Post.where(author_sub: user_sub).each do |stub|
      post = Post.find(stub.id, raise_error: false) or next
      post.update_attributes(author_name: name, author_avatar: avatar)
      rewritten += 1
    end

    Comment.where(author_sub: user_sub).each do |stub|
      comment = Comment.find(stub.post_id, range_key: stub.path, raise_error: false) or next
      comment.update_attributes(author_name: name, author_avatar: avatar)
      rewritten += 1
    end

    rewritten
  end

  def local? = ENV.fetch("BOOKFACE_ENV", "local") == "local"
end
