import { useState } from "react"
import { api, getUser } from "../api"

// Must match Reaction::PALETTE on the server. A mismatch surfaces as a typed
// `unsupported_reaction` error rather than a silent no-op, which is why the
// list can live here without drifting dangerously.
export const PALETTE = ["👍", "👎", "❤️", "😂", "😮", "😢", "😡"]

export function Reactions({
  postId,
  target,
  counts,
  mine,
  onChanged,
}: {
  postId: string
  target: string
  counts: Record<string, number>
  mine: string | null
  onChanged: (counts: Record<string, number>, mine: string | null) => void
}) {
  const [busy, setBusy] = useState(false)
  const signedIn = !!getUser()

  async function toggle(emoji: string) {
    if (!signedIn || busy) return
    setBusy(true)
    try {
      // One entry point for add / switch / remove, as on the server. The
      // response carries the fresh counts, so nothing is guessed client-side.
      const state = await api.reactions.toggle({ postId, target, emoji })
      onChanged(state.reactionCounts ?? {}, state.mine ?? null)
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="reactions" data-testid={`reactions-${target}`}>
      {PALETTE.map((emoji) => {
        const n = counts[emoji] ?? 0
        return (
          <button
            key={emoji}
            className={mine === emoji ? "chip mine" : "chip"}
            onClick={() => toggle(emoji)}
            disabled={!signedIn || busy}
            aria-label={`React ${emoji}`}
            aria-pressed={mine === emoji}
          >
            {emoji}
            {n > 0 && <span className="count"> {n}</span>}
          </button>
        )
      })}
    </div>
  )
}
