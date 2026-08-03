# frozen_string_literal: true

# Editing and deleting. The Rails suite drove edit forms at their own URLs;
# here the controls are inline on the card, so every step scopes to the card
# rather than navigating.

# Clicking Edit changes the route (/posts/:id/edit), so React replaces the card
# and any element held across that click goes stale. The form is also not
# findable by body text any more — the body moves into a textarea, and Capybara's
# `text` does not see field values.
#
# Only one post can be in edit mode, because the URL says which, so the fields
# are unambiguous page-wide.
When("I edit the post {string} to say {string}") do |old_body, new_body|
  visit "/" unless page.has_css?("[data-testid=post]", text: old_body, wait: 0)
  post_card(old_body).click_button "Edit"
  fill_in "Edit post", with: new_body
  click_button "Save"
  expect(page).to have_content(new_body)
end

When("I delete the post {string}") do |body|
  visit "/" unless page.has_css?("[data-testid=post]", text: body, wait: 0)
  within(post_card(body)) { click_button "Delete" }
  expect(page).to have_no_content(body)
end

When("I edit the comment {string} to say {string}") do |old_text, new_text|
  within(comment_card(old_text)) do
    click_button "Edit"
    fill_in "Edit comment", with: new_text
    click_button "Save"
  end
  expect(page).to have_content(new_text)
end

When("I delete the comment {string}") do |text|
  within(comment_card(text)) { click_button "Delete" }
end

# --- attempts that must be refused ----------------------------------------
#
# There is no UI for these: the client never renders Edit or Delete on content
# you do not own. That makes "trying" a question about the SERVER, so these
# steps forge the call the way a hostile client would and assert the refusal.
# Asserting only that a button is missing would test the UI's manners rather
# than the security boundary.
#
# The card is re-found in each assertion rather than held across steps: React
# re-renders between them, and a stored Element goes stale.

def forge(procedure, input)
  ctx = Bookface::Context.new(
    viewer: Bookface::Viewer.new(sub: persona_sub(@me), email: nil, name: @me)
  )
  Prospect::Dispatcher.new(Bookface::AppRouter).call(procedure, input, ctx)
end

When("I try to edit the post {string}") do |body|
  post = find_post(body)
  @status, @body = forge("posts.update", { "id" => post.id, "body" => "hijacked" })
  @attempted = [:post, body]
end

When("I try to delete the comment {string}") do |text|
  post = Post.recent.first
  comment = find_comment(post, text)
  @status, @body = forge("comments.destroy",
                         { "post_id" => post.id, "path" => comment.path })
  @attempted = [:comment, text]
  # Show the thread, so "still there" is about what a person actually sees.
  visit "/"
  within(post_card(post.body)) { find("[data-testid=open-comments]").click }
end

Then("I should not see any edit or delete control") do
  kind, text = @attempted
  card = kind == :post ? post_card(text) : comment_card(text)
  expect(card).to have_no_button("Edit")
  expect(card).to have_no_button("Delete")
end

Then("I am told I can only change my own content") do
  expect(@status).to eq(403)
  expect(@body.dig("error", "code")).to eq("forbidden")
end

# --- consequences ----------------------------------------------------------

Then("that post's thread is gone") do
  expect(Comment.count).to eq(0)
  expect(Reaction.count).to eq(0)
end

Then("the stored image should be gone") do
  expect(File).not_to exist(MediaStorage.path_for(@stored_key))
end
