import { useEffect, useState } from "react"
import { api } from "../api"
import type { Profile } from "../api/types"
import { uploadImage } from "../upload"
import { errorMessage } from "./Composer"
import { Avatar } from "./Avatar"

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
      setDisplayName(p.display_name ?? "")
      setBio(p.bio ?? "")
      setAvatarKey(p.avatar_key ?? null)
    })
  }, [])

  async function attach(file: File | undefined) {
    if (!file) return
    setError(null)
    try {
      // Same presign flow as post images. The server only honours a key under
      // the caller's own prefix, so a key from elsewhere is ignored rather
      // than trusted.
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
      setAvatarKey(updated.avatar_key ?? null)
      setSaved(true)
      onSaved?.()
    } catch (e) {
      setError(errorMessage(e))
    }
  }

  if (!profile) return <p className="empty">Loading…</p>

  return (
    <div className="feed" data-testid="profile">
      <button className="backlink" onClick={onDone}>
        ← Back to feed
      </button>

      <article className="card">
        <div className="profile__head">
          <Avatar
            name={profile.shown_name}
            url={profile.avatar_url}
            size="avatar--lg"
            testId={profile.avatar_url ? "profile-avatar" : undefined}
          />
          {/* shown_name is computed server-side, so every client agrees on the
              fallback from display name to identity-provider name. */}
          <h1 className="profile__name">{profile.shown_name}</h1>
        </div>
        {profile.bio && <p className="profile__bio">{profile.bio}</p>}
      </article>

      <div className="card">
        {saved && <div className="flash flash--notice">Profile saved.</div>}
        {error && (
          <div className="field-errors" role="alert">
            {error}
          </div>
        )}

        <label className="field">
          <span className="field__label">Display name</span>
          <input
            className="field__input"
            aria-label="Display name"
            value={displayName}
            onChange={(e) => setDisplayName(e.target.value)}
          />
        </label>

        <label className="field">
          <span className="field__label">Bio</span>
          <textarea
            className="field__input"
            aria-label="Bio"
            rows={3}
            value={bio}
            onChange={(e) => setBio(e.target.value)}
          />
        </label>

        <label className="field">
          <span className="field__label">Photo</span>
          <input
            type="file"
            accept="image/*"
            aria-label="Profile photo"
            onChange={(e) => attach(e.target.files?.[0])}
          />
        </label>

        <div className="composer__actions">
          <button className="btn btn--primary" onClick={save}>
            Save profile
          </button>
        </div>
      </div>
    </div>
  )
}
