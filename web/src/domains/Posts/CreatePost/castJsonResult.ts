import type Result from "./Result"


import { PostModel } from "../../Posts/Types/PostModel/PostModel"

import { Author } from "../../Shared/Types/Author/Author"

import { MediaItem } from "../../Shared/Types/MediaItem/MediaItem"

import { ReactionCount } from "../../Shared/Types/ReactionCount/ReactionCount"


export default function castJsonResult (json: any): Result {
  if (json?.author !== undefined) {
json.author = new Author(json.author)
}
json?.media?.forEach((element: any, index: number, array: any[]) => {
if (element !== undefined) {
array[index] = new MediaItem(element)
}
})
json?.reaction_counts?.forEach((element: any, index: number, array: any[]) => {
if (element !== undefined) {
array[index] = new ReactionCount(element)
}
})
if (json !== undefined) {
json = new PostModel(json)
}
return json
}
