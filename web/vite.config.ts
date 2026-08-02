import { defineConfig } from "vite"
import react from "@vitejs/plugin-react"

// Proxies /rpc to the local Rack server, which runs all five services in one
// process. Deployed, the same paths hit five Lambdas behind API Gateway — the
// frontend cannot tell the difference, which is the point of routing by
// procedure path (prospect/DESIGN.md §6).
export default defineConfig({
  plugins: [react()],
  server: { proxy: { "/rpc": "http://localhost:9292" } },
})
