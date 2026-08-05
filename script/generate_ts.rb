# frozen_string_literal: true
#
# Generates the TypeScript client from the manifest, using Foobara's own
# generator, and then patches three things in its output that do not work.
#
#   script/dev.sh serve                     # then
#   bundle exec ruby script/generate_ts.rb
#
# It reads the manifest over HTTP from the RUNNING connector rather than from
# this process. Two reasons, both learned the hard way:
#
#   * `Foobara.manifest` lacks the fields the generator needs. `serializers` and
#     `requires_authentication` are connector-level, so they exist only once
#     commands are connected; without them the generator dies with "undefined
#     local variable or method `serializers`", which names nothing useful.
#   * It must be the manifest of the process the client will actually talk to.
#     Pointing this at a different one is how the SDK silently regenerated
#     against stale types.
#
# (`raw_manifest:` is not an alternative: `Foobara.manifest` has symbol VALUES
# and fails with "Not sure how to convert :string to a TS type", while
# `JSON.parse` of it has string keys and fails on `serializers`. Only
# `symbolize_names: true` produces the shape it wants — which is what
# `manifest_url:` does internally anyway.)

require "foobara/typescript_remote_command_generator"

ROOT = File.expand_path("..", __dir__)
GENERATED = File.join(ROOT, "web/src/domains")
MANIFEST_URL = ENV.fetch("BOOKFACE_MANIFEST", "http://localhost:9292/manifest")

# Applies one patch and REFUSES TO CONTINUE if it did not apply.
#
# This matters more than it looks. Every patch below matches exact generated
# source, and `sub` returns the string unchanged when it does not match — so a
# whitespace change upstream would leave the file untouched while this script
# reported success. One of these patches works around a bug that `tsc` cannot
# see and that only appears in a browser, so a silent no-op here is a green
# build and a broken app.
def patch!(path, description, skip_if:)
  source = File.read(path)
  return puts("  already patched: #{description}") if source.include?(skip_if)

  patched = yield(source)

  if patched == source
    abort "FAILED to patch #{description} in #{path.delete_prefix("#{ROOT}/")}: " \
          "the generated source no longer matches what this patch expects. " \
          "Read the generated file and update script/generate_ts.rb."
  end

  File.write(path, patched)
  puts "  patched: #{description}"
end

outcome = Foobara::RemoteGenerator::WriteTypescriptToDisk.run(
  manifest_url: MANIFEST_URL,
  # Relative to the CWD, not to project_directory.
  output_directory: GENERATED
)

abort "FAILED: #{outcome.errors_hash}" unless outcome.success?

puts "generated #{outcome.result.inspect}"

# --- patch 1 -----------------------------------------------------------------
# RequiresAuthCommand is emitted for every command declaring
# requires_authentication, and imports ./utils/accessTokens and ./RefreshLogin —
# neither of which the generator emits unless the app uses Foobara::Auth. Any
# other auth scheme gets an SDK that does not compile.
#
# Replaced with a pass-through. This app sends a bearer token, which patch 3
# attaches on the base class instead.
AUTH_STUB = <<~TS
  import RemoteCommand from '../../base/RemoteCommand'
  import { type FoobaraError } from '../../base/Error'

  // Replaced after generation — see script/generate_ts.rb. The generated version
  // assumes Foobara's own Auth domain, whose helpers are not generated for an
  // app that does not use it.
  export default class RequiresAuthCommand<Inputs, Result, Error extends FoobaraError<any>>
    extends RemoteCommand<Inputs, Result, Error> {
  }
TS

auth_path = File.join(GENERATED, "Foobara/Auth/RequiresAuthCommand.ts")
if File.exist?(auth_path)
  patch!(auth_path, "RequiresAuthCommand (no Foobara::Auth here)",
         skip_if: "Replaced after generation") { |_source| AUTH_STUB }
end

# --- patch 2 -----------------------------------------------------------------
# RemoteCommand#_handleResponse calls this.dirtyQueries() on every success, but
# the generator only emits that method for apps that declare queries. With none
# declared, EVERY successful command raises "TypeError: this.dirtyQueries is not
# a function".
#
# The one that most needs the assertion above: it is not a type error, so tsc is
# clean and it only surfaces in a browser.
remote_path = File.join(GENERATED, "base/RemoteCommand.ts")

patch!(remote_path, "RemoteCommand#dirtyQueries (no-op)", skip_if: "dirtyQueries (") do |source|
  source.sub(
    /^(\s*)outcome: null \| Outcome<Result, CommandError>$/,
    "\\1outcome: null | Outcome<Result, CommandError>\n" \
    "\n\\1// Added after generation — see script/generate_ts.rb. The generated\n" \
    "\\1// class calls this on success but only defines it when the app\n" \
    "\\1// declares queries.\n" \
    "\\1dirtyQueries (): void {}\n"
  )
end

# --- patch 3 -----------------------------------------------------------------
# The SDK has no hook for an Authorization header, because upstream assumes
# Foobara::Auth's RequiresAuthCommand supplies one — the same assumption behind
# patch 1.
#
# It goes on the BASE class, not on RequiresAuthCommand: the commands that are
# public but viewer-aware (ListPosts marking your own posts editable,
# MyReactions) extend RemoteCommand directly and need the token too, or a
# signed-in caller looks anonymous to them.
#
# _issueRequest rather than _buildRequestParams because the provider is async: it
# may have to refresh an expired token before the request goes out.
patch!(remote_path, "RemoteCommand._issueRequest (bearer token hook)", skip_if: "authTokenProvider") do |source|
  source.sub(
    "  async _issueRequest (): Promise<Response> {\n" \
    "    return await fetch(this._buildUrl(), this._buildRequestParams())\n" \
    "  }",
    "  // Added after generation — see script/generate_ts.rb.\n" \
    "  static authTokenProvider: (() => Promise<string | null>) | null = null\n" \
    "\n" \
    "  async _issueRequest (): Promise<Response> {\n" \
    "    const params = this._buildRequestParams()\n" \
    "    const token = await RemoteCommand.authTokenProvider?.()\n" \
    "    if (token != null) {\n" \
    "      (params.headers as Record<string, string>).Authorization = `Bearer ${token}`\n" \
    "    }\n" \
    "    return await fetch(this._buildUrl(), params)\n" \
    "  }"
  )
end
