// An adapter over Foobara's generated SDK.
//
// The generated commands are classes — `new ListPosts({limit}).run()` returning
// an Outcome. The React components were written against Prospect's
// `api.posts.feed({...})` shape, so this presents that shape and translates,
// rather than rewriting every component. What is underneath is entirely the
// generated SDK; no protocol is hand-written here.

import RemoteCommand from "../domains/base/RemoteCommand"
import { ListPosts } from "../domains/Posts/ListPosts"
import { GetPost } from "../domains/Posts/GetPost"
import { CreatePost } from "../domains/Posts/CreatePost"
import { UpdatePost } from "../domains/Posts/UpdatePost"
import { DestroyPost } from "../domains/Posts/DestroyPost"
import { ListThread } from "../domains/Comments/ListThread"
import { CreateComment } from "../domains/Comments/CreateComment"
import { UpdateComment } from "../domains/Comments/UpdateComment"
import { DestroyComment } from "../domains/Comments/DestroyComment"
import { MyReactions } from "../domains/Reactions/MyReactions"
import { ToggleReaction } from "../domains/Reactions/ToggleReaction"
import { GetProfile } from "../domains/Profiles/GetProfile"
import { UpdateProfile } from "../domains/Profiles/UpdateProfile"
import { Presign } from "../domains/Uploads/Presign"
import { authConfig, idToken, identity } from "../auth"

RemoteCommand.urlBase = ""

export interface DevUser {
  sub: string
  name: string
}

// Two identity schemes, chosen at runtime by whether the stack deployed a
// config.json — so one bundle serves both.
//
//   deployed: a Cognito id token as a bearer, verified by the Lambda authorizer
//   local:    a dev-persona cookie, which the deployed units refuse (they only
//             honour X-Dev-* when BOOKFACE_DEV_IDENTITY=1, which the stack
//             never sets)
//
// The cookie survived because the generated SDK had no header hook; it now has
// one (see script/generate_ts.rb), but the cookie stays for local work because
// picking a persona from a list beats a real OAuth round trip in cucumber.
RemoteCommand.authTokenProvider = () => idToken()

const STORAGE_KEY = "bookface.dev-user"

function writeCookie(user: DevUser | null) {
  const opts = "path=/; SameSite=Lax"
  if (user) {
    document.cookie = `dev_sub=${encodeURIComponent(user.sub)}; ${opts}`
    document.cookie = `dev_name=${encodeURIComponent(user.name)}; ${opts}`
  } else {
    document.cookie = `dev_sub=; Max-Age=0; ${opts}`
    document.cookie = `dev_name=; Max-Age=0; ${opts}`
  }
}

function restore(): DevUser | null {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    return raw ? (JSON.parse(raw) as DevUser) : null
  } catch {
    return null
  }
}

let currentUser: DevUser | null = restore()
writeCookie(currentUser)

export const setUser = (u: DevUser | null) => {
  currentUser = u
  writeCookie(u)
  try {
    if (u) localStorage.setItem(STORAGE_KEY, JSON.stringify(u))
    else localStorage.removeItem(STORAGE_KEY)
  } catch {
    /* private mode */
  }
}

// The signed-in Cognito user when deployed, the chosen persona locally. Every
// caller wants "who is using this app", not "which scheme is in play".
export const getUser = (): DevUser | null => {
  if (authConfig()) {
    const me = identity()
    return me && { sub: me.sub, name: me.name }
  }
  return currentUser
}

export class RpcError<E = unknown> extends Error {
  constructor(readonly detail: E & { code: string }) {
    super(detail.code)
  }
}

// Foobara returns an Outcome; the components expect a resolved value or a
// throw. Its error symbols are richer than Prospect's codes — `cannot_cast`
// and friends come from the type system rather than being declared — so map
// the ones the UI branches on and pass the rest through.
async function run<T>(command: { run: () => Promise<any> }): Promise<T> {
  const outcome: any = await command.run()
  if (outcome.isSuccess()) return outcome.result as T

  const errors: any[] = outcome.errors ?? []
  const first = errors[0] ?? {}
  const symbol: string = first.symbol ?? first.key ?? "unknown"
  const mapped: Record<string, string> = {
    not_found: "not_found",
    post_not_found: "not_found",
    forbidden: "forbidden",
    unsupported_media_type: "unsupported_media_type",
  }
  const code = mapped[symbol] ?? (first.category === "data" ? "validation_failed" : symbol)
  const where = Array.isArray(first.path) && first.path.length ? first.path.join(".") : "base"

  throw new RpcError({ code, errors: { [where]: [first.message] } } as any)
}

export const api = {
  posts: {
    feed: (i: { limit?: number; cursor?: string | null }) =>
      run<any>(new ListPosts({ limit: i.limit, cursor: i.cursor ?? undefined })),
    get: (i: { id: string }) => run<any>(new GetPost(i)),
    create: (i: { body?: string | null; media?: any[] }) =>
      run<any>(new CreatePost({ body: i.body ?? undefined, media: i.media ?? [] })),
    update: (i: { id: string; body: string }) => run<any>(new UpdatePost(i)),
    destroy: (i: { id: string }) => run<any>(new DestroyPost(i)),
  },
  comments: {
    thread: (i: { postId: string }) => run<any>(new ListThread({ post_id: i.postId })),
    create: (i: { postId: string; body: string; parentPath?: string | null }) =>
      run<any>(new CreateComment({
        post_id: i.postId, body: i.body, parent_path: i.parentPath ?? undefined,
      })),
    update: (i: { postId: string; path: string; body: string }) =>
      run<any>(new UpdateComment({ post_id: i.postId, path: i.path, body: i.body })),
    destroy: (i: { postId: string; path: string }) =>
      run<any>(new DestroyComment({ post_id: i.postId, path: i.path })),
  },
  reactions: {
    mine: (i: { postId: string }) => run<any>(new MyReactions({ post_id: i.postId })),
    toggle: (i: { postId: string; target: string; emoji: string }) =>
      run<any>(new ToggleReaction({ post_id: i.postId, target: i.target, emoji: i.emoji })),
  },
  profiles: {
    get: (_i: Record<string, never>) => run<any>(new GetProfile(undefined)),
    update: (i: { displayName?: string | null; bio?: string | null; avatarKey?: string | null }) =>
      run<any>(new UpdateProfile({
        display_name: i.displayName ?? undefined,
        bio: i.bio ?? undefined,
        avatar_key: i.avatarKey ?? undefined,
      })),
  },
  uploads: {
    presign: (i: { contentType: string }) => run<any>(new Presign({ content_type: i.contentType })),
  },
}
