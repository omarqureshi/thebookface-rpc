import { useCallback, useEffect, useState } from "react"
import { api, getUser } from "../api"
import type { Comment, Post } from "../api/schema"
import { Reactions } from "./Reactions"
import { errorMessage } from "./Composer"
import { Avatar } from "./Avatar"
import { Byline, Media } from "./Feed"
import { timeAgo } from "../time"

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
    // Flat list, indented through the --indent custom property the CSS reads.
    // The materialized path already arrives in pre-order, so no recursion is
    // needed to render the tree.
    <div
      className="comment"
      data-testid="comment"
      data-depth={comment.depth}
      style={{ ["--indent" as any]: comment.depth }}
    >
      <Avatar name={comment.author?.name} url={comment.author?.avatarUrl} size="avatar--sm" />

      <div className="comment__body">
        {error && (
          <div className="field-errors" role="alert">
            {error}
          </div>
        )}

        {comment.deleted ? (
          <div className="comment__bubble comment__bubble--deleted">[comment deleted]</div>
        ) : editing ? (
          <>
            <textarea
              className="comment-form__input"
              aria-label="Edit comment"
              value={draft}
              onChange={(e) => setDraft(e.target.value)}
            />
            <div className="composer__actions">
              <button className="btn btn--ghost btn--sm" onClick={() => setEditing(false)}>
                Cancel
              </button>
              <button
                className="btn btn--primary btn--sm"
                onClick={() =>
                  act(() => api.comments.update({ postId, path: comment.path, body: draft }))
                }
              >
                Save
              </button>
            </div>
          </>
        ) : (
          <div className="comment__bubble">
            <div className="comment__author">{comment.author?.name}</div>
            <div className="comment__text">
              <p>{comment.body}</p>
            </div>
          </div>
        )}

        <div className="comment__meta">
          <span className="comment__time">{timeAgo(comment.createdAt)}</span>
          {getUser() && !comment.deleted && (
            <button className="comment__action" onClick={() => setReplying((r) => !r)}>
              Reply
            </button>
          )}
          {comment.editable && !comment.deleted && (
            <button
              className="comment__action"
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
              className="comment__action comment__action--danger"
              onClick={() => act(() => api.comments.destroy({ postId, path: comment.path }))}
            >
              Delete
            </button>
          )}
        </div>

        <Reactions
          postId={postId}
          target={target}
          counts={counts}
          mine={mine[target] ?? null}
          onChanged={(c) => setCounts(c)}
        />

        {replying && (
          <div className="comment-form">
            <textarea
              className="comment-form__input"
              data-testid="reply-box"
              aria-label="Reply"
              value={draft}
              onChange={(e) => setDraft(e.target.value)}
            />
            <div className="composer__actions">
              <button
                className="btn btn--primary btn--sm"
                data-testid="submit-reply"
                onClick={() =>
                  act(() => api.comments.create({ postId, body: draft, parentPath: comment.path }))
                }
              >
                Reply
              </button>
            </div>
          </div>
        )}
      </div>
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

  if (missing) return <p className="empty">That post no longer exists.</p>
  if (!post) return <p className="empty">Loading…</p>

  return (
    <div className="feed">
      <button className="backlink" onClick={onBack}>
        ← Back to feed
      </button>

      <article className="card post" data-testid="post">
        <Byline post={post} />
        <div className="post__body">
          <p>{post.body}</p>
        </div>
        <Media post={post} />
        <Reactions
          postId={id}
          target="post"
          counts={post.reactionCounts ?? {}}
          mine={mine["post"] ?? null}
          onChanged={(counts) => setPost({ ...post, reactionCounts: counts })}
        />

        <div className="post__foot">
          <h2 className="thread__title" data-testid="comment-count">
            {thread.length} {thread.length === 1 ? "comment" : "comments"}
          </h2>

          <div className="thread__list">
            {thread.map((c) => (
              <CommentNode key={c.path} comment={c} postId={id} mine={mine} onChanged={load} />
            ))}
          </div>

          {getUser() && (
            <div className="comment-form">
              {error && (
                <div className="field-errors" role="alert">
                  {error}
                </div>
              )}
              <textarea
                className="comment-form__input"
                aria-label="Add a comment"
                placeholder="Write a comment…"
                value={draft}
                onChange={(e) => setDraft(e.target.value)}
              />
              <div className="composer__actions">
                <button className="btn btn--primary btn--sm" onClick={comment}>
                  Comment
                </button>
              </div>
            </div>
          )}
        </div>
      </article>
    </div>
  )
}
