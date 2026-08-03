import { Model as FoobaraModel } from "../../../base/Model"


export interface ReactionCountAttributesType {
  emoji: string
  count: number
}

export class ReactionCount<
  AttributesType extends ReactionCountAttributesType = ReactionCountAttributesType
> extends FoobaraModel<AttributesType> {
  static readonly modelName: string = "ReactionCount"

  
  get emoji (): AttributesType["emoji"] {
    return this.readAttribute("emoji")
  }
  
  get count (): AttributesType["count"] {
    return this.readAttribute("count")
  }
  
}
