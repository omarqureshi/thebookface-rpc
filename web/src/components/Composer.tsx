import { useRef, useState } from "react"
import { api, RpcError, getUser } from "../api"
import { uploadImage } from "../upload"
import { Avatar } from "./Avatar"
import type { UploadedMedia } from "../api/types"

// Turns a typed contract error into something a person can read. Errors are a
// discriminated union in the generated types, so this is exhaustive by
// construction rather than by hope.
export function errorMessage(e: unknown): string {
  if (!(e instanceof RpcError)) return String(e)
  const d = e.detail as any
  switch (d.code) {
    case "validation_failed":
      return Object.values(d.errors ?? {}).flat().join(", ")
    case "invalid_input":
      return Object.entries(d.errors ?? {})
        .map(([f, m]) => `${f} ${m}`)
        .join(", ")
    case "forbidden":
      return "You can only edit or delete your own posts and comments."
    case "not_found":
      return "That no longer exists."
    case "unsupported_media_type":
      return "That file type isn't supported."
    case "unauthorized":
      return "Please sign in to do that."
    default:
      return d.code
  }
}

export function Composer({ onPosted }: { onPosted: () => void }) {
  const [body, setBody] = useState("")
  const [media, setMedia] = useState<UploadedMedia[]>([])
  const [uploading, setUploading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const fileInput = useRef<HTMLInputElement>(null)
  const me = getUser()

  async function attach(file: File | undefined) {
    if (!file) return
    setUploading(true)
    setError(null)
    try {
      const uploaded = await uploadImage(file)
      setMedia((m) => [...m, uploaded])
    } catch (e) {
      setError(errorMessage(e))
    } finally {
      setUploading(false)
    }
  }

  async function submit() {
    setBusy(true)
    setError(null)
    try {
      await api.posts.create({ body: body || null, media })
      setBody("")
      setMedia([])
      if (fileInput.current) fileInput.current.value = ""
      onPosted()
    } catch (e) {
      setError(errorMessage(e))
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="card composer" data-testid="composer">
      {error && (
        <div className="field-errors" role="alert">
          {error}
        </div>
      )}

      <div className="composer__row">
        <Avatar name={me?.name} />
        <textarea
          className="composer__input"
          rows={2}
          value={body}
          aria-label="What's on your mind?"
          placeholder={`What's on your mind${me ? `, ${me.name.split(" ")[0]}` : ""}?`}
          onChange={(e) => setBody(e.target.value)}
        />
      </div>

      <div className="composer__previews">
        {media.map((m) => (
          <span key={m.key} className="upload-tile" data-testid="attached-count" />
        ))}
        {uploading && <span className="upload-tile is-loading" />}
      </div>

      <div className="composer__actions">
        <input
          ref={fileInput}
          type="file"
          accept="image/*"
          aria-label="Attach an image"
          onChange={(e) => attach(e.target.files?.[0])}
        />
        <button className="btn btn--primary" onClick={submit} disabled={busy || uploading}>
          {busy ? "Posting…" : "Post"}
        </button>
      </div>
    </div>
  )
}
