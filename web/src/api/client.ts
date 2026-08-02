// Hand-written, generic over the generated `Procedures` map. Deliberately NOT
// generated: retries, batching, auth and error decoding are fixed once here
// rather than re-emitted into every consumer. See prospect/DESIGN.md §7.

import { WIRE_FIELDS, WIRE_NESTED, type Procedures } from "./schema"

type Id = keyof Procedures
type In<K extends Id> = Procedures[K]["input"]
type Out<K extends Id> = Procedures[K]["output"]
type Err<K extends Id> = Procedures[K]["error"]

export class RpcError<E = unknown> extends Error {
  constructor(readonly status: number, readonly detail: E & { code: string }) {
    super(detail.code)
  }
}

// --- wire mapping -----------------------------------------------------------
// Only names present in WIRE_FIELDS are ever renamed, so map keys (emoji counts,
// validation field names) pass through untouched by construction.

const rename = (v: any, type: string | undefined, dir: "to" | "from"): any => {
  if (v === null || v === undefined) return v
  if (Array.isArray(v)) return v.map((x) => rename(x, type, dir))
  if (typeof v !== "object" || !type) return v

  const fields = WIRE_FIELDS[type] ?? {}
  const nested = WIRE_NESTED[type] ?? {}
  const table =
    dir === "to" ? fields : Object.fromEntries(Object.entries(fields).map(([c, w]) => [w, c]))

  const out: Record<string, any> = {}
  for (const [k, val] of Object.entries(v)) {
    const mapped = table[k] ?? k
    // Look up the nested type by the camelCase key, whichever direction we're going.
    const camelKey = dir === "to" ? k : mapped
    out[mapped] = rename(val, nested[camelKey], dir)
  }
  return out
}

// --- client -----------------------------------------------------------------

export interface ClientOptions {
  url?: string
  headers?: () => Record<string, string>
  /** Coalesce concurrent queries into one POST /rpc?batch=1. */
  batch?: boolean
}

interface Pending {
  id: string
  input: unknown
  resolve: (v: any) => void
  reject: (e: unknown) => void
}

export function createClient(opts: ClientOptions = {}) {
  const url = opts.url ?? "/rpc"
  const headers = opts.headers ?? (() => ({}))
  const batching = opts.batch ?? true
  let queue: Pending[] = []
  let scheduled = false

  const unwrap = (status: number, body: any) => {
    if (body?.ok) return body.result
    throw new RpcError(status, body?.error ?? { code: "unknown" })
  }

  async function flush() {
    const batch = queue
    queue = []
    scheduled = false
    if (batch.length === 1) return void single(batch[0])

    try {
      const res = await fetch(`${url}?batch=1`, {
        method: "POST",
        headers: { "Content-Type": "application/json", ...headers() },
        body: JSON.stringify(batch.map((c) => ({ id: c.id, input: c.input }))),
      })
      const rows = await res.json()
      batch.forEach((c, i) => {
        try {
          c.resolve(unwrap(rows[i]?.status ?? res.status, rows[i]))
        } catch (e) {
          c.reject(e)
        }
      })
    } catch (e) {
      batch.forEach((c) => c.reject(e))
    }
  }

  async function single(c: Pending) {
    try {
      const res = await fetch(`${url}/${c.id.replace(".", "/")}`, {
        method: "POST",
        headers: { "Content-Type": "application/json", ...headers() },
        body: JSON.stringify(c.input),
      })
      c.resolve(unwrap(res.status, await res.json()))
    } catch (e) {
      c.reject(e)
    }
  }

  async function call<K extends Id>(id: K, input: In<K>): Promise<Out<K>> {
    const [type] = [String(id)]
    const wire = rename(input, inputTypeOf(type), "to")

    const raw = await new Promise<any>((resolve, reject) => {
      const p: Pending = { id: String(id), input: wire, resolve, reject }
      if (!batching) return void single(p)
      queue.push(p)
      if (!scheduled) {
        scheduled = true
        queueMicrotask(flush)
      }
    })
    return rename(raw, outputTypeOf(type), "from") as Out<K>
  }

  // The IR knows each procedure's input/output type names; until the emitter
  // ships that table too, resolve by convention from the generated maps.
  const inputTypeOf = (_id: string) => undefined
  const outputTypeOf = (id: string) => PROC_OUTPUT[id]

  // Proxy so call sites read `api.posts.get({...})` rather than
  // `call("posts.get", {...})` — the tRPC feel, with no generated methods.
  return new Proxy({} as ApiShape, {
    get: (_t, service: string) =>
      new Proxy({} as any, {
        get: (_t2, proc: string) => (input: any) => call(`${service}.${proc}` as Id, input),
      }),
  })
}

// Output type per procedure, for response mapping.
const PROC_OUTPUT: Record<string, string> = {
  "posts.feed": "FeedPage",
  "posts.get": "Post",
  "posts.create": "Post",
  "posts.update": "Post",
  "posts.destroy": "Empty",
  "comments.thread": "CommentList",
  "comments.create": "Comment",
  "comments.update": "Comment",
  "comments.destroy": "Comment",
  "reactions.mine": "MyReactions",
  "reactions.toggle": "ReactionState",
  "profiles.get": "Profile",
  "profiles.update": "Profile",
  "uploads.presign": "PresignedUpload",
}

type ApiShape = {
  [S in Id as S extends `${infer Svc}.${string}` ? Svc : never]: {
    [P in Id as P extends `${S extends `${infer Svc}.${string}` ? Svc : never}.${infer Proc}`
      ? Proc
      : never]: (input: In<P>) => Promise<Out<P>>
  }
}

export type { Procedures }
