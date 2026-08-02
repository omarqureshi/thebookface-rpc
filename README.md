# bookface-rpc

Bookface as a [Prospect](../../prospect) app — one service per controller, each
a Lambda. See [DESIGN.md](DESIGN.md). No UI.

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
