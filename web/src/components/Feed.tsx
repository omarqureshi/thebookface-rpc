import { useCallback, useEffect, useState } from "react"
import { api } from "../api"
import type { Post } from "../api/schema"
import { Composer, errorMessage } from "./Composer"
import { getUser } from "../api"

function Media({ post }: { post: Post }) {
  if (!post.media?.length) return null
  return (
    <div className="media">
      {post.media.map((m) => (
        // The server sends the URL; the client never builds one from a key.
        <img key={m.key} src={m.url} alt="" width={m.width ?? undefined} height={m.height ?? undefined} />
      ))}
    </div>
  )
}

function PostCard({
  post,
  onOpen,
  onChanged,
}: {
  post: Post
  onOpen: (id: string) => void
  onChanged: () => void
}) {
  const [editing, setEditing] = useState(false)
  const [draft, setDraft] = useState(post.body ?? "")
  const [error, setError] = useState<string | null>(null)

  async function save() {
    try {
      await api.posts.update({ id: post.id, body: draft })
      setEditing(false)
      onChanged()
    } catch (e) {
      setError(errorMessage(e))
    }
  }

  async function destroy() {
    try {
      await api.posts.destroy({ id: post.id })
      onChanged()
    } catch (e) {
      setError(errorMessage(e))
    }
  }

  return (
    <article className="card" data-testid="post">
      <div className="byline">
        {post.author.avatarUrl && <img className="avatar" src={post.author.avatarUrl} alt="" />}
        <strong>{post.author.name}</strong>
        <time>{new Date(post.createdAt).toLocaleString()}</time>
      </div>

      {editing ? (
        <div className="composer">
          <textarea aria-label="Edit post" value={draft} onChange={(e) => setDraft(e.target.value)} />
          <div className="row">
            <button onClick={save}>Save</button>
            <button className="link" onClick={() => setEditing(false)}>
              Cancel
            </button>
          </div>
        </div>
      ) : (
        <>
          <p>{post.body}</p>
          <Media post={post} />
        </>
      )}

      <div className="row">
        {/* A test id rather than the label, which changes with the count. */}
        <button className="link" data-testid="open-comments" onClick={() => onOpen(post.id)}>
          {post.commentCount} {post.commentCount === 1 ? "comment" : "comments"}
        </button>
        <span className="muted">
          {Object.entries(post.reactionCounts ?? {})
            .map(([e, n]) => `${e}${n}`)
            .join("  ")}
        </span>
        {/* Server-computed, so Ability is never reimplemented here. */}
        {post.editable && !editing && (
          <button className="link" onClick={() => setEditing(true)}>
            Edit
          </button>
        )}
        {post.deletable && (
          <button className="link" onClick={destroy}>
            Delete
          </button>
        )}
        {error && (
          <span className="error" role="alert">
            {error}
          </span>
        )}
      </div>
    </article>
  )
}

export function Feed({ onOpen }: { onOpen: (id: string) => void }) {
  const [posts, setPosts] = useState<Post[]>([])
  const [cursor, setCursor] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)

  const load = useCallback(() => {
    setLoading(true)
    api.posts
      .feed({ limit: 25 })
      .then((page) => {
        setPosts(page.posts)
        setCursor(page.nextCursor ?? null)
      })
      .finally(() => setLoading(false))
  }, [])

  useEffect(load, [load])

  async function more() {
    if (!cursor) return
    const page = await api.posts.feed({ limit: 25, cursor })
    setPosts((p) => [...p, ...page.posts])
    setCursor(page.nextCursor ?? null)
  }

  return (
    <>
      {getUser() ? <Composer onPosted={load} /> : <p className="muted">Sign in to post.</p>}
      {loading && <p className="muted">Loading…</p>}
      {!loading && posts.length === 0 && <p className="muted">Nothing here yet.</p>}
      {posts.map((p) => (
        <PostCard key={p.id} post={p} onOpen={onOpen} onChanged={load} />
      ))}
      {cursor && (
        <button className="link" onClick={more}>
          Load more
        </button>
      )}
    </>
  )
}
