import type Result from "./Result"


import { MyReaction } from "../../Reactions/Types/MyReaction/MyReaction"


export default function castJsonResult (json: any): Result {
  json?.forEach((element: any, index: number, array: any[]) => {
if (element !== undefined) {
array[index] = new MyReaction(element)
}
})
return json
}
