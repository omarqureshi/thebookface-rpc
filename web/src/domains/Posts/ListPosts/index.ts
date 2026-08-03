
import RemoteCommand from "../../base/RemoteCommand"


import type Inputs from "./Inputs"
import type Result from "./Result"
import { type Error } from "./Errors"

import castJsonResult from "./castJsonResult"



export class ListPosts extends RemoteCommand<Inputs, Result, Error> {
  static readonly organizationName = "GlobalOrganization"
  static readonly domainName = "Posts"
  static readonly commandName = "ListPosts"


  castJsonResult(json: any): Result {
    return castJsonResult(json)
  }



}
