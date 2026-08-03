export * as config from "./config"

export const isGlobal = false
export const organizationName = "GlobalOrganization"
export const domainName = "Reactions"


export { MyReactions } from "../Reactions/MyReactions"


export { ToggleReaction } from "../Reactions/ToggleReaction"

export * as ToggleReactionErrors from "../Reactions/ToggleReaction/errors"



// TODO: put these on an entities module so that commands can be the only top-level interface.

export { MyReaction } from "../Reactions/Types/MyReaction/MyReaction"

export { ReactionState } from "../Reactions/Types/ReactionState/ReactionState"

