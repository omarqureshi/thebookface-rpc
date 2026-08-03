import { useEffect, useState } from "react"
import { api } from "../api"
import type { Profile } from "../api/schema"
import { uploadImage } from "../upload"
import { errorMessage } from "./Composer"

export function ProfilePage({ onDone, onSaved }: { onDone: () => void; onSaved?: () => void }) {
  const [profile, setProfile] = useState<Profile | null>(null)
  const [displayName, setDisplayName] = useState("")
  const [bio, setBio] = useState("")
  const [avatarKey, setAvatarKey] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [saved, setSaved] = useState(false)

  useEffect(() => {
    api.profiles.get({}).then((p) => {
      setProfile(p)
      setDisplayName(p.displayName ?? "")
      setBio(p.bio ?? "")
      setAvatarKey(p.avatarKey ?? null)
    })
  }, [])

  async function attach(file: File | undefined) {
    if (!file) return
    setError(null)
    try {
      // Same presign flow as post images. The server only honours a key under
      // the caller's own prefix, so a key from elsewhere is silently ignored
      // rather than trusted.
      const media = await uploadImage(file)
      setAvatarKey(media.key)
    } catch (e) {
      setError(errorMessage(e))
    }
  }

  async function save() {
    setError(null)
    setSaved(false)
    try {
      const updated = await api.profiles.update({
        displayName: displayName || null,
        bio: bio || null,
        avatarKey,
      })
      setProfile(updated)
      setAvatarKey(updated.avatarKey ?? null)
      setSaved(true)
      onSaved?.()
    } catch (e) {
      setError(errorMessage(e))
    }
  }

  if (!profile) return <p className="muted">Loading…</p>

  return (
    <div data-testid="profile">
      <button className="link" onClick={onDone}>
        ← back
      </button>

      <article className="card">
        <div className="byline">
          {profile.avatarUrl && (
            <img className="avatar large" src={profile.avatarUrl} alt="" data-testid="profile-avatar" />
          )}
          {/* shown_name is computed server-side, so every client agrees on the
              fallback from display name to identity-provider name. */}
          <h2>{profile.shownName}</h2>
        </div>
        {profile.bio && <p>{profile.bio}</p>}
      </article>

      <div className="card composer">
        <label>
          Display name
          <input
            aria-label="Display name"
            value={displayName}
            onChange={(e) => setDisplayName(e.target.value)}
          />
        </label>
        <label>
          Bio
          <textarea aria-label="Bio" value={bio} onChange={(e) => setBio(e.target.value)} />
        </label>
        <label>
          Photo
          <input
            type="file"
            accept="image/*"
            aria-label="Profile photo"
            onChange={(e) => attach(e.target.files?.[0])}
          />
        </label>
        <div className="row">
          <button onClick={save}>Save profile</button>
          {saved && <span className="muted">Profile saved.</span>}
          {error && (
            <span className="error" role="alert">
              {error}
            </span>
          )}
        </div>
      </div>
    </div>
  )
}
