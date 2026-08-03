import { Model as FoobaraModel } from "../../../base/Model"

import { Author } from "../../../Shared/Types/Author/Author"

import { MediaItem } from "../../../Shared/Types/MediaItem/MediaItem"

import { ReactionCount } from "../../../Shared/Types/ReactionCount/ReactionCount"


export interface PostModelAttributesType {
  id: string
  body?: string
  author: Author
  media: MediaItem[]
  reaction_counts: ReactionCount[]
  comment_count: number
  created_at: string
  editable: boolean
  deletable: boolean
}

export class PostModel<
  AttributesType extends PostModelAttributesType = PostModelAttributesType
> extends FoobaraModel<AttributesType> {
  static readonly modelName: string = "PostModel"

  
  get id (): AttributesType["id"] {
    return this.readAttribute("id")
  }
  
  get body (): AttributesType["body"] {
    return this.readAttribute("body")
  }
  
  get author (): AttributesType["author"] {
    return this.readAttribute("author")
  }
  
  get media (): AttributesType["media"] {
    return this.readAttribute("media")
  }
  
  get reaction_counts (): AttributesType["reaction_counts"] {
    return this.readAttribute("reaction_counts")
  }
  
  get comment_count (): AttributesType["comment_count"] {
    return this.readAttribute("comment_count")
  }
  
  get created_at (): AttributesType["created_at"] {
    return this.readAttribute("created_at")
  }
  
  get editable (): AttributesType["editable"] {
    return this.readAttribute("editable")
  }
  
  get deletable (): AttributesType["deletable"] {
    return this.readAttribute("deletable")
  }
  
}
