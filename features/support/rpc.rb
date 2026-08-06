# frozen_string_literal: true

# Calling a command the way a hostile client would.
#
# A few scenarios are about server rules that no UI can express — forging an
# edit of someone else's post, claiming an avatar key from another user's
# prefix. On the Prospect branch these went through Prospect::Dispatcher
# in-process. Here they go over HTTP to the running connector, which is closer
# to the thing being asserted: it exercises the authenticator and the error
# serializer too, not just the command.

require "net/http"
require "json"

# Returns [status, parsed_body]. Identity travels as X-Dev-* headers, the same
# pair config.ru's authenticator reads (the browser uses a cookie instead, only
# because the generated SDK offers no header hook).
# +name+ overrides the claimed display name while keeping the same sub, which
# is how a scenario can act as one user whose identity claim has changed.
def run_command(path, input, as: nil, name: nil)
  who = as || @me
  uri = URI("#{API_HOST}/run/#{path}")

  request = Net::HTTP::Post.new(uri)
  request["Content-Type"] = "application/json"
  if who
    request["X-Dev-Sub"] = persona_sub(who)
    request["X-Dev-Name"] = name || who
  end
  request.body = JSON.dump(input)

  response = Net::HTTP.start(uri.hostname, uri.port) { |http| http.request(request) }
  body = begin
    JSON.parse(response.body)
  rescue JSON::ParserError
    response.body
  end

  [response.code.to_i, body]
end

# Foobara serializes a command's declared runtime errors as a LIST of error
# objects, keyed by `symbol` — and answers 422 for all of them, where Prospect
# chose a status per error code (403 for forbidden, 404 for not_found). The
# symbol is the stable part, so that is what these steps assert.
def error_symbols(body)
  return [] unless body.is_a?(Array)

  body.map { |e| e["symbol"] }
end
