import { Model as FoobaraModel } from "../../../base/Model"


export interface MediaItemAttributesType {
  key: string
  url: string
  content_type: string
  width?: number
  height?: number
}

export class MediaItem<
  AttributesType extends MediaItemAttributesType = MediaItemAttributesType
> extends FoobaraModel<AttributesType> {
  static readonly modelName: string = "MediaItem"

  
  get key (): AttributesType["key"] {
    return this.readAttribute("key")
  }
  
  get url (): AttributesType["url"] {
    return this.readAttribute("url")
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
