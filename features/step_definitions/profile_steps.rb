# frozen_string_literal: true

When("I open my profile") do
  visit "/"
  click_button "My profile"
  expect(page).to have_css("[data-testid=profile]")
end

When("I set my display name to {string} and bio {string}") do |name, bio|
  step "I open my profile"
  fill_in "Display name", with: name
  fill_in "Bio", with: bio
  click_button "Save profile"
  expect(page).to have_content("Profile saved.")
end

When("I set my avatar to an image I uploaded") do
  step "I open my profile"
  attach_file "Profile photo", File.expand_path("../support/fixtures/sample.jpg", __dir__)
  click_button "Save profile"
  expect(page).to have_content("Profile saved.")
end

# The server only honours an avatar key under the caller's own upload prefix.
# A key from anywhere else is ignored rather than trusted — there is no UI for
# this, because the UI cannot produce such a key; it is a server rule, so the
# step exercises the procedure directly.
When("I try to set my avatar to someone else's key") do
  @response = run_command(
    "Profiles/UpdateProfile",
    { "display_name" => @me, "bio" => "", "avatar_key" => "u/dev|grace/not-mine.jpg" }
  )
end

Then("my profile shows my photo") do
  step "I open my profile"
  expect(page).to have_css("[data-testid=profile-avatar]")
end

Then("my profile has no photo") do
  expect(Profile.for(persona_sub(@me)).avatar_key).to be_nil
end

Given("I have saved my profile") do
  # Stamps profile.name from the current claim, which is what a later post must
  # agree with.
  status, = run_command("Profiles/UpdateProfile", {})
  expect(status).to eq(200)
end

When("my identity claim starts saying {string}") do |name|
  @claim_name = name
end

When("I post {string} through the API") do |body|
  status, = run_command("Posts/CreatePost", { "body" => body }, name: @claim_name)
  expect(status).to eq(200)
end

Then("the post {string} is attributed to {string}") do |body, expected|
  expect(find_post(body).author_name).to eq(expected)
end
