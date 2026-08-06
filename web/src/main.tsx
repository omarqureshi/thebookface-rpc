import { StrictMode } from "react"
import { createRoot } from "react-dom/client"
import App from "./App"
// Imported rather than linked from index.html: Vite then content-hashes it, so a
// changed stylesheet arrives under a new URL instead of being served from a
// browser cache that has no idea it is stale.
import "./styles.css"
import { loadAuthConfig, completeSignIn } from "./auth"

// Both settled BEFORE the first render, deliberately.
//
// The config decides which sign-in the top bar offers, and completeSignIn turns
// a ?code= redirect into a token. Rendering first would show the signed-out bar
// and fire the feed anonymously, then flip — and the feed marks your own posts
// editable, so that flicker is visible, not just theoretical.
//
// loadAuthConfig never rejects: locally there is no /config.json, and that is
// the signal to use dev personas rather than an error.
//
// An async function rather than top-level await, which the build target does
// not allow — and raising the target to get it would drop browser support for a
// syntax preference.
async function boot() {
  await loadAuthConfig()
  await completeSignIn()

  createRoot(document.getElementById("root")!).render(
    <StrictMode>
      <App />
    </StrictMode>,
  )
}

void boot()
