// Sign-in against the Cognito hosted UI, Authorization Code + PKCE.
//
// PKCE rather than the implicit flow, and no client secret: this is a static
// bundle served from S3, so it has nowhere to keep one. The stack registers a
// PUBLIC app client for exactly this, and what stops another site using that
// client id is Cognito's callback-URL allowlist, not secrecy.
//
// The pool is the Rails app's — it already carries the Google IdP and the
// hosted UI, and Google's own OAuth client is registered against that hosted-UI
// domain rather than against this app's hostname. So this works from any origin
// the stack lists in callback_urls, including the Vite dev server.

export interface AuthConfig {
  userPoolId: string
  clientId: string
  hostedUi: string
}

export interface Identity {
  sub: string
  name: string
  email?: string
}

interface Tokens {
  idToken: string
  refreshToken?: string
  // Epoch millis. Kept rather than expires_in, which is only meaningful at the
  // moment of issue.
  expiresAt: number
}

const TOKENS_KEY = "bookface.tokens"
const VERIFIER_KEY = "bookface.pkce-verifier"

// Deploy-time config, written into the site bucket by the stack. Absent locally,
// which is the signal to fall back to dev personas — so the same bundle serves
// both, and no build-time environment variable is involved.
let config: AuthConfig | null = null

export async function loadAuthConfig(): Promise<AuthConfig | null> {
  try {
    const res = await fetch("/config.json", { cache: "no-store" })
    if (!res.ok) return null
    const parsed = (await res.json()) as AuthConfig
    config = parsed.clientId ? parsed : null
  } catch {
    config = null
  }
  return config
}

export const authConfig = () => config

// --- PKCE ------------------------------------------------------------------

function base64url(bytes: ArrayBuffer): string {
  return btoa(String.fromCharCode(...new Uint8Array(bytes)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "")
}

function randomVerifier(): string {
  const bytes = new Uint8Array(32)
  crypto.getRandomValues(bytes)
  return base64url(bytes.buffer)
}

async function challengeFor(verifier: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier))
  return base64url(digest)
}

// The redirect target must match a registered callback EXACTLY, so it is the
// bare origin with a trailing slash — not location.href, which would carry the
// client-side route and be rejected.
const redirectUri = () => `${location.origin}/`

// --- the flow ---------------------------------------------------------------

export async function signIn(): Promise<void> {
  if (!config) return

  const verifier = randomVerifier()
  sessionStorage.setItem(VERIFIER_KEY, verifier)

  const params = new URLSearchParams({
    response_type: "code",
    client_id: config.clientId,
    redirect_uri: redirectUri(),
    scope: "openid email profile",
    // Straight to Google rather than showing Cognito's own chooser: Google is
    // the only provider on this client.
    identity_provider: "Google",
    code_challenge: await challengeFor(verifier),
    code_challenge_method: "S256",
  })
  location.assign(`${config.hostedUi}/oauth2/authorize?${params}`)
}

// Called once at boot. Returns true when it consumed a redirect, so the caller
// knows identity may have changed.
export async function completeSignIn(): Promise<boolean> {
  if (!config) return false

  const code = new URLSearchParams(location.search).get("code")
  if (!code) return false

  const verifier = sessionStorage.getItem(VERIFIER_KEY)
  sessionStorage.removeItem(VERIFIER_KEY)
  // The code is single-use, so it must leave the URL whether or not the
  // exchange succeeds — otherwise a refresh retries it and fails confusingly.
  history.replaceState(null, "", location.pathname)
  if (!verifier) return false

  const res = await fetch(`${config.hostedUi}/oauth2/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "authorization_code",
      client_id: config.clientId,
      code,
      redirect_uri: redirectUri(),
      code_verifier: verifier,
    }),
  })
  if (!res.ok) return false

  store(await res.json())
  return true
}

function store(payload: any) {
  const tokens: Tokens = {
    // The ID token, deliberately, not the access token. The Lambda authorizer
    // verifies `aud` — which a Cognito access token does not carry (it has
    // client_id) — and the handler reads `name`/`email` for the viewer, which
    // only the id token has.
    idToken: payload.id_token,
    refreshToken: payload.refresh_token,
    // 30s of slack so a token cannot expire in flight.
    expiresAt: Date.now() + (payload.expires_in - 30) * 1000,
  }
  localStorage.setItem(TOKENS_KEY, JSON.stringify(tokens))
}

function stored(): Tokens | null {
  try {
    const raw = localStorage.getItem(TOKENS_KEY)
    return raw ? (JSON.parse(raw) as Tokens) : null
  } catch {
    return null
  }
}

// One in-flight refresh at a time: a page issuing several commands at once would
// otherwise fire a refresh per command and race, with all but one losing.
let refreshing: Promise<string | null> | null = null

async function refresh(tokens: Tokens): Promise<string | null> {
  if (!config || !tokens.refreshToken) return null

  const res = await fetch(`${config.hostedUi}/oauth2/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "refresh_token",
      client_id: config.clientId,
      refresh_token: tokens.refreshToken,
    }),
  })
  if (!res.ok) {
    localStorage.removeItem(TOKENS_KEY)
    return null
  }

  const payload = await res.json()
  // A refresh response omits refresh_token — carry the existing one forward or
  // the next refresh has nothing to present.
  store({ ...payload, refresh_token: tokens.refreshToken })
  return payload.id_token
}

export async function idToken(): Promise<string | null> {
  const tokens = stored()
  if (!tokens) return null
  if (Date.now() < tokens.expiresAt) return tokens.idToken

  refreshing ??= refresh(tokens).finally(() => {
    refreshing = null
  })
  return await refreshing
}

// Read straight off the token rather than calling /oauth2/userInfo: the claims
// are already there, and the signature does not need checking here because the
// authorizer checks it on every request that matters.
export function identity(): Identity | null {
  const tokens = stored()
  if (!tokens) return null

  try {
    const claims = JSON.parse(atob(tokens.idToken.split(".")[1]))
    return { sub: claims.sub, name: claims.name || claims.email || claims.sub, email: claims.email }
  } catch {
    return null
  }
}

export function signOut(): void {
  localStorage.removeItem(TOKENS_KEY)
  if (!config) return

  const params = new URLSearchParams({ client_id: config.clientId, logout_uri: redirectUri() })
  location.assign(`${config.hostedUi}/logout?${params}`)
}
