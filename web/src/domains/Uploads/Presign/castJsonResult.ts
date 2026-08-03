import type Result from "./Result"


import { FormField } from "../../Uploads/Types/FormField/FormField"

import { PresignedUpload } from "../../Uploads/Types/PresignedUpload/PresignedUpload"


export default function castJsonResult (json: any): Result {
  json?.fields?.forEach((element: any, index: number, array: any[]) => {
if (element !== undefined) {
array[index] = new FormField(element)
}
})
if (json !== undefined) {
json = new PresignedUpload(json)
}
return json
}
