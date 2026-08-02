# bookface-rpc

Bookface redesigned as a [Prospect](../../prospect/DESIGN.md) app: one **service
per controller**, each deployed as its own Lambda, behind one API Gateway front
door. No UI — this is the API surface only.

It is written against a Prospect that **does not exist yet**. That is the point:
a real app is a better test of the router DSL than an imagined one, and every
awkwardness here is a bug report against `prospect/DESIGN.md` before it's
implemented. Open DSL questions are collected in §6.

## 1. Controller → Service

| Rails controller | Service | Procedures |
| --- | --- | --- |
| `PostsController` | `posts` | `feed`, `get` · `create`, `update`, `destroy` |
| `CommentsController` | `comments` | `thread` · `create`, `update`, `destroy` |
| `ReactionsController` | `reactions` | `mine` · `toggle` |
| `ProfilesController` | `profiles` | `get` · `update` |
| `UploadsController` | `uploads` | `presign` |
| `SessionsController` | — | dissolved into the JWT authorizer (§3) |

Each service is one Lambda (`granularity: :per_router`), routed as
`/rpc/posts/{proxy+}` etc. Per Prospect §6 that choice is invisible to clients,
so collapsing to one function or splitting a hot procedure out later needs no
client regeneration.

### What disappears

- **`new` and `edit`.** Pure view actions. Five REST actions become three
  procedures.
- **Base64 comment ids.** `Comment#to_param` exists only because a materialized
  path contains `/` and can't sit in a URL segment. In a request body it's just
  a string.
- **Turbo Stream responses.** `reactions#toggle` returns data — the updated
  counts and the viewer's own emoji — instead of an HTML fragment.
- **`redirect_to` as control flow.** Rails signals "not found" and "not yours"
  by bouncing with a flash. Those become typed errors in the contract (§4), so
  the client gets a discriminated union rather than a redirect.

## 2. Composite reads: separate procedures, batched

A post page needs the post, its comment thread, and the viewer's own reactions.
Rails' `posts#show` does all three in one action. Here they stay in their own
services and the client batches:

```ts
const [post, thread, mine] = await Promise.all([
  api.posts.get({ id }),
  api.comments.thread({ postId: id }),
  api.reactions.mine({ postId: id }),
])
```

The Prospect client coalesces concurrent queries into a single
`POST /rpc?batch=1`, so this is one HTTP round trip.

**The honest cost: it fans out to three Lambdas, so a cold page view can pay
three cold starts.** At the ~285ms measured in Prospect §6 that's real. It is
the price of genuine service independence, and the mitigations are ordinary:
provisioned concurrency on `posts`, or collapsing to `granularity: :single`
under load, which — because granularity is invisible — is a deploy-time flag and
not a rewrite.

The rejected alternative was a fat `posts.show` returning everything. It's
faster, but it puts comment-threading and reaction logic inside the posts
service, which is precisely the coupling service-per-controller exists to
prevent.

## 3. Auth moves to the edge

Cognito stays the identity provider, but the OIDC dance leaves the API. API
Gateway runs a **JWT authorizer** against the Cognito user pool, so:

- `SessionsController` has no successor. No `create`, no `failure`, no
  `destroy`, no OmniAuth in any service's cold-start path.
- Every service receives *already-verified* claims in
  `event.requestContext.authorizer.jwt.claims`.
- `Context` is built from those claims and nothing else (`app/context.rb`).

`User` survives almost unchanged — it was already a value object reconstructed
from claims rather than a persisted record, which made it unusually easy to move.

**Authorization stays in the app.** `Ability` (CanCanCan) is unchanged; services
call `authorize!` and a denial becomes a typed `Forbidden` rather than a
redirect. Authentication is infrastructure; authorization is domain.

### Known limitation

`ctx.user` is `T.nilable(Viewer)` even inside `authenticated do … end`, because
Prospect v0 has no static context narrowing (its §6 defers this). So authored
procedures must still handle a nil user the type system can't rule out. This is
the single biggest ergonomic gap the port surfaces, and it is exactly the
feature tRPC users like most.

## 4. The contract

Wire types are hand-written `T::Struct`s in `app/schema`, **not** derived from
Dynamoid models. Auto-derivation from a persistence model is how internal fields
leak; the allowlist is the safety property.

Two decisions worth stating:

**`author_sub` is not exposed.** Rails templates compare `author_sub` to
`current_user.sub` to decide whether to show edit controls. Sending the Cognito
subject to every client just to let it re-implement `Ability` is worse on both
counts, so `Post` and `Comment` carry a server-computed `editable` boolean
instead. Ownership logic stays in one place and an internal identifier stops
travelling.

**The comment thread is flat.** `Comment` has `path` and `depth`, and the client
indents by depth — mirroring how the materialized path already renders. This
avoids a recursive wire type, which matters because Prospect's IR (§4 there)
handles recursion poorly. A DynamoDB modelling choice turns out to produce a
naturally IR-friendly contract.

### The camelCase trap, live

`Post#reactions` is `{ "👍" => 12, "❤️" => 3 }` — a `T::Hash[String, Integer]`
whose keys are *emoji data*, not field names. A generic deep-camelize in the TS
client would corrupt them. This app is a concrete instance of the bug Prospect
§7 predicts, and the reason the IR must distinguish `struct` from `map`.

## 5. What isn't an RPC service

- **`ProfileReconciliation`** — SQS-triggered fan-out that rewrites denormalized
  author snapshots. It's a Lambda, but an *event handler*, not a procedure. It
  keeps its own function and is not in the router.
- **`MediaStorage`** — S3 presigning, called by `uploads.presign`. Plain
  collaborator.
- **`AttachedMedia`** — parses client-supplied media JSON. In the RPC design the
  input is already typed, so most of its parsing work disappears.

## 6. Findings

Discovered by writing this app and then running it. The first three are
**resolved** — running the code answered them; the rest are still open.

### Resolved by running it

- **`T::Struct.from_hash` does not type-check.** `from_hash({"body" => 42})`
  puts an Integer in a `T.nilable(String)` field without complaint; only `.new`
  checks. Prospect's DESIGN §3 claimed the opposite. Fixed by having the
  dispatcher reflect over declared props and validate — which is the same walk
  the IR extractor needs.
- **Errors must be Prospect's, not the app's.** These were redeclared here as
  `< Prospect::Error` and silently lost their HTTP statuses: an unauthenticated
  call returned 422 instead of 401. Now aliased. Answers old §6.4 — Prospect
  should own the errors every app needs.
- **Timestamps need a coercion story.** Dynamoid returns `DateTime`; a
  `T::Struct` field typed `Time` rejects it outright. Handled with `.to_time` at
  the presenter boundary, but the IR's `timestamp` scalar needs a defined set of
  accepted Ruby types, because ORMs will not hand back `Time`.

### Still open

1. **Middleware scoping syntax.** `authenticated do … end` is implemented and
   works — procedure registration confirms the right middleware on all 14. But
   the shape isn't settled. Alternatives: `use RequireLogin, only: %i[create
   update]` (Rails-like) or a tRPC-style procedure builder. The block reads
   best in Ruby but hides
   which procedures are covered when the file gets long.
2. **Context narrowing** (§3 above). Deferred in Prospect, but every mutation
   here pays for it.
3. **Pagination isn't in the IR.** `Post.recent` currently returns the entire
   feed. A real API needs cursors, and cursor-paginated lists are common enough
   to deserve a first-class IR shape rather than each app inventing one.
4. **Validation errors.** Dynamoid/ActiveModel produce
   `{ field => [messages] }`. Modelled as `ValidationFailed` with a
   `T::Hash[String, T::Array[String]]`. Should Prospect ship this error type
   rather than having every app redefine it?
5. **`Time` on the wire.** Pinned to RFC 3339 UTC in the dispatcher
   (`value.utc.iso8601`). Still needs to be stated in the IR rather than left as
   a dispatcher implementation detail.
6. **Per-procedure deploy overrides.** `posts.feed` is the hot path and
   `posts.destroy` does a batch delete across three tables; they want different
   memory and timeout. The `deploy:` option covers it, but that splits one
   service across two Lambdas — which the granularity model permits but the
   "service per controller" framing doesn't obviously anticipate.
