
import { CannotCastError } from "../../GlobalDomain/errors/Foobara/Value/Processor/Casting/CannotCastError"

import { NotFoundError } from "../../Posts/GetPost/errors/NotFoundError"

import { UnexpectedAttributesError } from "../../Types/attributes/errors/UnexpectedAttributesError"

import { MissingRequiredAttributeError } from "../../Types/attributes/errors/MissingRequiredAttributeError"



export interface PossibleErrors {

  "data.cannot_cast": CannotCastError,

  "data.id.cannot_cast": CannotCastError,

  "data.id.missing_required_attribute": MissingRequiredAttributeError,

  "data.missing_required_attribute": MissingRequiredAttributeError,

  "data.unexpected_attributes": UnexpectedAttributesError,

  "runtime.not_found": NotFoundError,

}


export type Error = CannotCastError |
  MissingRequiredAttributeError |
  NotFoundError |
  UnexpectedAttributesError
