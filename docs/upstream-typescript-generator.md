# Upstream report: foobara-typescript-remote-command-generator 1.4.0

Three defects found by generating a client for an app that uses
`requires_authentication` but not `Foobara::Auth`, and declares no queries. All
three are worked around in `script/generate_ts.rb`; the workarounds are patches
applied after generation, which is not where they belong.

Line numbers are from the 1.4.0 gem as published.

---

## 1. `this.dirtyQueries()` is called unconditionally but defined conditionally

**Severity:** high — every successful command fails, and `tsc` cannot see it.

`templates/base/RemoteCommand.ts.erb`:

```erb
124:      this.dirtyQueries()          # not guarded

  3:  <% if auto_dirty_queries? %>    # guards elsewhere in the file
111:  <% if auto_dirty_queries? %>
136:  <% if auto_dirty_queries? %>    # ...including the one defining it
137:    dirtyQueries () {
```

The call at 124 sits in `_handleResponse`'s success branch. The definition at 137
is behind `auto_dirty_queries?`. With that off — an app declaring no queries —
the generated client throws on **every successful command**:

```
TypeError: this.dirtyQueries is not a function
```

It is a runtime error rather than a type error, so `tsc --noEmit` is clean and it
appears only in a browser.

**Reproduction:** generate against any manifest with `auto_dirty_queries` off and
run any command successfully.

**Suggested fix:** guard the call the same way as the definition.

```erb
      this.commandState = 'succeeded'
<% if auto_dirty_queries? %>
      this.dirtyQueries()
<% end %>
```

Defining a no-op in the `else` branch would work too, and keeps the method
present for anyone overriding it.

---

## 2. `RequiresAuthCommand` imports files the generator did not generate

**Severity:** high — the SDK does not compile.

`src/generators/typescript_from_manifest_base_generator.rb:41`:

```ruby
if manifest.requires_authentication?
  Auth::RequiresAuthGenerator
else
  CommandGenerator
end
```

`RequiresAuthGenerator` depends on `Foobara/Auth/RequiresAuthCommand`, and
`templates/Foobara/Auth/RequiresAuthCommand.ts.erb` begins:

```ts
import { tokenForUrl } from './utils/accessTokens'
import { RefreshLogin } from './RefreshLogin'
```

Those two come from `Auth::AccessTokensGenerator` and
`Auth::RefreshLoginGenerator`, which are only selected for
`Foobara::Auth::Login` and `/\bGetCurrentUser$/`. So an app that declares
`requires_authentication` **without** using `Foobara::Auth` gets a
`RequiresAuthCommand.ts` importing two modules that were never written:

```
src/domains/Foobara/Auth/ contains only RequiresAuthCommand.ts
```

The generated project does not typecheck, let alone run.

**Reproduction:** connect one command with `requires_authentication: true` in an
app with no `Foobara::Auth` commands, and generate.

**Root cause, as I read it:** `requires_authentication?` is being treated as
"this app uses Foobara::Auth". They are different questions — authentication is
a property of the connection, and the token scheme is a separate choice. This
app authenticates with a Cognito bearer token, and earlier with a cookie.

**Suggested fix**, in preference order:

1. Select `Auth::RequiresAuthGenerator` only when the manifest actually contains
   `Foobara::Auth`, and fall back to `CommandGenerator` otherwise. A command
   requiring authentication needs no special base class if the app supplies
   credentials another way.
2. Or emit the token machinery whenever `RequiresAuthCommand` is emitted, so its
   imports always resolve.
3. Or make the imports conditional in the template, leaving a pass-through
   `RequiresAuthCommand` when the auth domain is absent — which is exactly the
   patch this repo applies by hand.

---

## 3. No hook for an `Authorization` header

**Severity:** medium — a missing feature, but it follows from the same assumption
as (2).

`RemoteCommand#_buildRequestParams` sets `credentials: 'include'` and a
`Content-Type`, and nothing else. There is no documented way to attach a header,
because the assumption is that `RequiresAuthCommand` handles credentials.

An app using bearer tokens therefore has to patch the base class. It must be the
**base** class, not `RequiresAuthCommand`: commands that are public *and*
viewer-aware — a feed marking your own posts editable, a "my reactions"
endpoint — extend `RemoteCommand` directly, and without the token a signed-in
caller looks anonymous to them.

**Suggested fix:** a static hook on `RemoteCommand`, applied in `_issueRequest`
rather than `_buildRequestParams` so it can be async (refreshing an expired
token before the request goes out):

```ts
static authTokenProvider: (() => Promise<string | null>) | null = null

async _issueRequest (): Promise<Response> {
  const params = this._buildRequestParams()
  const token = await RemoteCommand.authTokenProvider?.()
  if (token != null) {
    (params.headers as Record<string, string>).Authorization = `Bearer ${token}`
  }
  return await fetch(this._buildUrl(), params)
}
```

A more general `headersProvider` would serve API keys and tracing headers too.

---

## Two sharp edges, probably documentation

- **`raw_manifest:` and `manifest_url:` are not interchangeable.**
  `Foobara.manifest` has symbol *values* and fails with "Not sure how to convert
  :string to a TS type". `JSON.parse` of it has string keys and fails with
  "undefined local variable or method `serializers`". Only
  `JSON.parse(..., symbolize_names: true)` works — and only against a manifest a
  *connector* served, since `serializers` and `requires_authentication` are
  connector-level and absent from `Foobara.manifest`. Neither error names the
  real problem.

- **`output_directory` is relative to the working directory**, not to
  `project_directory`.

## Separately: `associative_array` has no TypeScript mapping

"Not sure how to convert associative_array to a TS type". Foobara's own type
system handles it; the generator does not. This app models emoji⇒count maps and
presigned form fields as lists of pairs to avoid it, which is a worse API than
the domain deserves.
