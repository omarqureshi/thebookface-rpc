import { Model as FoobaraModel } from "../../../base/Model"


export interface ProfileModelAttributesType {
  display_name?: string
  bio?: string
  avatar_key?: string
  avatar_url?: string
  shown_name: string
}

export class ProfileModel<
  AttributesType extends ProfileModelAttributesType = ProfileModelAttributesType
> extends FoobaraModel<AttributesType> {
  static readonly modelName: string = "ProfileModel"

  
  get display_name (): AttributesType["display_name"] {
    return this.readAttribute("display_name")
  }
  
  get bio (): AttributesType["bio"] {
    return this.readAttribute("bio")
  }
  
  get avatar_key (): AttributesType["avatar_key"] {
    return this.readAttribute("avatar_key")
  }
  
  get avatar_url (): AttributesType["avatar_url"] {
    return this.readAttribute("avatar_url")
  }
  
  get shown_name (): AttributesType["shown_name"] {
    return this.readAttribute("shown_name")
  }
  
}
