import { Model as FoobaraModel } from "../../../base/Model"


export interface FormFieldAttributesType {
  name: string
  value: string
}

export class FormField<
  AttributesType extends FormFieldAttributesType = FormFieldAttributesType
> extends FoobaraModel<AttributesType> {
  static readonly modelName: string = "FormField"

  
  get name (): AttributesType["name"] {
    return this.readAttribute("name")
  }
  
  get value (): AttributesType["value"] {
    return this.readAttribute("value")
  }
  
}
