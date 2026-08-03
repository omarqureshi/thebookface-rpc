// Initials in a blue gradient disc, or the photo when there is one — the same
// treatment as the Rails app's avatar helper, which computed initials in Ruby.
export function initialsOf(name: string | null | undefined): string {
  const parts = (name ?? "").split(/\s+/).filter(Boolean)
  return parts.slice(0, 2).map((p) => p[0]).join("").toUpperCase() || "?"
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
