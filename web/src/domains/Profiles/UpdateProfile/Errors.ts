
import { UnauthenticatedError } from "../../GlobalDomain/errors/Foobara/CommandConnector/UnauthenticatedError"

import { CannotCastError } from "../../GlobalDomain/errors/Foobara/Value/Processor/Casting/CannotCastError"

import { UnexpectedAttributesError } from "../../Types/attributes/errors/UnexpectedAttributesError"



export interface PossibleErrors {

  "data.avatar_key.cannot_cast": CannotCastError,

  "data.bio.cannot_cast": CannotCastError,

  "data.cannot_cast": CannotCastError,

  "data.display_name.cannot_cast": CannotCastError,

  "data.unexpected_attributes": UnexpectedAttributesError,

  "runtime.unauthenticated": UnauthenticatedError,

}


export type Error = UnauthenticatedError |
  CannotCastError |
  UnexpectedAttributesError
