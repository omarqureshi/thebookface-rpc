import { useCallback, useEffect, useState } from "react"
import { api, getUser } from "../api"
import type { Comment, Post } from "../api/schema"
import { Reactions } from "./Reactions"
import { errorMessage } from "./Composer"

function CommentNode({
  comment,
  postId,
  mine,
  onChanged,
}: {
  comment: Comment
  postId: string
  mine: Record<string, string>
  onChanged: () => void
}) {
  const [replying, setReplying] = useState(false)
  const [editing, setEditing] = useState(false)
  const [draft, setDraft] = useState("")
  const [error, setError] = useState<string | null>(null)
  const [counts, setCounts] = useState(comment.reactionCounts ?? {})
  const target = `comment#${comment.path}`

  async function act(fn: () => Promise<unknown>) {
    setError(null)
    try {
      await fn()
      setReplying(false)
      setEditing(false)
      setDraft("")
      onChanged()
    } catch (e) {
      setError(errorMessage(e))
    }
  }

  return (
    // Flat list, indented by depth — the materialized path already arrives in
    // pre-order, so no recursion is needed to render the tree.
    <div
      className="card comment"
      data-testid="comment"
      data-depth={comment.depth}
      style={{ marginLeft: comment.depth * 24 }}
    >
      {comment.deleted ? (
        <p className="muted">[comment deleted]</p>
      ) : editing ? (
        <div className="composer">
          <textarea aria-label="Edit comment" value={draft} onChange={(e) => setDraft(e.target.value)} />
          <div className="row">
            <button onClick={() => act(() => api.comments.update({ postId, path: comment.path, body: draft }))}>
              Save
            </button>
            <button className="link" onClick={() => setEditing(false)}>
              Cancel
            </button>
          </div>
        </div>
      ) : (
        <>
          <div className="byline">
            {comment.author?.avatarUrl && <img className="avatar" src={comment.author.avatarUrl} alt="" />}
            <strong>{comment.author?.name}</strong>
            <time>{new Date(comment.createdAt).toLocaleString()}</time>
          </div>
          <p>{comment.body}</p>
        </>
      )}

      <Reactions
        postId={postId}
        target={target}
        counts={counts}
        mine={mine[target] ?? null}
        onChanged={(c) => setCounts(c)}
      />

      <div className="row">
        {getUser() && !comment.deleted && (
          <button className="link" onClick={() => setReplying((r) => !r)}>
            Reply
          </button>
        )}
        {comment.editable && !comment.deleted && (
          <button
            className="link"
            onClick={() => {
              setDraft(comment.body ?? "")
              setEditing(true)
            }}
          >
            Edit
          </button>
        )}
        {comment.deletable && !comment.deleted && (
          <button
            className="link"
            onClick={() => act(() => api.comments.destroy({ postId, path: comment.path }))}
          >
            Delete
          </button>
        )}
        {error && (
          <span className="error" role="alert">
            {error}
          </span>
        )}
      </div>

      {replying && (
        <div className="composer">
          <textarea
            data-testid="reply-box"
            aria-label="Reply"
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
          />
          <button
            data-testid="submit-reply"
            onClick={() =>
              act(() => api.comments.create({ postId, body: draft, parentPath: comment.path }))
            }
          >
            Reply
          </button>
        </div>
      )}
    </div>
  )
}

export function PostView({ id, onBack }: { id: string; onBack: () => void }) {
  const [post, setPost] = useState<Post | null>(null)
  const [thread, setThread] = useState<Comment[]>([])
  const [mine, setMine] = useState<Record<string, string>>({})
  const [draft, setDraft] = useState("")
  const [error, setError] = useState<string | null>(null)
  const [missing, setMissing] = useState(false)

  // Three procedures across three services, issued together so the client
  // coalesces them into ONE POST /rpc?batch=1. Deployed, that single request
  // fans out to three Lambdas.
  const load = useCallback(() => {
    Promise.all([
      api.posts.get({ id }),
      api.comments.thread({ postId: id }),
      api.reactions.mine({ postId: id }),
    ])
      .then(([p, t, m]) => {
        setPost(p)
        setThread(t.comments)
        setMine(m.byTarget ?? {})
      })
      .catch(() => setMissing(true))
  }, [id])

  useEffect(load, [load])

  async function comment() {
    if (!draft.trim()) return
    setError(null)
    try {
      await api.comments.create({ postId: id, body: draft, parentPath: null })
      setDraft("")
      load()
    } catch (e) {
      setError(errorMessage(e))
    }
  }

  if (missing) return <p className="muted">That post no longer exists.</p>
  if (!post) return <p className="muted">Loading…</p>

  return (
    <>
      <button className="link" onClick={onBack}>
        ← back
      </button>

      <article className="card" data-testid="post">
        <div className="byline">
          {post.author.avatarUrl && <img className="avatar" src={post.author.avatarUrl} alt="" />}
          <strong>{post.author.name}</strong>
          <time>{new Date(post.createdAt).toLocaleString()}</time>
        </div>
        <p>{post.body}</p>
        {post.media?.map((m) => (
          <img key={m.key} src={m.url} alt="" className="media" />
        ))}
        <Reactions
          postId={id}
          target="post"
          counts={post.reactionCounts ?? {}}
          mine={mine["post"] ?? null}
          onChanged={(counts) => setPost({ ...post, reactionCounts: counts })}
        />
        <p className="muted" data-testid="comment-count">
          {thread.length} {thread.length === 1 ? "comment" : "comments"}
        </p>
      </article>

      {getUser() && (
        <div className="card composer">
          <textarea
            aria-label="Add a comment"
            placeholder="Add a comment…"
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
          />
          <div className="row">
            <button onClick={comment}>Comment</button>
            {error && (
              <span className="error" role="alert">
                {error}
              </span>
            )}
          </div>
        </div>
      )}

      {thread.map((c) => (
        <CommentNode key={c.path} comment={c} postId={id} mine={mine} onChanged={load} />
      ))}
    </>
  )
}
