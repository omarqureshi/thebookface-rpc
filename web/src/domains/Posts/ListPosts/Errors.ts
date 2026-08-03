
import { CannotCastError } from "../../GlobalDomain/errors/Foobara/Value/Processor/Casting/CannotCastError"

import { UnexpectedAttributesError } from "../../Types/attributes/errors/UnexpectedAttributesError"



export interface PossibleErrors {

  "data.cannot_cast": CannotCastError,

  "data.cursor.cannot_cast": CannotCastError,

  "data.limit.cannot_cast": CannotCastError,

  "data.unexpected_attributes": UnexpectedAttributesError,

}


export type Error = CannotCastError |
  UnexpectedAttributesError
