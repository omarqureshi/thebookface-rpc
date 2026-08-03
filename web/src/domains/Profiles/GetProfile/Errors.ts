
import { UnauthenticatedError } from "../../GlobalDomain/errors/Foobara/CommandConnector/UnauthenticatedError"



export interface PossibleErrors {

  "runtime.unauthenticated": UnauthenticatedError,

}


export type Error = UnauthenticatedError
