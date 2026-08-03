import type Result from "./Result"


import { CommentModel } from "../../Comments/Types/CommentModel/CommentModel"

import { Author } from "../../Shared/Types/Author/Author"

import { ReactionCount } from "../../Shared/Types/ReactionCount/ReactionCount"


export default function castJsonResult (json: any): Result {
  json?.forEach((element: any, index: number, array: any[]) => {
if (element?.author !== undefined) {
element.author = new Author(element.author)
}
element?.reaction_counts?.forEach((element: any, index: number, array: any[]) => {
if (element !== undefined) {
array[index] = new ReactionCount(element)
}
})
if (element !== undefined) {
array[index] = new CommentModel(element)
}
})
return json
}
