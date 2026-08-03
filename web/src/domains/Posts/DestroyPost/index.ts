
import RequiresAuthCommand from "../../Foobara/Auth/RequiresAuthCommand"


import type Inputs from "./Inputs"
import type Result from "./Result"
import { type Error } from "./Errors"



export class DestroyPost extends RequiresAuthCommand<Inputs, Result, Error> {
  static readonly organizationName = "GlobalOrganization"
  static readonly domainName = "Posts"
  static readonly commandName = "DestroyPost"




}
