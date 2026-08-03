import type Result from "./Result"


import { ProfileModel } from "../../Profiles/Types/ProfileModel/ProfileModel"


export default function castJsonResult (json: any): Result {
  if (json !== undefined) {
json = new ProfileModel(json)
}
return json
}
