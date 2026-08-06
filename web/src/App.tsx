import { useCallback, useEffect, useState } from "react"
import { api, getUser, setUser, type DevUser } from "./api"
import { Feed } from "./components/Feed"
import { ProfilePage } from "./components/ProfilePage"
import { Avatar } from "./components/Avatar"
import { GoogleSignInButton } from "./components/GoogleSignInButton"
import { useRoute } from "./router"
import { authConfig, signIn as cognitoSignIn, signOut as cognitoSignOut } from "./auth"

// Local personas, used only when the app is running without a deployed
// config.json. Deployed, the same block becomes a redirect to the Cognito
// hosted UI and a bearer token — see src/auth.ts.
const PERSONAS: DevUser[] = [
  { sub: "dev|ada", name: "Ada Lovelace" },
  { sub: "dev|grace", name: "Grace Hopper" },
]

export default function App() {
  const [route, navigate] = useRoute()
  const [, force] = useState(0)
  const [shown_name, setShownName] = useState<string | null>(null)
  const [avatar_url, setAvatarUrl] = useState<string | null>(null)
  const me = getUser()

  // The name to greet you by is the profile's, not the persona's — otherwise
  // setting a display name changes nothing outside the profile page.
  const loadProfile = useCallback(() => {
    if (!getUser()) {
      setShownName(null)
      setAvatarUrl(null)
      return
    }
    api.profiles.get({}).then((p) => {
      setShownName(p.shown_name)
      setAvatarUrl(p.avatar_url ?? null)
    })
  }, [])

  useEffect(loadProfile, [loadProfile])

  const signInAs = (u: DevUser | null) => {
    setUser(u)
    navigate({ name: "feed" })
    force((n) => n + 1)
    loadProfile()
  }

  // Deployed, logging out has to end the Cognito session too — clearing the
  // token locally would leave the hosted UI signing you straight back in.
  const cognito = authConfig()
  const logOut = () => (cognito ? cognitoSignOut() : signInAs(null))

  return (
    <>
      <div className="topbar">
        <div className="topbar__inner">
          <button className="brand" onClick={() => navigate({ name: "feed" })}>
            <span className="brand__mark">B</span>
            <span className="brand__word">bookface</span>
          </button>

          <span className="topbar__spacer" />

          {me ? (
            <>
              <button
                className="topbar__me"
                aria-label="My profile"
                onClick={() => navigate({ name: "profile" })}
              >
                <Avatar name={shown_name ?? me.name} url={avatar_url} size="avatar--sm" />
                <span className="topbar__name" data-testid="signed-in">
                  Signed in as {shown_name ?? me.name}
                </span>
              </button>
              <button className="btn btn--ghost btn--sm" onClick={logOut}>
                Log out
              </button>
            </>
          ) : (
            <div className="signin">
              {cognito ? (
                <GoogleSignInButton onClick={() => void cognitoSignIn()} />
              ) : (
                <>
                  <span className="signin__label">Sign in as</span>
                  {PERSONAS.map((p) => (
                    <button
                      key={p.sub}
                      className="btn btn--dev btn--sm"
                      onClick={() => signInAs(p)}
                    >
                      {p.name}
                    </button>
                  ))}
                </>
              )}
            </div>
          )}
        </div>
      </div>

      <main className="page">
        {route.name === "profile" ? (
          <ProfilePage onDone={() => navigate({ name: "feed" })} onSaved={loadProfile} />
        ) : (
          <Feed route={route} navigate={navigate} />
        )}
      </main>
    </>
  )
}
