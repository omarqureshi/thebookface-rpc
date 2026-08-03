
import RemoteCommand from "../../base/RemoteCommand"


import type Inputs from "./Inputs"
import type Result from "./Result"
import { type Error } from "./Errors"

import castJsonResult from "./castJsonResult"



export class MyReactions extends RemoteCommand<Inputs, Result, Error> {
  static readonly organizationName = "GlobalOrganization"
  static readonly domainName = "Reactions"
  static readonly commandName = "MyReactions"


  castJsonResult(json: any): Result {
    return castJsonResult(json)
  }



}
