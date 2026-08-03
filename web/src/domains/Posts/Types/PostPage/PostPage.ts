import { Model as FoobaraModel } from "../../../base/Model"

import { PostModel } from "../../../Posts/Types/PostModel/PostModel"


export interface PostPageAttributesType {
  posts: PostModel[]
  next_cursor?: string
}

export class PostPage<
  AttributesType extends PostPageAttributesType = PostPageAttributesType
> extends FoobaraModel<AttributesType> {
  static readonly modelName: string = "PostPage"

  
  get posts (): AttributesType["posts"] {
    return this.readAttribute("posts")
  }
  
  get next_cursor (): AttributesType["next_cursor"] {
    return this.readAttribute("next_cursor")
  }
  
}
