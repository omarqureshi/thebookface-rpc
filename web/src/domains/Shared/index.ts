export * as config from "./config"

export const isGlobal = false
export const organizationName = "GlobalOrganization"
export const domainName = "Shared"



// TODO: put these on an entities module so that commands can be the only top-level interface.

export { Author } from "../Shared/Types/Author/Author"

export { ReactionCount } from "../Shared/Types/ReactionCount/ReactionCount"

export { MediaUpload } from "../Shared/Types/MediaUpload/MediaUpload"

export { MediaItem } from "../Shared/Types/MediaItem/MediaItem"

