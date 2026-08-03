import { defineConfig } from "vite"
import react from "@vitejs/plugin-react"

// Proxies /run to the local Rack server, which connects all five domains in one
// process. Deployed, the same paths hit five Lambdas behind API Gateway — the
// frontend cannot tell the difference, which is the point of routing by command
// path.
//
// /run, not /rpc: the Foobara connector serves each command at
// /run/<Domain>/<Command>, derived from its scoped_full_path. Proxying rather
// than pointing the SDK at :9292 also keeps the dev identity cookie same-origin,
// which matters because the generated SDK sends credentials: "include" and has
// no hook for a custom header.
export default defineConfig({
  plugins: [react()],
  server: { proxy: { "/run": "http://localhost:9292" } },
})
