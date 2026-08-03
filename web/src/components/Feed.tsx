import { useCallback, useEffect, useState } from "react"
import { api, getUser } from "../api"
import type { Post } from "../api/schema"
import { Composer, errorMessage } from "./Composer"
import { Avatar } from "./Avatar"
import { Reactions } from "./Reactions"
import { Thread } from "./Thread"
import { timeAgo } from "../time"

// The grid class encodes how many images there are, exactly as the Rails
// partial did — one big, two side by side, three with a wide first.
export function Media({ post }: { post: Post }) {
  const items = post.media ?? []
  if (!items.length) return null
  return (
    <div className={`media media--${Math.min(items.length, 4)}`}>
      {items.map((m) => (
        // The server sends the URL; the client never builds one from a key.
        <span key={m.key} className="media__item">
          <img src={m.url} alt="" />
        </span>
      ))}
    </div>
  )
}

export function Byline({ post }: { post: Pick<Post, "author" | "createdAt"> }) {
  return (
    <div className="post__head">
      <Avatar name={post.author.name} url={post.author.avatarUrl} />
      <div>
        <div className="post__author">{post.author.name}</div>
        <div className="post__time">{timeAgo(post.createdAt)}</div>
      </div>
    </div>
  )
}

function PostCard({ post, onChanged }: { post: Post; onChanged: () => void }) {
  const [expanded, setExpanded] = useState(false)
  const [count, setCount] = useState(post.commentCount)
  const [editing, setEditing] = useState(false)
  const [draft, setDraft] = useState(post.body ?? "")
  const [counts, setCounts] = useState(post.reactionCounts ?? {})
  const [error, setError] = useState<string | null>(null)

  async function act(fn: () => Promise<unknown>) {
    setError(null)
    try {
      await fn()
      setEditing(false)
      onChanged()
    } catch (e) {
      setError(errorMessage(e))
    }
  }

  return (
    <article className="card post" data-testid="post">
      <Byline post={post} />

      {error && (
        <div className="field-errors" role="alert">
          {error}
        </div>
      )}

      {editing ? (
        <>
          <textarea
            className="composer__input"
            aria-label="Edit post"
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
          />
          <div className="composer__actions">
            <button className="btn btn--ghost btn--sm" onClick={() => setEditing(false)}>
              Cancel
            </button>
            <button
              className="btn btn--primary btn--sm"
              onClick={() => act(() => api.posts.update({ id: post.id, body: draft }))}
            >
              Save
            </button>
          </div>
        </>
      ) : (
        <>
          <div className="post__body">
            <p>{post.body}</p>
          </div>
          <Media post={post} />
        </>
      )}

      {/* React straight from the feed. `mine` stays null here, as in the Rails
          view — highlighting your own reaction is only computed on the post
          page, so the feed remains a single query. */}
      <Reactions
        postId={post.id}
        target="post"
        counts={counts}
        mine={null}
        onChanged={(c) => setCounts(c)}
      />

      <div className="post__foot">
        <div className="owner-actions owner-actions--inline">
          {/* Expands the thread in place rather than navigating, as the Rails
              view's Turbo Frame did. */}
          <button
            className="post__comments-link"
            data-testid="open-comments"
            aria-expanded={expanded}
            onClick={() => setExpanded((e) => !e)}
          >
            {count} {count === 1 ? "comment" : "comments"}
          </button>
          {/* Server-computed, so Ability is never reimplemented here. */}
          {post.editable && !editing && (
            <button className="owner-actions__link" onClick={() => setEditing(true)}>
              Edit
            </button>
          )}
          {post.deletable && (
            <button
              className="owner-actions__link owner-actions__link--danger"
              onClick={() => act(() => api.posts.destroy({ id: post.id }))}
            >
              Delete
            </button>
          )}
        </div>

        {expanded && (
          <Thread
            postId={post.id}
            onCountChanged={(n) => setCount(n)}
          />
        )}
      </div>
    </article>
  )
}

export function Feed() {
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
    <div className="feed">
      {getUser() ? (
        <Composer onPosted={load} />
      ) : (
        <div className="card">
          <p className="muted">Sign in to post.</p>
        </div>
      )}
      {loading && <p className="empty">Loading…</p>}
      {!loading && posts.length === 0 && <p className="empty">Nothing here yet.</p>}
      {posts.map((p) => (
        <PostCard key={p.id} post={p} onChanged={load} />
      ))}
      {cursor && (
        <button className="btn btn--ghost" onClick={more}>
          Load more
        </button>
      )}
    </div>
  )
}
