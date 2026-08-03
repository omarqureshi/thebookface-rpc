import { useCallback, useEffect, useState } from "react"

// A minimal history-API router. Deliberately not a routing library: there are
// four routes, and the point is that state which changes what you see should be
// in the URL — so it survives a reload, works with the back button, and can be
// linked to.
//
//   /                    the feed
//   /posts/:id           feed with that post's thread expanded
//   /posts/:id/edit      feed with that post in its edit form
//   /profile             your profile
//
// The paths mirror the Rails app's, so a link that worked there works here.
export type Route =
  | { name: "feed" }
  | { name: "post"; id: string }
  | { name: "editPost"; id: string }
  | { name: "profile" }

export function parseRoute(pathname: string): Route {
  const path = pathname.replace(/\/+$/, "") || "/"
  const post = path.match(/^\/posts\/([^/]+)(\/edit)?$/)
  if (post) return post[2] ? { name: "editPost", id: post[1] } : { name: "post", id: post[1] }
  if (path === "/profile") return { name: "profile" }
  return { name: "feed" }
}

export function routePath(route: Route): string {
  switch (route.name) {
    case "post":
      return `/posts/${route.id}`
    case "editPost":
      return `/posts/${route.id}/edit`
    case "profile":
      return "/profile"
    default:
      return "/"
  }
}

export function useRoute() {
  const [route, setRoute] = useState<Route>(() => parseRoute(window.location.pathname))

  // Back and forward must work, which is the whole reason for pushState rather
  // than component state.
  useEffect(() => {
    const onPop = () => setRoute(parseRoute(window.location.pathname))
    window.addEventListener("popstate", onPop)
    return () => window.removeEventListener("popstate", onPop)
  }, [])

  const navigate = useCallback((next: Route, opts?: { replace?: boolean }) => {
    const path = routePath(next)
    if (path !== window.location.pathname) {
      if (opts?.replace) window.history.replaceState(null, "", path)
      else window.history.pushState(null, "", path)
    }
    setRoute(next)
  }, [])

  return [route, navigate] as const
}
