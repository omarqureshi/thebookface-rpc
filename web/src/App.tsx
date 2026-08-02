import { useCallback, useEffect, useState } from "react"
import { api, getUser, setUser, RpcError } from "./api"
import type { Post, Comment } from "./api/schema"

const PALETTE = ["👍", "👎", "❤️", "😂", "😮", "😢", "😡"]

const USERS = [
  { sub: "user-alice", name: "Alice" },
  { sub: "user-bob", name: "Bob" },
]

// --- shared bits ------------------------------------------------------------

function Reactions({
  counts,
  mine,
  onToggle,
}: {
  counts: Record<string, number>
  mine: string | null
  onToggle: (emoji: string) => void
}) {
  return (
    <div className="reactions">
      {PALETTE.map((e) => {
        const n = counts[e] ?? 0
        return (
          <button
            key={e}
            className={mine === e ? "chip mine" : "chip"}
            onClick={() => onToggle(e)}
            title={e}
          >
            {e}
            {n > 0 && <span className="count">{n}</span>}
          </button>
        )
      })}
    </div>
  )
}

function Byline({ post }: { post: Pick<Post, "author" | "createdAt"> }) {
  return (
    <div className="byline">
      <strong>{post.author.name}</strong>
      <time>{new Date(post.createdAt).toLocaleString()}</time>
    </div>
  )
}

// --- feed -------------------------------------------------------------------

function Composer({ onPosted }: { onPosted: () => void }) {
  const [body, setBody] = useState("")
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  async function submit() {
    setBusy(true)
    setError(null)
    try {
      await api.posts.create({ body })
      setBody("")
      onPosted()
    } catch (e) {
      // Typed errors from the contract — a discriminated union, not a redirect.
      if (e instanceof RpcError) {
        setError(
          e.detail.code === "validation_failed"
            ? Object.values((e.detail as any).errors).flat().join(", ")
            : e.detail.code,
        )
      } else setError(String(e))
    } finally {
      setBusy(false)
    }
  }

  if (!getUser()) return <p className="muted">Pick a user above to post.</p>

  return (
    <div className="card composer">
      <textarea
        value={body}
        placeholder="What's on your mind?"
        onChange={(e) => setBody(e.target.value)}
      />
      <div className="row">
        <button onClick={submit} disabled={busy}>
          {busy ? "Posting…" : "Post"}
        </button>
        {error && <span className="error">{error}</span>}
      </div>
    </div>
  )
}

function Feed({ onOpen }: { onOpen: (id: string) => void }) {
  const [posts, setPosts] = useState<Post[]>([])
  const [loading, setLoading] = useState(true)

  const load = useCallback(() => {
    setLoading(true)
    api.posts
      .feed({ limit: 25 })
      .then((page) => setPosts(page.posts))
      .finally(() => setLoading(false))
  }, [])

  useEffect(load, [load])

  return (
    <>
      <Composer onPosted={load} />
      {loading && <p className="muted">Loading…</p>}
      {!loading && posts.length === 0 && <p className="muted">Nothing here yet.</p>}
      {posts.map((p) => (
        <article key={p.id} className="card">
          <Byline post={p} />
          <p>{p.body}</p>
          <div className="row">
            <button className="link" onClick={() => onOpen(p.id)}>
              {p.commentCount} {p.commentCount === 1 ? "comment" : "comments"}
            </button>
            <span className="muted">
              {Object.entries(p.reactionCounts ?? {})
                .map(([e, n]) => `${e}${n}`)
                .join("  ")}
            </span>
          </div>
        </article>
      ))}
    </>
  )
}

// --- post view --------------------------------------------------------------

function PostView({ id, onBack }: { id: string; onBack: () => void }) {
  const [post, setPost] = useState<Post | null>(null)
  const [thread, setThread] = useState<Comment[]>([])
  const [mine, setMine] = useState<Record<string, string>>({})
  const [reply, setReply] = useState("")

  // Three procedures across three services. Because they're issued together,
  // the client coalesces them into ONE POST /rpc?batch=1 — a single round trip.
  // Deployed, that one request fans out to three Lambdas.
  const load = useCallback(() => {
    Promise.all([
      api.posts.get({ id }),
      api.comments.thread({ postId: id }),
      api.reactions.mine({ postId: id }),
    ]).then(([p, t, m]) => {
      setPost(p)
      setThread(t.comments)
      setMine(m.byTarget ?? {})
    })
  }, [id])

  useEffect(load, [load])

  async function toggle(target: string, emoji: string) {
    if (!getUser()) return
    await api.reactions.toggle({ postId: id, target, emoji })
    load()
  }

  async function addComment(parentPath: string | null) {
    if (!reply.trim()) return
    await api.comments.create({ postId: id, body: reply, parentPath })
    setReply("")
    load()
  }

  if (!post) return <p className="muted">Loading…</p>

  return (
    <>
      <button className="link" onClick={onBack}>
        ← back
      </button>
      <article className="card">
        <Byline post={post} />
        <p>{post.body}</p>
        <Reactions
          counts={post.reactionCounts ?? {}}
          mine={mine["post"] ?? null}
          onToggle={(e) => toggle("post", e)}
        />
      </article>

      {getUser() && (
        <div className="card composer">
          <textarea
            value={reply}
            placeholder="Add a comment…"
            onChange={(e) => setReply(e.target.value)}
          />
          <button onClick={() => addComment(null)}>Comment</button>
        </div>
      )}

      {/* The thread is flat with a depth field — the materialized path already
          renders in pre-order, so indentation is one pass and no recursion. */}
      {thread.map((c) => (
        <div key={c.path} className="card comment" style={{ marginLeft: c.depth * 24 }}>
          {c.deleted ? (
            <p className="muted">[deleted]</p>
          ) : (
            <>
              <div className="byline">
                <strong>{c.author?.name}</strong>
                <time>{new Date(c.createdAt).toLocaleString()}</time>
              </div>
              <p>{c.body}</p>
            </>
          )}
          <Reactions
            counts={c.reactionCounts ?? {}}
            mine={mine[`comment#${c.path}`] ?? null}
            onToggle={(e) => toggle(`comment#${c.path}`, e)}
          />
          {getUser() && (
            <button className="link" onClick={() => addComment(c.path)}>
              reply
            </button>
          )}
        </div>
      ))}
    </>
  )
}

// --- shell ------------------------------------------------------------------

export default function App() {
  const [openId, setOpenId] = useState<string | null>(null)
  const [, force] = useState(0)

  return (
    <main>
      <header>
        <h1>The Bookface</h1>
        <div className="row">
          {USERS.map((u) => (
            <button
              key={u.sub}
              className={getUser()?.sub === u.sub ? "chip mine" : "chip"}
              onClick={() => {
                setUser(u)
                force((n) => n + 1)
              }}
            >
              {u.name}
            </button>
          ))}
          <button
            className="chip"
            onClick={() => {
              setUser(null)
              force((n) => n + 1)
            }}
          >
            sign out
          </button>
        </div>
      </header>
      {openId ? <PostView id={openId} onBack={() => setOpenId(null)} /> : <Feed onOpen={setOpenId} />}
    </main>
  )
}
