import { Model as FoobaraModel } from "../../../base/Model"

import { FormField } from "../../../Uploads/Types/FormField/FormField"


export interface PresignedUploadAttributesType {
  url: string
  fields: FormField[]
  key: string
}

export class PresignedUpload<
  AttributesType extends PresignedUploadAttributesType = PresignedUploadAttributesType
> extends FoobaraModel<AttributesType> {
  static readonly modelName: string = "PresignedUpload"

  
  get url (): AttributesType["url"] {
    return this.readAttribute("url")
  }
  
  get fields (): AttributesType["fields"] {
    return this.readAttribute("fields")
  }
  
  get key (): AttributesType["key"] {
    return this.readAttribute("key")
  }
  
}
