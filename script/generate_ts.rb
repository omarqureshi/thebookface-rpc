# frozen_string_literal: true
#
# Foobara's own TypeScript SDK generator — the counterpart to `prospect emit ts`.
#
#   bundle exec ruby script/generate_ts.rb
#
# The manifest is captured BEFORE the generator is required. Loading it
# registers its own commands, one of which declares `possible_error
# :missing_manifest` with no context type — and a context-less error breaks
# Foobara.manifest for the whole process. Worth reporting upstream.
# Deliberately does NOT boot the app: the generator needs the CONNECTOR's
# manifest, not Foobara.manifest. Connector-level data — `serializers`,
# `requires_authentication` — only exists once commands are connected, and the
# generator fails on its absence with "undefined local variable or method
# 'serializers'".
#
#   script/dev.sh serve    # then
#   bundle exec ruby script/generate_ts.rb

# Round-tripped through JSON with symbolized KEYS, which is the shape the
# generator expects and what it would get from manifest_url:
#
#   Foobara.manifest        symbol keys, SYMBOL values -> "Not sure how to
#                           convert :string to a TS type"
#   JSON.parse(...)         string keys, string values -> "undefined local
#                           variable or method 'serializers'"
#   symbolize_names: true   symbol keys, string values -> works
#
# Worth reporting: raw_manifest: and manifest_url: are not interchangeable, and
# neither failure names the real problem.
require "foobara/typescript_remote_command_generator"

# The dev server on :9292 serves /manifest itself, so generation reads the
# manifest of the very process it will be talking to. Pointing this at a
# separate process is how the SDK silently regenerated against stale types.
MANIFEST_URL = ENV.fetch("BOOKFACE_MANIFEST", "http://localhost:9292/manifest")

outcome = Foobara::RemoteGenerator::WriteTypescriptToDisk.run(
  manifest_url: MANIFEST_URL,
  # output_directory is relative to the CWD, not project_directory.
  output_directory: File.expand_path("../web/src/domains", __dir__)
)

# POST-GENERATION PATCH, and a finding worth reporting.
#
# The generator emits RequiresAuthCommand for every command declaring
# requires_authentication, and that file hard-imports ./utils/accessTokens and
# ./RefreshLogin — which only exist if the app uses Foobara's own Auth domain.
# bookface authenticates with a cookie, so the generated SDK does not compile
# out of the box.
#
# Replaced with a pass-through: RemoteCommand already sends
# credentials: "include", which is all cookie auth needs.
AUTH_STUB = <<~TS
  import RemoteCommand from '../../base/RemoteCommand'
  import { type FoobaraError } from '../../base/Error'

  // Replaced after generation — see script/generate_ts.rb. The generated
  // version assumes Foobara's bearer-token Auth domain; this app uses a cookie,
  // and RemoteCommand already sends credentials: "include".
  export default class RequiresAuthCommand<Inputs, Result, Error extends FoobaraError<any>>
    extends RemoteCommand<Inputs, Result, Error> {
  }
TS

if outcome.success?
  stub_path = File.expand_path("../web/src/domains/Foobara/Auth/RequiresAuthCommand.ts", __dir__)
  if File.exist?(stub_path)
    File.write(stub_path, AUTH_STUB)
    puts "patched RequiresAuthCommand (cookie auth, not bearer)"
  end

  # Second patch, second finding. RemoteCommand#_handleResponse calls
  # this.dirtyQueries() on every success, but the generator only emits that
  # method for apps that declare queries — so with none declared, every
  # successful command raises a TypeError at runtime. A no-op restores it.
  remote_path = File.expand_path("../web/src/domains/base/RemoteCommand.ts", __dir__)
  remote = File.read(remote_path)
  unless remote.include?("dirtyQueries (")
    remote = remote.sub(
      /^(\s*)outcome: null \| Outcome<Result, CommandError>$/,
      "\\1outcome: null | Outcome<Result, CommandError>\n" \
      "\n\\1// Added after generation — see script/generate_ts.rb. The generated\n" \
      "\\1// class calls this on success but only defines it when the app\n" \
      "\\1// declares queries.\n" \
      "\\1dirtyQueries (): void {}\n"
    )
    File.write(remote_path, remote)
    puts "patched RemoteCommand#dirtyQueries (no-op)"
  end

  puts "generated #{outcome.result.inspect}"
else
  puts "FAILED: #{outcome.errors_hash}"
end
