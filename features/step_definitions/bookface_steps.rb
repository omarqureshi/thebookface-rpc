# frozen_string_literal: true

# Steps rewritten for the SPA. The Gherkin is unchanged from the Rails suite —
# it described user behaviour, not Rails — but every step that touched a Rails
# route or a server-rendered form had to be redone against the React UI.
#
# Seeding steps ported unchanged: the Dynamoid models came across intact.

# --- personas --------------------------------------------------------------
# Must match PERSONAS in web/src/App.tsx.
PERSONAS = { "Ada Lovelace" => "dev|ada", "Grace Hopper" => "dev|grace" }.freeze

def persona_sub(name)
  PERSONAS.fetch(name) { raise "unknown persona #{name.inspect}" }
end

# --- finders ---------------------------------------------------------------

def find_post(body)
  Post.recent.find { |p| p.body == body } or raise "no post saying #{body.inspect}"
end

def find_comment(post, body)
  Comment.thread_for(post.id).find { |c| c.body == body } or raise "no comment #{body.inspect}"
end

# The card on screen containing this text. Everything scopes through here, so a
# step can never accidentally act on a different post's controls.
def post_card(body)
  find("[data-testid=post]", text: body)
end

def comment_card(body)
  find("[data-testid=comment]", text: body)
end

def fixture_image = File.expand_path("../support/fixtures/sample.jpg", __dir__)

# --- auth ------------------------------------------------------------------

Given("I am signed in as {string}") do |name|
  @me = name
  visit "/"
  click_button name # the persona button in the header
  expect(page).to have_css("[data-testid=signed-in]", text: name)
end

# --- seeding ---------------------------------------------------------------
# `seed|X` deliberately does NOT match any persona sub, so seeded content is
# owned by someone else — which is what the permission scenarios rely on.

Given("a post by {string} saying {string}") do |author, body|
  Post.create!(body: body, author_sub: "seed|#{author}", author_name: author)
end

Given("the post {string} has a comment {string} by {string}") do |post_body, text, author|
  post = find_post(post_body)
  Comment.create!(post_id: post.id, body: text, author_sub: "seed|#{author}", author_name: author)
end

Given("the comment {string} has a reply {string} by {string}") do |parent_body, text, author|
  post = Post.recent.first
  parent = find_comment(post, parent_body)
  Comment.create!(post_id: post.id, parent_path: parent.path, body: text,
                  author_sub: "seed|#{author}", author_name: author)
end

Given("I have posted {string}") do |body|
  Post.create!(body: body, author_sub: persona_sub(@me), author_name: @me)
end

Given("I have commented {string} on the post {string}") do |text, post_body|
  post = find_post(post_body)
  Comment.create!(post_id: post.id, body: text,
                  author_sub: persona_sub(@me), author_name: @me)
end

Given("I have posted {string} with a stored image") do |body|
  key = "u/#{persona_sub(@me)}/seeded.jpg"
  FileUtils.mkdir_p(MediaStorage.local_dir)
  FileUtils.cp(fixture_image, MediaStorage.path_for(key))
  @stored_key = key
  Post.create!(body: body, author_sub: persona_sub(@me), author_name: @me,
               media: [{ "key" => key, "content_type" => "image/jpeg" }])
end

# --- navigation ------------------------------------------------------------

When("I open the feed") do
  visit "/"
end

When("I open the post {string}") do |body|
  visit "/" unless page.has_css?("[data-testid=post]", text: body, wait: 0)
  within(post_card(body)) { find("[data-testid=open-comments]").click }
  expect(page).to have_content(body)
end

# --- posting ---------------------------------------------------------------

When("I write a post {string}") do |body|
  fill_in "What's on your mind?", with: body
end

When("I attach an image to my post") do
  attach_file "Attach an image", fixture_image
  # The upload is a real round trip (presign, then POST to the store), so wait
  # for it to land before submitting.
  expect(page).to have_css("[data-testid=attached-count]")
end

When("I attach the fixture image") do
  attach_file "Attach an image", fixture_image
  expect(page).to have_css("[data-testid=attached-count]")
end

When("I submit the post") do
  within("[data-testid=composer]") { click_button "Post" }
end

# --- comments --------------------------------------------------------------

When("I comment {string}") do |text|
  fill_in "Add a comment", with: text
  click_button "Comment"
  expect(page).to have_content(text)
end

When("I reply {string} to the comment {string}") do |text, parent|
  within(comment_card(parent)) do
    click_button "Reply"                       # opens the reply box
    find("[data-testid=reply-box]").set(text)
    find("[data-testid=submit-reply]").click
  end
  expect(page).to have_content(text)
end

# --- assertions ------------------------------------------------------------

Then("I should see {string}") do |text|
  expect(page).to have_content(text)
end

Then("I should not see {string}") do |text|
  expect(page).to have_no_content(text)
end

# Depth is rendered as a data attribute rather than inferred from indentation,
# so the assertion is about the thread's structure and not about CSS.
Then("the comment {string} should be nested at depth {int}") do |text, depth|
  expect(comment_card(text)["data-depth"]).to eq(depth.to_s)
end

Then("the comment {string} is still there") do |text|
  expect(page).to have_content(text)
end
