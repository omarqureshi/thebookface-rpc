import { Model as FoobaraModel } from "../../../base/Model"


export interface MediaUploadAttributesType {
  key: string
  content_type: string
  width?: number
  height?: number
}

export class MediaUpload<
  AttributesType extends MediaUploadAttributesType = MediaUploadAttributesType
> extends FoobaraModel<AttributesType> {
  static readonly modelName: string = "MediaUpload"

  
  get key (): AttributesType["key"] {
    return this.readAttribute("key")
  }
  
  get content_type (): AttributesType["content_type"] {
    return this.readAttribute("content_type")
  }
  
  get width (): AttributesType["width"] {
    return this.readAttribute("width")
  }
  
  get height (): AttributesType["height"] {
    return this.readAttribute("height")
  }
  
}
