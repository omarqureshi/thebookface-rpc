import { Model as FoobaraModel } from "../../../base/Model"

import { ReactionCount } from "../../../Shared/Types/ReactionCount/ReactionCount"


export interface ReactionStateAttributesType {
  target: string
  reaction_counts: ReactionCount[]
  mine?: string
}

export class ReactionState<
  AttributesType extends ReactionStateAttributesType = ReactionStateAttributesType
> extends FoobaraModel<AttributesType> {
  static readonly modelName: string = "ReactionState"

  
  get target (): AttributesType["target"] {
    return this.readAttribute("target")
  }
  
  get reaction_counts (): AttributesType["reaction_counts"] {
    return this.readAttribute("reaction_counts")
  }
  
  get mine (): AttributesType["mine"] {
    return this.readAttribute("mine")
  }
  
}
