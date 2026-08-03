import { useState } from "react"
import { api, getUser } from "../api"

// Must match Reaction::PALETTE on the server. A mismatch surfaces as a typed
// `unsupported_reaction` error rather than a silent no-op.
export const PALETTE = ["👍", "👎", "❤️", "😂", "😮", "😢", "😡"]

// Counts and palette are separate rows, as in the Rails view: a pill per
// non-zero emoji, then the palette of buttons. Toggling the last one off
// removes the pill entirely rather than showing a zero.
export function Reactions({
  postId,
  target,
  counts,
  mine,
  onChanged,
  testId,
}: {
  postId: string
  target: string
  counts: Record<string, number>
  mine: string | null
  onChanged: (counts: Record<string, number>, mine: string | null) => void
  testId?: string
}) {
  const [busy, setBusy] = useState(false)
  const signedIn = !!getUser()
  const shown = Object.entries(counts).filter(([, n]) => n > 0)

  async function toggle(emoji: string) {
    if (!signedIn || busy) return
    setBusy(true)
    try {
      const state = await api.reactions.toggle({ postId, target, emoji })
      onChanged(state.reactionCounts ?? {}, state.mine ?? null)
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="reactions" data-testid={testId ?? `reactions-${target}`}>
      {shown.length > 0 && (
        <div className="reactions__counts">
          {shown.map(([emoji, n]) => (
            <span key={emoji} className="reactions__count">
              {emoji} {n}
            </span>
          ))}
        </div>
      )}
      <div className="reactions__palette">
        {PALETTE.map((emoji) => (
          <button
            key={emoji}
            className={mine === emoji ? "reactions__btn reactions__btn--mine" : "reactions__btn"}
            onClick={() => toggle(emoji)}
            disabled={!signedIn || busy}
            aria-label={`React ${emoji}`}
            aria-pressed={mine === emoji}
          >
            {emoji}
          </button>
        ))}
      </div>
    </div>
  )
}
