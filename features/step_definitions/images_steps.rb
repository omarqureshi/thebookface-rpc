# frozen_string_literal: true

# The presign contract, exercised through the procedure rather than the browser:
# the scenario is about what the server hands back, not about the file picker.

When("I request an upload for {string}") do |content_type|
  _, @presigned = run_command("Uploads/Presign", { "content_type" => content_type })
end

Then("I receive a presigned upload target") do
  expect(@presigned).to include("url", "fields", "key")
  # Scoped to the caller's own prefix — this is what makes trusting a
  # client-supplied key safe later.
  expect(@presigned["key"]).to start_with("u/#{persona_sub(@me)}/")
end

Then("I should see the attached image") do
  expect(page).to have_css("[data-testid=post] img")
end

Then("the attached image loads") do
  src = find("[data-testid=post] img")["src"]
  response = Net::HTTP.get_response(URI(src))
  expect(response.code).to eq("200")
end
