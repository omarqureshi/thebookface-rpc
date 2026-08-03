import { Model as FoobaraModel } from "../../../base/Model"

import { Author } from "../../../Shared/Types/Author/Author"

import { ReactionCount } from "../../../Shared/Types/ReactionCount/ReactionCount"


export interface CommentModelAttributesType {
  path: string
  depth: number
  body?: string
  author?: Author
  deleted: boolean
  reaction_counts: ReactionCount[]
  created_at: string
  editable: boolean
  deletable: boolean
}

export class CommentModel<
  AttributesType extends CommentModelAttributesType = CommentModelAttributesType
> extends FoobaraModel<AttributesType> {
  static readonly modelName: string = "CommentModel"

  
  get path (): AttributesType["path"] {
    return this.readAttribute("path")
  }
  
  get depth (): AttributesType["depth"] {
    return this.readAttribute("depth")
  }
  
  get body (): AttributesType["body"] {
    return this.readAttribute("body")
  }
  
  get author (): AttributesType["author"] {
    return this.readAttribute("author")
  }
  
  get deleted (): AttributesType["deleted"] {
    return this.readAttribute("deleted")
  }
  
  get reaction_counts (): AttributesType["reaction_counts"] {
    return this.readAttribute("reaction_counts")
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
