import { useCallback, useEffect, useState } from "react"
import { api, getUser, setUser, type DevUser } from "./api"
import { Feed } from "./components/Feed"
import { PostView } from "./components/PostView"
import { ProfilePage } from "./components/ProfilePage"
import { Avatar } from "./components/Avatar"

// Local personas. There is no Cognito locally, so identity is a header — see
// bookface-rpc DESIGN.md §3. Deployed, this whole block becomes a redirect to
// the hosted UI and a bearer token.
const PERSONAS: DevUser[] = [
  { sub: "dev|ada", name: "Ada Lovelace" },
  { sub: "dev|grace", name: "Grace Hopper" },
]

type View = { name: "feed" } | { name: "post"; id: string } | { name: "profile" }

export default function App() {
  const [view, setView] = useState<View>({ name: "feed" })
  const [, force] = useState(0)
  const [shownName, setShownName] = useState<string | null>(null)
  const [avatarUrl, setAvatarUrl] = useState<string | null>(null)
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
      setShownName(p.shownName)
      setAvatarUrl(p.avatarUrl ?? null)
    })
  }, [])

  useEffect(loadProfile, [loadProfile])

  const signIn = (u: DevUser | null) => {
    setUser(u)
    setView({ name: "feed" })
    force((n) => n + 1)
    loadProfile()
  }

  return (
    <>
      <div className="topbar">
        <div className="topbar__inner">
          <button className="brand" onClick={() => setView({ name: "feed" })}>
            <span className="brand__mark">B</span>
            <span className="brand__word">bookface</span>
          </button>

          <span className="topbar__spacer" />

          {me ? (
            <>
              <button
                className="topbar__me"
                aria-label="My profile"
                onClick={() => setView({ name: "profile" })}
              >
                <Avatar name={shownName ?? me.name} url={avatarUrl} size="avatar--sm" />
                <span className="topbar__name" data-testid="signed-in">
                  Signed in as {shownName ?? me.name}
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
        {view.name === "feed" && <Feed onOpen={(id) => setView({ name: "post", id })} />}
        {view.name === "post" && <PostView id={view.id} onBack={() => setView({ name: "feed" })} />}
        {view.name === "profile" && (
          <ProfilePage onDone={() => setView({ name: "feed" })} onSaved={loadProfile} />
        )}
      </main>
    </>
  )
}
