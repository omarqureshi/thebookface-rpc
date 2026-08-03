import { Model as FoobaraModel } from "../../../base/Model"


export interface AuthorAttributesType {
  name: string
  avatar_url?: string
}

export class Author<
  AttributesType extends AuthorAttributesType = AuthorAttributesType
> extends FoobaraModel<AttributesType> {
  static readonly modelName: string = "Author"

  
  get name (): AttributesType["name"] {
    return this.readAttribute("name")
  }
  
  get avatar_url (): AttributesType["avatar_url"] {
    return this.readAttribute("avatar_url")
  }
  
}
