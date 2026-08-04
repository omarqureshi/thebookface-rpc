# bookface-rpc (foobara branch)

Bookface as a [Foobara](https://github.com/foobara) app — one **domain** per
Lambda, with the deployment derived from Foobara's manifest. `main` is the same
app built on [Prospect](../../prospect); the two exist to be compared. See
[FOOBARA.md](FOOBARA.md) for what that comparison found, and [DESIGN.md](DESIGN.md)
for Prospect's own design.

Nothing here depends on Prospect any more. The last piece was the optional-auth
Lambda authorizer, now `lib/bookface_authorizer.rb` — see FOOBARA.md on why that
belongs in a connector rather than an app.

## Local

Needs Docker and Ruby 3.3+. No AWS account, no credentials, no LocalStack —
DynamoDB runs locally and S3/SQS are stubbed in-process.

```sh
bundle install
script/dev.sh up      # dynamodb-local + create tables + serve on :9292
script/dev.sh smoke   # request smoke test
script/dev.sh stop
```

All five domains are connected to **one** connector locally; deployed each is its
own Lambda running the same `Foobara::CommandConnectors::Http::Rack`. A unit does
not refuse other domains' commands — it simply never registers them.

There's no API Gateway locally and therefore no authorizer, so identity comes
from headers (or a cookie, for the browser):

```sh
curl -X POST localhost:9292/run/Posts/CreatePost \
  -H 'Content-Type: application/json' \
  -H 'X-Dev-Sub: dev|ada' -H 'X-Dev-Name: Ada Lovelace' \
  -d '{"body":"Hello from a command."}'
```

Commands are served at `/run/<Domain>/<Command>`, from the manifest's
`scoped_full_path`. `GET /manifest` is the manifest itself — packaging, the
TypeScript SDK and the CDK stack are all derived from it.

Deployed, those dev headers are ignored: a unit honours them only when
`BOOKFACE_DEV_IDENTITY=1`, which the stack never sets. Identity there is the
verified claims from the authorizer.

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
script/dev.sh serve                              # serves /manifest
bundle exec ruby script/package_from_manifest.rb # artifacts + units.json + tables.json
cd web && npm run build                          # SPA into web/dist
cd infra && bundle exec cdk deploy
```

Packaging emits two files the stack reads: `units.json` (topology, from the
manifest) and `tables.json` (storage, from the Dynamoid models via
[dynamoid-cdk-schema](https://github.com/omarqureshi/dynamoid-cdk-schema)). So
synthesis needs no running server and carries neither Foobara nor Dynamoid nor
the app — and it cannot route to a Lambda whose artifact was never built.

The SPA sits on S3 behind CloudFront, and **the API is on the same distribution
at `/run/*`**, with images at `/media/*`. That is not a detail: it makes the
client same-origin, so there is no CORS and no preflight, and it lets the bundle
ship with no environment-specific URL (`RemoteCommand.urlBase = ""`). The local
Vite proxy points `/run` at the API for the same reason: dev and production
agree.

The SPA history fallback is a **viewer-request CloudFront Function on the default
behaviour only**, not `error_responses`. Custom error responses apply to the
whole distribution, so the usual `403/404 -> /index.html 200` recipe also
rewrites the API's own errors into a 200 HTML page — see FOOBARA.md.

## Frontend

```sh
script/dev.sh up                 # API on :9292
cd web && npm install && npm run dev   # UI on :5173, proxies /rpc
```

The client is **generated from the manifest** by Foobara's own generator — 175
files, no hand-written protocol:

```sh
script/dev.sh serve                        # /manifest
bundle exec ruby script/generate_ts.rb     # -> web/src/domains
```

That script also applies three post-generation patches, each working around a
generator bug documented in FOOBARA.md. `src/api/index.ts` is a thin adapter
presenting the old `api.posts.feed({...})` shape over the generated command
classes, so components did not have to be rewritten around a different call
style.

Identity is chosen at runtime by whether the stack deployed a `config.json`:
Cognito (Authorization Code + PKCE against the hosted UI) when it did, two
hardcoded dev personas when it did not. One bundle serves both.

## Packaging

Builds one deployable artifact per service. Needs Docker.

```sh
bundle exec ruby script/package_from_manifest.rb
```

One artifact per **domain**, derived from the manifest: a unit's commands are
whichever ones the manifest files under that domain, and its public list comes
from `requires_authentication`. There is no hand-maintained list of either.

Each artifact holds the app sources, a generated `handler.rb`, and a standalone
gem bundle containing only that unit's dependencies (`units/*.gemfile`). Units
whose gemfiles resolve identically share one bundle build.

The authorizer is a unit too, but not a domain one: it serves no commands and
needs neither the app nor Foobara — one file and one gem, 576K.

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
