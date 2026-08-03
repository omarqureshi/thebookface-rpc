export * as config from "./config"

export const isGlobal = false
export const organizationName = "GlobalOrganization"
export const domainName = "Posts"


export { CreatePost } from "../Posts/CreatePost"


export { DestroyPost } from "../Posts/DestroyPost"

export * as DestroyPostErrors from "../Posts/DestroyPost/errors"


export { GetPost } from "../Posts/GetPost"

export * as GetPostErrors from "../Posts/GetPost/errors"


export { ListPosts } from "../Posts/ListPosts"


export { UpdatePost } from "../Posts/UpdatePost"

export * as UpdatePostErrors from "../Posts/UpdatePost/errors"



// TODO: put these on an entities module so that commands can be the only top-level interface.

export { PostModel } from "../Posts/Types/PostModel/PostModel"

export { PostPage } from "../Posts/Types/PostPage/PostPage"

