import { useCallback, useEffect, useState } from "react"
import { api, getUser, setUser, type DevUser } from "./api"
import { Feed } from "./components/Feed"
import { PostView } from "./components/PostView"
import { ProfilePage } from "./components/ProfilePage"

// Local personas. There is no Cognito locally, so identity is a header — see
// bookface-rpc DESIGN.md §3. Deployed, this whole block is replaced by a
// redirect to the hosted UI and a bearer token.
const PERSONAS: DevUser[] = [
  { sub: "dev|ada", name: "Ada Lovelace" },
  { sub: "dev|grace", name: "Grace Hopper" },
]

type View = { name: "feed" } | { name: "post"; id: string } | { name: "profile" }

export default function App() {
  const [view, setView] = useState<View>({ name: "feed" })
  const [, force] = useState(0)
  const [shownName, setShownName] = useState<string | null>(null)
  const me = getUser()

  // The name to greet you by is the profile's, not the persona's — otherwise
  // setting a display name changes nothing outside the profile page.
  const loadProfile = useCallback(() => {
    if (!getUser()) return setShownName(null)
    api.profiles.get({}).then((p) => setShownName(p.shownName))
  }, [])

  useEffect(loadProfile, [loadProfile])

  const signIn = (u: DevUser | null) => {
    setUser(u)
    setView({ name: "feed" })
    force((n) => n + 1)
    loadProfile()
  }

  return (
    <main>
      <header>
        <h1>
          <button className="link plain" onClick={() => setView({ name: "feed" })}>
            The Bookface
          </button>
        </h1>

        <div className="row">
          {me ? (
            <>
              <span data-testid="signed-in">Signed in as {shownName ?? me.name}</span>
              <button className="link" onClick={() => setView({ name: "profile" })}>
                My profile
              </button>
              <button className="link" onClick={() => signIn(null)}>
                Log out
              </button>
            </>
          ) : (
            PERSONAS.map((p) => (
              <button key={p.sub} className="chip" onClick={() => signIn(p)}>
                {p.name}
              </button>
            ))
          )}
        </div>
      </header>

      {view.name === "feed" && <Feed onOpen={(id) => setView({ name: "post", id })} />}
      {view.name === "post" && (
        <PostView id={view.id} onBack={() => setView({ name: "feed" })} />
      )}
      {view.name === "profile" && (
        <ProfilePage
          onDone={() => setView({ name: "feed" })}
          onSaved={loadProfile}
        />
      )}
    </main>
  )
}
