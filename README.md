# bookface-rpc

Bookface as a [Prospect](../../prospect) app — one service per controller, each
a Lambda. See [DESIGN.md](DESIGN.md). No UI.

## Repository layout

This app depends on [prospect](https://github.com/omarqureshi/prospect) as a
**path gem**, so the two must be cloned as siblings:

```
repos/
  prospect/
  thebookface-rpc/
```

`path:` rather than `git:` on purpose: the two are developed together, and a
change to the framework should be visible here without a commit and a bundle
update. It is also what makes packaging work — `script/package.rb` mounts the
prospect checkout into the build container, which a git-sourced gem would not
need but a path gem does. Once prospect is published, the `mounts:` option and
these path references both go away.

## Local

Needs Docker and Ruby 3.3+. No AWS account, no credentials, no LocalStack —
DynamoDB runs locally and S3/SQS are stubbed in-process.

```sh
bundle install
script/dev.sh up      # dynamodb-local + create tables + serve on :9292
script/dev.sh smoke   # request smoke test
script/dev.sh stop
```

All five services run in **one** process locally; deployed they are five
Lambdas. Both go through `Prospect::Dispatcher`, so behaviour can't drift.

There's no API Gateway locally and therefore no JWT authorizer, so identity
comes from headers:

```sh
curl -X POST localhost:9292/rpc/posts/create \
  -H 'Content-Type: application/json' \
  -H 'X-Dev-Sub: user-alice' -H 'X-Dev-Name: Alice' \
  -d '{"body":"Hello from a procedure."}'
```

A batched post view — three services, one round trip:

```sh
curl -X POST 'localhost:9292/rpc?batch=1' -H 'Content-Type: application/json' -d '[
  {"id":"posts.get","input":{"id":"<ID>"}},
  {"id":"comments.thread","input":{"post_id":"<ID>"}},
  {"id":"reactions.mine","input":{"post_id":"<ID>"}}
]'
```

`GET /up` lists every registered procedure.

### Routes

State that changes what you see is in the URL, so reloads, the back button and
links all work:

```
/                  the feed
/posts/:id         feed with that post's thread expanded
/posts/:id/edit    feed with that post in its edit form
/profile           your profile
```

Paths mirror the Rails app's. Threads expand in place rather than navigating to
a post page — the equivalent of the Turbo Frame the Rails view used — but the
URL still changes, so a thread can be linked to.

Vite's dev server serves `index.html` for unknown paths already. Deployed, the
CloudFront distribution does it — see `infra/stacks/bookface_stack.rb`.

## Deploying

```sh
bundle exec ruby script/package.rb    # Lambda artifacts
cd web && npm run build               # SPA into web/dist
cd infra && bundle exec cdk deploy
```

The SPA sits on S3 behind CloudFront, and **the API is on the same distribution
at `/rpc/*`**. That is not a detail: it makes the client same-origin, so there is
no CORS and no preflight — which matters because every request carries
`X-Prospect-Schema`, a custom header that would otherwise make each one
non-simple. It also means `createClient({ url: "/rpc" })` needs no build-time
configuration, so the bundle is identical in every environment. The local Vite
proxy points `/rpc` at the API for the same reason: dev and production agree.

CloudFront rewrites 403 and 404 to `/index.html` with a 200, which is what makes
`/posts/:id` survive a cold load or a refresh. S3 answers 403 rather than 404 for
a missing key when access is via OAC, so both are needed.

## Frontend

```sh
script/dev.sh up                 # API on :9292
cd web && npm install && npm run dev   # UI on :5173, proxies /rpc
```

Types are **generated from the router**, never hand-written:

```sh
cd web && npm run schema         # -> src/api/schema.ts
```

`src/api/client.ts` is hand-written and generic over the generated `Procedures`
map — retries, batching and error decoding live there, so regenerating produces
a legible type diff rather than a rewritten client.

Two users are hardcoded in the header for switching identity, since there's no
Cognito locally.

## Packaging

Builds one deployable artifact per service. Needs Docker.

```sh
bundle exec ruby script/package.rb --dry-run   # what would be built
bundle exec ruby script/package.rb             # build into build/
```

Each artifact holds the app sources, a generated `handler.rb`, and a standalone
gem bundle containing only that service's dependencies (`units/*.gemfile`).
Services whose gemfiles resolve identically share one bundle build — 5 units
currently collapse to 3.

Every artifact is booted in a Lambda-like container before the build succeeds.
An unsound slice caught at build time is an inconvenience; caught at invoke time
it is an outage.

## Cucumber

27 scenarios ported from the Rails app, running in a real headless browser
against the SPA, the API and DynamoDB Local.

```sh
cd web && npx @puppeteer/browsers install chrome@stable   # once
script/cucumber.sh                                        # everything
script/cucumber.sh features/comments.feature              # one file
```

The script starts the API and the Vite dev server, waits for both, runs the
suite and tears them down.

**What ported unchanged:** every `.feature` file, and every step that seeds
through the Dynamoid models. The Gherkin described user behaviour, not Rails.

**What had to be rewritten:** the harness and the interaction steps. The old
suite used `cucumber-rails` and drove server-rendered HTML in-process with
`rack_test`. Here the UI is a React SPA, so nothing exists until JavaScript has
run — every scenario needs a real browser, and Capybara must not boot a Rack app
of its own.

**Two steps deliberately bypass the UI.** "I try to edit a post I do not own" and
"a forged delete" forge the call the way a hostile client would and assert the
server refuses. The UI never renders those controls, so driving it would test
the client's manners rather than the security boundary.
