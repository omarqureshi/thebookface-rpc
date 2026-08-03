
import RequiresAuthCommand from "../../Foobara/Auth/RequiresAuthCommand"


import type Inputs from "./Inputs"
import type Result from "./Result"
import { type Error } from "./Errors"

import castJsonResult from "./castJsonResult"



export class Presign extends RequiresAuthCommand<Inputs, Result, Error> {
  static readonly organizationName = "GlobalOrganization"
  static readonly domainName = "Uploads"
  static readonly commandName = "Presign"


  castJsonResult(json: any): Result {
    return castJsonResult(json)
  }



}
