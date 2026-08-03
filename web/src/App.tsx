import { useCallback, useEffect, useState } from "react"
import { api, getUser, setUser, type DevUser } from "./api"
import { Feed } from "./components/Feed"
import { ProfilePage } from "./components/ProfilePage"
import { Avatar } from "./components/Avatar"
import { useRoute } from "./router"

// Local personas. There is no Cognito locally, so identity is a header — see
// bookface-rpc DESIGN.md §3. Deployed, this whole block becomes a redirect to
// the hosted UI and a bearer token.
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

  const signIn = (u: DevUser | null) => {
    setUser(u)
    navigate({ name: "feed" })
    force((n) => n + 1)
    loadProfile()
  }

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
              <button className="btn btn--ghost btn--sm" onClick={() => signIn(null)}>
                Log out
              </button>
            </>
          ) : (
            <div className="signin">
              <span className="signin__label">Sign in as</span>
              {PERSONAS.map((p) => (
                <button key={p.sub} className="btn btn--dev btn--sm" onClick={() => signIn(p)}>
                  {p.name}
                </button>
              ))}
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
