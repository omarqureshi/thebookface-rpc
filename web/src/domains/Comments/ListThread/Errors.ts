
import { CannotCastError } from "../../GlobalDomain/errors/Foobara/Value/Processor/Casting/CannotCastError"

import { UnexpectedAttributesError } from "../../Types/attributes/errors/UnexpectedAttributesError"

import { MissingRequiredAttributeError } from "../../Types/attributes/errors/MissingRequiredAttributeError"



export interface PossibleErrors {

  "data.cannot_cast": CannotCastError,

  "data.missing_required_attribute": MissingRequiredAttributeError,

  "data.post_id.cannot_cast": CannotCastError,

  "data.post_id.missing_required_attribute": MissingRequiredAttributeError,

  "data.unexpected_attributes": UnexpectedAttributesError,

}


export type Error = CannotCastError |
  MissingRequiredAttributeError |
  UnexpectedAttributesError
