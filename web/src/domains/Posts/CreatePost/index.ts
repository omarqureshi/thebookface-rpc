
import RequiresAuthCommand from "../../Foobara/Auth/RequiresAuthCommand"


import type Inputs from "./Inputs"
import type Result from "./Result"
import { type Error } from "./Errors"

import castJsonResult from "./castJsonResult"



export class CreatePost extends RequiresAuthCommand<Inputs, Result, Error> {
  static readonly organizationName = "GlobalOrganization"
  static readonly domainName = "Posts"
  static readonly commandName = "CreatePost"


  castJsonResult(json: any): Result {
    return castJsonResult(json)
  }



}
