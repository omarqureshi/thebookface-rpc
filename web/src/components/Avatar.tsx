// Initials in a blue gradient disc, or the photo when there is one — the same
// treatment as the Rails app's avatar helper, which computed initials in Ruby.
export function initialsOf(name: string | null | undefined): string {
  const parts = (name ?? "").split(/\s+/).filter(Boolean)
  if (parts.length === 0) return "?"

  // First and last, not the first two: a middle name should not displace the
  // family name, so "Omar Ali Qureshi" is OQ. One name stays one letter.
  const chosen = parts.length === 1 ? [parts[0]] : [parts[0], parts[parts.length - 1]]
  return chosen.map((p) => p[0]).join("").toUpperCase()
}

export function Avatar({
  name,
  url,
  size = "",
  testId,
}: {
  name?: string | null
  url?: string | null
  /** "" | "avatar--sm" | "avatar--lg" */
  size?: string
  testId?: string
}) {
  const classes = ["avatar", size, url ? "avatar--photo" : "", name ? "" : "avatar--ghost"]
    .filter(Boolean)
    .join(" ")

  return (
    <span
      className={classes}
      data-testid={testId}
      style={url ? { backgroundImage: `url(${url})` } : undefined}
      aria-hidden="true"
    >
      {initialsOf(name)}
    </span>
  )
}
