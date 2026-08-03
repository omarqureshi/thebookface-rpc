import { useCallback, useEffect, useState } from "react"
import { api, getUser } from "../api"
import type { Comment } from "../api/types"
import { Reactions } from "./Reactions"
import { errorMessage } from "./Composer"
import { Avatar } from "./Avatar"
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
  const [counts, setCounts] = useState<any>(comment.reaction_counts ?? [])
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
      <Avatar name={comment.author?.name} url={comment.author?.avatar_url} size="avatar--sm" />

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
          <span className="comment__time">{timeAgo(comment.created_at)}</span>
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

// The thread, loaded on demand and rendered inside the post's footer — the
// equivalent of the Rails app's Turbo Frame, which swapped the "N comments"
// link for the thread in place rather than navigating.
//
// Two procedures across two services, issued together so the client coalesces
// them into one POST /rpc?batch=1. Deployed that single request fans out to two
// Lambdas; expanding a thread costs one round trip either way.
export function Thread({
  postId,
  onCountChanged,
}: {
  postId: string
  onCountChanged?: (n: number) => void
}) {
  const [comments, setComments] = useState<Comment[] | null>(null)
  const [mine, setMine] = useState<Record<string, string>>({})
  const [draft, setDraft] = useState("")
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(() => {
    Promise.all([api.comments.thread({ postId }), api.reactions.mine({ postId })]).then(
      ([t, m]) => {
        setComments(t)
        // A list of {target, emoji} pairs, for the same generator limitation.
        setMine(Object.fromEntries((m ?? []).map((r: any) => [r.target, r.emoji])))
        onCountChanged?.(t.length)
      },
    )
    // onCountChanged is a fresh closure each render; depending on it would
    // reload the thread forever.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [postId])

  useEffect(load, [load])

  async function comment() {
    if (!draft.trim()) return
    setError(null)
    try {
      await api.comments.create({ postId, body: draft, parentPath: null })
      setDraft("")
      load()
    } catch (e) {
      setError(errorMessage(e))
    }
  }

  if (!comments) return <p className="empty">Loading…</p>

  return (
    <>
      <div className="thread__list">
        {comments.map((c) => (
          <CommentNode key={c.path} comment={c} postId={postId} mine={mine} onChanged={load} />
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
    </>
  )
}
