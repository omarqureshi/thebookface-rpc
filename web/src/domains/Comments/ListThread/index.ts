
import RemoteCommand from "../../base/RemoteCommand"


import type Inputs from "./Inputs"
import type Result from "./Result"
import { type Error } from "./Errors"

import castJsonResult from "./castJsonResult"



export class ListThread extends RemoteCommand<Inputs, Result, Error> {
  static readonly organizationName = "GlobalOrganization"
  static readonly domainName = "Comments"
  static readonly commandName = "ListThread"


  castJsonResult(json: any): Result {
    return castJsonResult(json)
  }



}
