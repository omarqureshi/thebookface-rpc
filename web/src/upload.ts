import { api } from "./api"
import type { UploadedMedia } from "./api/schema"

// Presign, then upload straight to the store. The bytes never pass through the
// API — uploads.presign only mints a target scoped to the caller's own prefix.
//
// Locally the "store" is the dev endpoint in config.ru; deployed it is S3. The
// browser code is identical, because a presigned S3 POST and the dev endpoint
// take the same multipart shape.
export async function uploadImage(file: File): Promise<UploadedMedia> {
  const presigned = await api.uploads.presign({ contentType: file.type })

  const form = new FormData()
  for (const [k, v] of Object.entries(presigned.fields)) form.append(k, v)
  form.append("file", file)

  const res = await fetch(presigned.url, { method: "POST", body: form })
  if (!res.ok) throw new Error(`upload failed: ${res.status}`)

  const { width, height } = await dimensions(file)
  return { key: presigned.key, contentType: file.type, width, height }
}

// Read the intrinsic size so the feed can reserve space and avoid reflow.
// Best-effort: a file the browser cannot decode still uploads fine.
function dimensions(file: File): Promise<{ width: number | null; height: number | null }> {
  return new Promise((resolve) => {
    const url = URL.createObjectURL(file)
    const img = new Image()
    img.onload = () => {
      URL.revokeObjectURL(url)
      resolve({ width: img.naturalWidth, height: img.naturalHeight })
    }
    img.onerror = () => {
      URL.revokeObjectURL(url)
      resolve({ width: null, height: null })
    }
    img.src = url
  })
}
