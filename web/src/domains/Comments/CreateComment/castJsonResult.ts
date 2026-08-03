import type Result from "./Result"


import { CommentModel } from "../../Comments/Types/CommentModel/CommentModel"

import { Author } from "../../Shared/Types/Author/Author"

import { ReactionCount } from "../../Shared/Types/ReactionCount/ReactionCount"


export default function castJsonResult (json: any): Result {
  if (json?.author !== undefined) {
json.author = new Author(json.author)
}
json?.reaction_counts?.forEach((element: any, index: number, array: any[]) => {
if (element !== undefined) {
array[index] = new ReactionCount(element)
}
})
if (json !== undefined) {
json = new CommentModel(json)
}
return json
}
