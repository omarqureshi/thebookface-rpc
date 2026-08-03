// Types the components use, mirroring the generated Result shapes.
//
// Not hand-written contract: the generated SDK has these per command
// (src/domains/*/Result.ts). They are re-exported in one place because the
// components predate the SDK and refer to a single Post/Comment/Profile shape.
export type { default as Post } from "../domains/Posts/GetPost/Result"
export type { default as Comment } from "../domains/Comments/CreateComment/Result"
export type { default as Profile } from "../domains/Profiles/GetProfile/Result"

export interface UploadedMedia {
  key: string
  content_type: string
  width?: number
  height?: number
}
