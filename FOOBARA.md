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

## Two footguns worth knowing

Neither is documented anywhere I found, and both cost real time:

- The authenticator block is `instance_exec`'d against the request, so it takes
  **no argument** and `self` is the request. `->(request) { … }` fails with a
  confusing arity error.
- On the Rack connector the request exposes `env`, not `raw_request.env`.

## What this means

The RPC half of Prospect is a worse duplicate of Foobara and should go. The
deployment half — per-unit packaging, gem slicing, CDK synthesis, the
optional-auth Lambda authorizer, the cold-start defaults — is not duplicated by
anything and works on top of the manifest with the router swapped out.

That is a connector, not a framework.
