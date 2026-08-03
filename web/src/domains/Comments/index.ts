export * as config from "./config"

export const isGlobal = false
export const organizationName = "GlobalOrganization"
export const domainName = "Comments"


export { CreateComment } from "../Comments/CreateComment"

export * as CreateCommentErrors from "../Comments/CreateComment/errors"


export { DestroyComment } from "../Comments/DestroyComment"

export * as DestroyCommentErrors from "../Comments/DestroyComment/errors"


export { ListThread } from "../Comments/ListThread"


export { UpdateComment } from "../Comments/UpdateComment"

export * as UpdateCommentErrors from "../Comments/UpdateComment/errors"



// TODO: put these on an entities module so that commands can be the only top-level interface.

export { CommentModel } from "../Comments/Types/CommentModel/CommentModel"

