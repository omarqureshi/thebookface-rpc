import { createClient, RpcError } from "./client"

// Local dev has no API Gateway and therefore no JWT authorizer, so identity is
// sent as headers. Deployed, this whole block disappears — the Authorization
// bearer token is verified at the edge and the client sends nothing else.
// See bookface-rpc DESIGN.md §3.
export interface DevUser {
  sub: string
  name: string
}

// Persisted, so a page load does not sign you out. Deployed this is a token in
// storage rather than a persona, but the lifetime is the same: identity has to
// outlive the JS module that holds it.
const STORAGE_KEY = "bookface.dev-user"

function restore(): DevUser | null {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    return raw ? (JSON.parse(raw) as DevUser) : null
  } catch {
    return null
  }
}

let currentUser: DevUser | null = restore()

export const setUser = (u: DevUser | null) => {
  currentUser = u
  try {
    if (u) localStorage.setItem(STORAGE_KEY, JSON.stringify(u))
    else localStorage.removeItem(STORAGE_KEY)
  } catch {
    /* private mode; identity just won't survive a reload */
  }
}

export const getUser = () => currentUser

export const api = createClient({
  url: "/rpc",
  headers: (): Record<string, string> =>
    currentUser ? { "X-Dev-Sub": currentUser.sub, "X-Dev-Name": currentUser.name } : {},
})

export { RpcError }
export type * from "./schema"
