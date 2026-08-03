import type Result from "./Result"


import { ReactionState } from "../../Reactions/Types/ReactionState/ReactionState"

import { ReactionCount } from "../../Shared/Types/ReactionCount/ReactionCount"


export default function castJsonResult (json: any): Result {
  json?.reaction_counts?.forEach((element: any, index: number, array: any[]) => {
if (element !== undefined) {
array[index] = new ReactionCount(element)
}
})
if (json !== undefined) {
json = new ReactionState(json)
}
return json
}
