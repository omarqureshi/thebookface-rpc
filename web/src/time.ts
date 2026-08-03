// "3 minutes ago" — the equivalent of Rails' time_ago_in_words, which is what
// the original feed showed rather than an absolute timestamp.
const UNITS: [Intl.RelativeTimeFormatUnit, number][] = [
  ["year", 31_536_000],
  ["month", 2_592_000],
  ["day", 86_400],
  ["hour", 3_600],
  ["minute", 60],
]

export function timeAgo(iso: string): string {
  const seconds = Math.max(1, Math.floor((Date.now() - new Date(iso).getTime()) / 1000))
  for (const [unit, size] of UNITS) {
    if (seconds >= size) {
      const n = Math.floor(seconds / size)
      return `${n} ${unit}${n === 1 ? "" : "s"} ago`
    }
  }
  return "less than a minute ago"
}
