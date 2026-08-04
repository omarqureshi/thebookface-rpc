# Foobara on AWS Lambda

What building and deploying this app found. It is a small social app — posts,
comments, reactions, profiles, image uploads — written as Foobara commands and
deployed as one Lambda per domain, with the whole deployment derived from the
manifest.

Everything below was measured against the running system rather than reasoned
about. Versions: `foobara` 0.5.10, `foobara-rack-connector` 0.1.3,
`foobara-typescript-remote-command-generator` 1.4.0, `dynamoid` 3.14.0, Ruby
4.0.5.

**The headline: the manifest is a good deployment IR, and the one real gap is in
Foobara's model rather than its tooling — a command cannot learn who is calling
unless it also requires authentication.**

## What runs

Five domains, 14 commands, served by the Rack connector locally and packaged
into five Lambda artifacts plus an authorizer:

```
comments   /run/Comments/{proxy+}    4 commands   public 1
posts      /run/Posts/{proxy+}       5 commands   public 2
profiles   /run/Profiles/{proxy+}    2 commands   public 0
reactions  /run/Reactions/{proxy+}   2 commands   public 1
uploads    /run/Uploads/{proxy+}     1 command    public 0
authorizer                           0 commands
```

Each artifact serves its own domain and 404s every other, because a unit
registers only its own commands — there is nothing to refuse. Measured in the
built `posts` artifact, in the runtime image:

```
own public, anonymous       200
own gated, anonymous        401
own gated, signed in        200
foreign domain (Comments)   404
```

And deployed, through CloudFront at `staging.thebookface.net`. The refusals are
403 rather than 401 here because the API Gateway authorizer denies the request
before it reaches a function at all — in the artifact above there is no
authorizer, so the connector itself answers 401:

```
public command, anonymous            200
gated, no token                      403
gated, forged X-Dev-Sub header       403
gated, invalid token                 403 application/json
public command, invalid token        200   (treated as anonymous)
```

That last row is the behaviour the whole optional-auth design exists for: a
caller whose session expired still sees public data and gains nothing by it.

The public/gated split is **derived from the manifest** — `requires_authentication`,
one field per command — so no list of public commands is maintained anywhere.

## The manifest as a deployment IR

| deployment needs | manifest field |
| --- | --- |
| unit identity and grouping | `domain`, `organization` — two levels, not one |
| the route | `scoped_full_path` |
| which commands are public | `requires_authentication` |
| what a per-command unit must contain | `depends_on` |
| client generation | `inputs_type`, `result_type`, `possible_errors` |

Two of these are unusual and worth calling out.

**`requires_authentication` makes the public list derivable.** A hand-maintained
list of anonymous endpoints in an infrastructure file can silently drift from
what the application enforces; here the two cannot differ, because there is only
one declaration.

Note it is `requires_authentication`, not `authenticator`. The manifest has both,
and `authenticator` answers a different question — *which* authenticator applies
(`{"symbol" => "authenticator", "explanation" => "authenticator"}`) — and is
absent entirely when identity arrives another way. Reading it instead produces a
plausible-looking public list that is wrong.

**`depends_on` solves per-command slicing.** Deploying one Lambda per command
requires knowing what else that command needs in the artifact, which cannot be
inferred soundly from Ruby's require graph. Foobara does not infer it; commands
declare it. `foobara-aws` closes each per-command unit over `depends_on`
transitively, and a dependency cycle terminates rather than recursing.

**Two grouping levels, not one.** Most frameworks give a single axis; `domain`
and `organization` give a choice of deployment granularity for free. One caveat
found by using it: the route must be derived from the commands' own
`scoped_full_path`, not from the group's name. An app declaring no organization
is filed under `global_organization`, which appears in no URL — routing by that
name matches nothing.

## What Foobara does well

- **It validates results, not just inputs.** It rejected an explicit `nil` for an
  optional attribute in a command's output — a class of bug that otherwise
  reaches the client.
- **Validation errors are derived from types.** `possible_errors` includes
  entries like `data.body.cannot_cast` automatically, so a generated client's
  error union is complete without anyone maintaining it.
- **Types are one system.** No parallel "wire type" that skips validation, and no
  coercion scattered through presenters.
- **A unit is a subset by construction.** `connect(Posts)` registers exactly that
  domain; the others are not refused, they were never registered.

## The one gap in the model: optional identity

Foobara authenticates only commands declaring `requires_authentication`. That
answers *may this caller in?* but never *who is this caller?* — and those are
different questions.

This app has four commands that are public **and** viewer-aware:
`Posts::ListPosts` and `Posts::GetPost` mark your own posts editable,
`Reactions::MyReactions` returns your own reactions. They must be readable signed
out and must know the caller when signed in. Foobara has nowhere to put that.

A result transformer was suggested as a way in. It does not work, for two
independent reasons:

1. **No request handle.** `transform_result` resolves `self.class.result_transformer`
   and calls `process_value!(result)`. The transformer is class-level and
   receives only the result value.
2. **Nothing to see even with one.** `authenticated_user` is nil for a public
   command, whatever asks.

The second is the real finding. `Request#authenticate`:

```ruby
def authenticate
  return if error
  return unless command_class.respond_to?(:requires_authentication) && command_class.requires_authentication

  authenticated_user, authenticated_credential = authenticator.authenticate(self)
  self.authenticated_user = authenticated_user
  ...
  self.error = UnauthenticatedError.new unless authenticated_user
end
```

One guard skips **both** things this method does — running the authenticator and
enforcing it. `CommandConnector#run_request` reinforces it a layer up, attaching
an authenticator to the request only when `requires_authentication` is true. So
authentication is conditional on the gate, and identity is unavailable to every
hook rather than to any particular one.

**Splitting the guard is about four lines:**

```ruby
def authenticate
  return if error
  return unless authenticator            # RUN whenever there is one

  self.authenticated_user, self.authenticated_credential = authenticator.authenticate(self)

  return unless command_class.requires_authentication   # ENFORCE only when asked
  self.error = UnauthenticatedError.new unless authenticated_user
end
```

plus attaching the authenticator unconditionally in `run_request`. Verified by
monkey-patching exactly that against this app:

```
public command, as shipped         authenticated_user=nil
public command, with the change    authenticated_user=#<struct sub="google|1", name="Ada">
```

It is backward compatible: a gated command behaves identically, and a public
command's `authenticated_user` goes from always-nil to populated, which nothing
can be relying on.

**It also unblocks the idiomatic answer rather than a workaround.** The ordering
in `run_request` is already right — `request.authenticate` then
`request.mutate_request` — so a request mutator injecting the caller as an input,
the way `SetRefreshTokenFromCookie` injects a token, would work for public
commands too. Today it cannot, only because of that guard.

Until then this app uses a thread-local (`Foobara::AWS.current_caller`), set from
the authorizer's verified claims in Lambda and from Rack middleware locally. It
works and it is the smallest thing that does; it is not what Foobara's design is
reaching for.

## Footguns

Neither is documented anywhere I found, and both cost real time:

- The `authenticator:` block is `instance_exec`'d against the request, so it takes
  **no argument** and `self` is the request. `->(request) { … }` fails with a
  confusing arity error.
- On the Rack connector the request exposes `env`, not `raw_request.env`.

## TypeScript generator bugs

The whole React UI runs on the generated SDK — 175 files from
`script/generate_ts.rb` — and 27 cucumber scenarios pass against it. Three
defects had to be worked around first; two are patched after generation, in that
script.

- **`RequiresAuthCommand` assumes Foobara's own auth domain.** It is emitted for
  every command declaring `requires_authentication`, and imports
  `./utils/accessTokens` and `./RefreshLogin` — neither of which is generated
  unless the app uses `Foobara::Auth`. Any other auth scheme gets an SDK that
  does not compile.
- **`RemoteCommand#_handleResponse` calls `this.dirtyQueries()` unconditionally**,
  but that method is only emitted for apps declaring queries. With none declared,
  *every successful command* raises `TypeError: this.dirtyQueries is not a
  function`. This is the more serious one: it is not a type error, so `tsc` is
  clean and it only appears in a browser.
- **`associative_array` is unsupported** — "Not sure how to convert
  associative_array to a TS type". Emoji⇒count maps and presigned form fields are
  modelled as pair lists here to avoid it. Foobara's own type system handles
  them; only the TS generator does not.

Two sharp edges that are arguably documentation gaps:

- **`raw_manifest:` and `manifest_url:` are not interchangeable.**
  `Foobara.manifest` has symbol values and fails with "Not sure how to convert
  :string to a TS type"; `JSON.parse` of it has string keys and fails with
  "undefined local variable or method `serializers`". Only `symbolize_names: true`
  works — and only against the manifest a *connector* serves, because
  `serializers` and `requires_authentication` are connector-level and absent from
  `Foobara.manifest`.
- **`output_directory` is relative to the CWD**, not to `project_directory`.

A third gap, related: the SDK has no hook for an `Authorization` header, because
the upstream assumption is that `RequiresAuthCommand` supplies one. The patch
here adds it to the base `RemoteCommand`, not to `RequiresAuthCommand` — the
public-but-viewer-aware commands extend the base directly and need the token too,
or a signed-in caller looks anonymous to them.

## Design differences the app absorbed

Not defects — decisions that changed the app or its tests:

- **Every declared runtime error answers 422**, with the meaning in the error's
  `symbol`. The forgery scenarios assert the symbol, which is the more stable
  thing to assert.
- **Errors serialize as a JSON array**, so a command can report several at once.
- **Input and output types cannot be shared when the server derives a field.**
  `CreatePost` first reused `Shared::MediaItem` for its `media` input, but that
  type requires `url`, which is derived from the key — so every upload failed
  with "Missing required attribute url". Split into `Shared::MediaUpload` (what a
  client may send) and `Shared::MediaItem` (what it receives).
- **Commands are served at `/run/<Domain>/<Command>`**, from `scoped_full_path`.

## What a green test suite did not catch

27 cucumber scenarios in a real browser, passing throughout. Then deploying found
eight defects:

| # | Defect | Symptom |
|---|--------|---------|
| 1 | Authorizer declared an `identity_source` | Every anonymous caller 401'd; API Gateway never invoked the Lambda |
| 2 | CloudFront `error_responses` are distribution-wide | The API's 403 came back as `200` serving `index.html` |
| 3 | Tables built with no GSIs | Feed 500'd: `Query` on `posts_by_recency` refused |
| 4 | CDK omits index ARNs unless a table declares an index | The same failure again, one layer down, after the GSIs existed |
| 5 | `dynamodb:ListTables` never granted | Every write 500'd — Dynamoid probes table existence on first write |
| 6 | S3 presigning, delete and public URL never implemented | `NotImplementedError` |
| 7 | `require "aws-sdk-s3"` inside an argument expression | `uninitialized constant Aws::S3` — Ruby resolves the constant first |
| 8 | Ruby 4.0 ships no XML library as a default gem | Unit booted, then died on the first S3 call |

Plus a ninth that behaves like a defect: the custom domain lived in an
environment variable, so a deploy that forgot it produced a stack with no
certificate, no records and no alias — and would have deleted them on the next
run. Config that exists only in a shell history is not config.

**Why the suite missed all of them.** Every one lives in a seam the suite does
not have. It exercises a different storage path (a dev object store, not S3), a
different identity path (dev personas over a cookie, not verified claims), a
single process with no API Gateway, no CloudFront and no IAM — and tables created
by the app itself through `Dynamoid.create_table`.

That last one repays attention. The local suite passed *because* it built its
tables from the same models the CDK stack was failing to restate. It could not
have disagreed with itself. A test only catches drift between two things it
actually compares.

**What would have caught them, cheapest first:**

1. **A post-deploy contract check.** This now exists — `Foobara::AWS::Check`,
   driven by the plan, so it knows which commands are public without being told.
   Against the deployed API it runs 48 checks (`script/check_deploy.rb`):

   ```
   48/48 checks passed
   ok   Posts::ListPosts        reachable anonymously (expected not 401/403, got 200)
   ok   Posts::GetPost          reachable anonymously (expected not 401/403, got 422)
   ok   Uploads::Presign        refused anonymously (expected 401/403, got 403)
   ok   Uploads::Presign        refusal is not a web page (expected json, got application/json)
   ```

   Replaying defects 1 and 2 through it — every caller 401'd, refusals rewritten
   to `200 text/html` — fails 44 of those 48. It would have caught both, in a run
   taking seconds.

   A 422 counts as reachable, as `Posts::GetPost` shows above: every request
   carries `{}`, so a command with required inputs answers 422, and the question
   is whether the request reached the command rather than whether it liked the
   inputs. Gated commands are only ever called *without* credentials, so they are
   refused before executing and nothing is written.
2. **Running a real command inside the packaged artifact**, not merely booting it.
   The packager booted each unit and that caught nothing — booting exercises no
   path that matters. Invoking one command per unit against real configuration
   found defects 6, 7 and 8 immediately, and before deploying.
3. **Asserting the synthesised template** — does the authorizer declare an
   identity source, does the distribution declare error responses, do the tables
   declare the indexes their models declare. Those catch 1, 2 and 3 with no AWS
   account at all.

The general shape: this suite tests **the app**, thoroughly. Nothing tested **the
deployment**, and a serverless deployment is not configuration — it is a
distributed system whose failure modes are mostly permissions, routing and edge
behaviour. Foobara has nothing to say about that, and neither does any other
framework; it is a gap in how the app was tested, not in what it was built with.

## What became a gem

Everything in this repo that was about *deploying Foobara* rather than about
bookface is now [foobara-aws](https://github.com/omarqureshi/foobara-aws):

```ruby
Foobara::AWS.plan(manifest)   # what to deploy. No CDK, no Foobara.
Foobara::AWS::Packager        # one artifact per unit.
Foobara::AWS::CDK::Service    # the AWS resources. Synth time.
Foobara::AWS::Handler         # API Gateway v2 -> Rack. Runtime.
Foobara::AWS::Authorizer      # optional auth. Runtime.
```

The split that matters: the plan is plain data, produced where the app is and
consumed where the infrastructure is. Synthesis reads what was *built*, so it
cannot route to an artifact that does not exist, and `infra/` installs neither
Foobara nor Dynamoid — nine gems, all CDK.

Moving it shrank this repo by 355 lines and answered the question the exercise
started with: **none of the deployment machinery was ever application-specific.**

Two things it added that this app could not have had alone:

- **`aws_lambda` on a command.** The manifest has no place for deployment
  metadata — Foobara describes what a command *is*, not how to run it, which is a
  defensible line, but something must carry it. `DestroyPost` declares
  `aws_lambda vcpu: 1, timeout: 60` because it fans out across a whole comment
  tree; that travels through the manifest into the plan and onto the function
  (verified: 1769MB/60s, everything else 1024/10). It needs no change to Foobara,
  since a command's manifest is `super.merge(...)` — but a first-class place for
  it would be better than a gem bolting one on.
- **Two edge bugs made unrepresentable.** `Service` builds the authorizer itself
  precisely so it can guarantee `identity_source: []` and no caching, which is
  defect 1 above; and the SPA history fallback is a viewer-request function on
  the site behaviour only, which is defect 2.

What stayed here, because it genuinely is this app's: where the sources live, the
DynamoDB schema (via `dynamoid-cdk-schema`, same describe/build split), and the
least-privilege grants — the manifest says which commands a unit serves, not
which tables they touch.

## Costs

Artifact sizes, measured:

```
authorizer   660K    (foobara-aws + jwt; no app, no Foobara)
comments      35M    DynamoDB only
reactions     35M
posts         43M    + aws-sdk-s3
profiles      43M
uploads       43M
```

Per-unit gem slicing works — the units that never touch S3 are 8MB smaller — and
the authorizer being three orders of magnitude smaller than a domain unit is the
point of keeping it separate: it runs on every request, including anonymous ones.

**Cold start is about 2 seconds**, against 7–12 seconds for the Rails monolith
this app replaces.

That is not a like-for-like framework comparison — the old one is a whole Rails
application in a single function, this is one domain's commands in a slice of a
gem bundle — but the difference is the point. Three things contribute, in
descending order: no Rails, a bundle holding only what one domain needs, and
`bundle install --standalone` so Bundler's own runtime is never loaded.

2 seconds is still slow enough to notice on a first request, and most of it is
Foobara's own load. Per-command granularity would divide the *work* further but
not that constant, which is the argument for keeping domains as the unit.

X-Ray is enabled on every function, so an `Initialization` subsegment gives the
number directly rather than inferring it from `REPORT` lines.

## Open questions

- **Optional identity**, above. The only finding that is about Foobara's model
  rather than its tooling, and the only one that cannot be worked around without
  a thread-local.
- **A place for deployment metadata** in the manifest, rather than a gem
  extending it.
- **Cold start**, if 2 seconds is too slow. The load is Foobara's, so the levers
  are its own boot cost or something that avoids paying it per request.
