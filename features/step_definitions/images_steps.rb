# frozen_string_literal: true

require "stringio"

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

# The presigned target is the dev object store locally, so these post to it the
# same way the browser would — the point being that storing is what triggers
# verification, not some separate call the suite makes.
def upload_to_presigned(bytes)
  uri = URI(@presigned.fetch("url"))
  fields = @presigned.fetch("fields").map { |f| [f.fetch("name"), f.fetch("value")] }

  request = Net::HTTP::Post.new(uri)
  # A real file part, with a filename — not a plain string field. Rack only
  # yields a tempfile for the former, and the dev object store reads the bytes
  # from that. Without it the upload silently stores nothing.
  request.set_form(
    fields + [["file", StringIO.new(bytes), { filename: "upload.bin", content_type: "application/octet-stream" }]],
    "multipart/form-data"
  )
  response = Net::HTTP.start(uri.hostname, uri.port) { |http| http.request(request) }

  # Asserted, because a failed upload would leave nothing stored and make the
  # "it was deleted" scenario pass for the wrong reason.
  expect(response.code).to eq("204")
  response
end

def presigned_object_response
  # Escaped: a persona sub contains "|", which URI() rejects outright. The
  # browser percent-encodes it for the same reason, and the dev store unescapes.
  key = URI::DEFAULT_PARSER.escape(@presigned.fetch("key"))
  Net::HTTP.get_response(URI("#{@presigned.fetch("url")}/#{key}"))
end

When("I upload bytes that are not an image") do
  # A ZIP, which is what a disguised payload usually is. The declared content
  # type still says image/png.
  upload_to_presigned("PK\x03\x04not really an image at all")
end

When("I upload a real PNG") do
  # An 8-byte PNG signature is enough: verification sniffs the magic bytes, it
  # does not decode the image.
  upload_to_presigned("\x89PNG\r\n\x1A\n".b + ("\x00" * 32))
end

Then("the uploaded object is gone") do
  expect(presigned_object_response.code).to eq("404")
end

Then("the uploaded object is still there") do
  expect(presigned_object_response.code).to eq("200")
end
