import type Result from "./Result"


import { PostModel } from "../../Posts/Types/PostModel/PostModel"

import { PostPage } from "../../Posts/Types/PostPage/PostPage"

import { Author } from "../../Shared/Types/Author/Author"

import { MediaItem } from "../../Shared/Types/MediaItem/MediaItem"

import { ReactionCount } from "../../Shared/Types/ReactionCount/ReactionCount"


export default function castJsonResult (json: any): Result {
  json?.posts?.forEach((element: any, index: number, array: any[]) => {
if (element?.author !== undefined) {
element.author = new Author(element.author)
}
element?.media?.forEach((element: any, index: number, array: any[]) => {
if (element !== undefined) {
array[index] = new MediaItem(element)
}
})
element?.reaction_counts?.forEach((element: any, index: number, array: any[]) => {
if (element !== undefined) {
array[index] = new ReactionCount(element)
}
})
if (element !== undefined) {
array[index] = new PostModel(element)
}
})
if (json !== undefined) {
json = new PostPage(json)
}
return json
}
