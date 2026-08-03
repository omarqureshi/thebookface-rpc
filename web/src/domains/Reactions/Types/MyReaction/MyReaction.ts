import { Model as FoobaraModel } from "../../../base/Model"


export interface MyReactionAttributesType {
  target: string
  emoji: string
}

export class MyReaction<
  AttributesType extends MyReactionAttributesType = MyReactionAttributesType
> extends FoobaraModel<AttributesType> {
  static readonly modelName: string = "MyReaction"

  
  get target (): AttributesType["target"] {
    return this.readAttribute("target")
  }
  
  get emoji (): AttributesType["emoji"] {
    return this.readAttribute("emoji")
  }
  
}
