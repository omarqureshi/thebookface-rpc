import { createClient, RpcError } from "./client"

// Local dev has no API Gateway and therefore no JWT authorizer, so identity is
// sent as headers. Deployed, this whole block disappears — the Authorization
// bearer token is verified at the edge and the client sends nothing else.
// See bookface-rpc DESIGN.md §3.
export interface DevUser {
  sub: string
  name: string
}

let currentUser: DevUser | null = null
export const setUser = (u: DevUser | null) => {
  currentUser = u
}
export const getUser = () => currentUser

export const api = createClient({
  url: "/rpc",
  headers: (): Record<string, string> =>
    currentUser ? { "X-Dev-Sub": currentUser.sub, "X-Dev-Name": currentUser.name } : {},
})

export { RpcError }
export type * from "./schema"
