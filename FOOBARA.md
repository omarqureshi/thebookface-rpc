# Foobara spike

Can Foobara replace Prospect's RPC half while keeping its deployment half? This
branch answers that by building it, not by reasoning about it.

**Yes, and the manifest is a better IR than the one Prospect grew.**

## What works

All five domains — 12 commands — served by Foobara's Rack connector locally and
packaged from the manifest into five Lambda artifacts, each of which boots in
the runtime image, serves its own commands and 404s every other domain's.

```
built comments:  4 commands, route /rpc/comments/{proxy+},  public 1
built posts:     3 commands, route /rpc/posts/{proxy+},     public 2
built profiles:  2 commands, route /rpc/profiles/{proxy+},  public 0
built reactions: 2 commands, route /rpc/reactions/{proxy+}, public 1
built uploads:   1 commands, route /rpc/uploads/{proxy+},   public 0
```

Isolation, in the built artifacts:

```
posts      own=200  foreign(Uploads)=404
comments   own=422  foreign(Posts)=404      (422 = input validation: it ran)
reactions  own=422  foreign(Posts)=404
profiles   own=200  foreign(Posts)=404
uploads    own=422  foreign(Posts)=404
```

And the auth gate, also in the artifacts:

```
Posts::ListPosts      signed-in=200  anonymous=200   (public)
Posts::CreatePost     signed-in=200  anonymous=401
Uploads::Presign      signed-in=200  anonymous=401
Profiles::GetProfile  signed-in=200  anonymous=401
```

The public/auth split is **derived from the manifest**, not handed to the
packager — `requires_authentication`, one field per command.

## The manifest drives packaging

`script/package_from_manifest.rb` is Prospect's packager with the router swapped
for a manifest. Everything topological comes straight out:

| packaging needs | manifest field |
| --- | --- |
| unit identity and grouping | `domain`, `organization` — **two** levels; Prospect has one |
| the route | `scoped_full_path` |
| which commands are public | `authenticator` — **derived, not hand-listed** |
| what a per-command unit must contain | `depends_on` |
| client generation | `inputs_type`, `result_type`, `possible_errors` |

Two of those are things Prospect could not do. The `anonymous:` list in
Prospect's CDK stack was hand-maintained and could silently drift from what the
app enforced; here it is read. And `depends_on` is a declared command dependency
graph — the file-level slicing problem Prospect deferred as "v1, and hard"
because Ruby's require graph is not soundly analysable. Foobara does not analyse
it; commands declare it.

`connect(Domain)` is what makes a unit a subset. Prospect::Lambda has a `unit:`
check that *refuses* out-of-unit procedures as defence in depth; a domain-scoped
connector never registers the others, so there is nothing to refuse. Better
property, obtained by construction.

## What Foobara does better

- **It validates results.** It rejected an explicit `nil` for an optional
  attribute in a command's output. Prospect only ever validated inputs.
- **Validation errors are derived from types.** `possible_errors` includes
  entries like `data.body.cannot_cast` automatically. Prospect makes you declare
  `errors: [ValidationFailed]` by hand, and its IR cannot derive them because
  Sorbet's types do not describe coercion — the same root cause as the
  `DateTime` and `BigDecimal` bugs on the main branch.
- **Types are one system.** No `from_hash` that skips validation, no `.to_time`
  and `.to_i` scattered through a presenter.

## What is harder

- **The caller is kept out of the command body**, on purpose: `current_user` is
  for `allowed_rule`, and `execute` is pure domain logic. bookface needs the
  viewer as *data* — `editable`/`deletable` are per-viewer fields. This branch
  uses a thread-local set by middleware, which is a spike shortcut; the
  idiomatic answer is a request mutator injecting it as an input, the way the
  auth demo's `SetRefreshTokenFromCookie` injects a token.
- **Optional auth recurs.** The connector authenticates only commands declaring
  `requires_authentication`, so a command that is public *and* viewer-aware
  never learns who is calling — the same gap as API Gateway's JWT authorizer,
  one layer up. Worked around here with middleware that always runs.
- **Optional auth needs two mechanisms, not one.** `requires_authentication:
  true` calls the connector's authenticator — and raises on nil if there isn't
  one — while public commands skip authentication entirely. So a public but
  viewer-aware command needs identity from somewhere else. This branch pairs an
  authenticator (the gate) with middleware (identity for public commands), both
  reading the same headers. Worth raising with the maintainer: it is the same
  shape of problem as API Gateway's JWT authorizer.
- **Artifact size**: 35MB for the DynamoDB-only units, 42MB for those needing
  the S3 SDK, against 31–38MB on the Prospect branch. Per-unit gem slicing
  works — comments and reactions are 7MB smaller than uploads because they omit
  aws-sdk-s3 — but Foobara itself costs more than Prospect did.

## Footguns worth knowing

None is documented anywhere I found, and all cost real time:

- The authenticator block is `instance_exec`'d against the request, so it takes
  **no argument** and `self` is the request. `->(request) { … }` fails with a
  confusing arity error.
- On the Rack connector the request exposes `env`, not `raw_request.env`.

## Generator bugs found by porting the UI

The whole React UI runs on the generated SDK (`script/generate_ts.rb`, 175
files) and the cucumber suite passes against it — but three defects had to be
worked around first. Two are patched after generation, in that script.

- **`RequiresAuthCommand` assumes Foobara's own auth domain.** The generator
  emits it for every command declaring `requires_authentication`, and the file
  imports `./utils/accessTokens` and `./RefreshLogin` — neither of which it
  generates unless the app uses `Foobara::Auth`. An app authenticating any other
  way (bookface uses a cookie) gets an SDK that does not compile. Patched to a
  pass-through: `RemoteCommand` already sends `credentials: "include"`.
- **`RemoteCommand#_handleResponse` calls `this.dirtyQueries()` unconditionally**,
  but the method is only emitted for apps that declare queries. With none
  declared, *every successful command* raises `TypeError: this.dirtyQueries is
  not a function` at runtime. Patched to a no-op. This is the more serious of
  the two: it is not a type error, so it only surfaces in a browser.
- **`associative_array` is unsupported** — "Not sure how to convert
  associative_array to a TS type". Emoji=>count maps and presigned form fields
  are both modelled as pair lists here to avoid it. Foobara's own IR handles
  them; only the TS generator does not.

And two sharp edges that are arguably documentation gaps rather than bugs:

- **`raw_manifest:` and `manifest_url:` are not interchangeable.**
  `Foobara.manifest` has symbol values and fails with "Not sure how to convert
  :string to a TS type"; `JSON.parse` of it has string keys and fails with
  "undefined local variable or method `serializers`". Only
  `symbolize_names: true` works — and only against the manifest a *connector*
  serves, because `serializers` and `requires_authentication` are
  connector-level and absent from `Foobara.manifest`.
- **`output_directory` is relative to the CWD**, not to `project_directory`.

## Differences the port had to absorb

Not defects — design differences that changed the app or its tests:

- **Every declared runtime error answers 422.** Prospect chose a status per
  error code (403 forbidden, 404 not_found); Foobara puts the meaning in the
  error's `symbol` and the status is always 422. The forgery scenarios in
  `features/step_definitions/permissions_steps.rb` now assert the symbol, which
  is the more stable thing to assert anyway.
- **Errors serialize as a JSON array**, not a single `{error: {code: …}}`
  object — so a command can report several at once.
- **Input and output types cannot be shared when the server derives a field.**
  `CreatePost` first reused `Shared::MediaItem` for its `media` input, but that
  type requires `url`, which `MediaStorage` derives from the key — so every
  upload failed with "Missing required attribute url". Split into
  `Shared::MediaUpload` (what a client may send) and `Shared::MediaItem` (what
  it receives). Prospect had the same split for the same reason; it is a
  property of the domain, not of either framework.
- **Commands are at `/run/<Domain>/<Command>`**, from `scoped_full_path` — so
  the Vite proxy forwards `/run`, not `/rpc`.

## The CDK, ported

`infra/stacks/bookface_stack.rb` now synthesises from the manifest rather than
from a router, and `cdk synth` produces the same topology it did on the
Prospect branch: five domain Lambdas behind one HTTP API, greedy
`ANY /run/<Domain>/{proxy+}` routes, a REQUEST authorizer, CloudFront with the
API at `/run/*` on the same distribution.

What that took, and what it says:

- **`Prospect::CDK::Service` is router-shaped in exactly three places** —
  `units`, `schema_hash`, and `setting` (per-procedure sizing). Everything else
  (functions, integrations, routes, authorizer wiring, greedy-vs-exact route
  splitting, custom domain, DNS) is generic. Given a `units:` prop instead of
  `router:`, the same construct would serve both. That is the deployment half of
  the earlier conclusion, now measured rather than asserted.
- **The manifest has nowhere to put deployment metadata.** Prospect declared
  `deploy memory: 1769, timeout: 60` on `posts.destroy` — the one procedure that
  fans out across a whole thread — and the construct took the largest value in a
  unit. Foobara describes what a command *is*, not how it should be run, which is
  a defensible line; but something has to carry it, so it sits in a `SIZING`
  constant in the stack. This is the only genuine gap the port hit.
- **Least-privilege grants stay hand-written under either framework.** The
  manifest says which commands a unit serves, not which tables they touch.
  `depends_on` is a command-to-command graph, which is a different question.
- **`build/units.json` is now the contract between packaging and synthesis.**
  The Prospect stack read the router's IR in-process, so synthesis loaded the
  whole app; this one reads what the packager wrote. Synthesis therefore needs
  no running server, no Foobara and no Dynamoid — `infra/Gemfile` is down to
  CDK alone — and it cannot route to a Lambda whose artifact was never built.
- **`Prospect::Authorizer` survives unchanged**, and reasonably so: optional
  auth is a property of API Gateway, not of the framework behind it. A JWT
  authorizer still cannot express it — four commands here are public *and*
  viewer-aware — and the anonymous list it is configured with is derived from
  `requires_authentication`, so there is no hand-maintained list of public
  commands anywhere in the repo.

## What this means

The RPC half of Prospect is a worse duplicate of Foobara and should go. The
deployment half — per-unit packaging, gem slicing, CDK synthesis, the
optional-auth Lambda authorizer, the cold-start defaults — is not duplicated by
anything and works on top of the manifest with the router swapped out.

That is a connector, not a framework.
