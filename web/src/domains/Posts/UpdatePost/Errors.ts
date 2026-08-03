
import { UnauthenticatedError } from "../../GlobalDomain/errors/Foobara/CommandConnector/UnauthenticatedError"

import { CannotCastError } from "../../GlobalDomain/errors/Foobara/Value/Processor/Casting/CannotCastError"

import { ForbiddenError } from "../../Posts/UpdatePost/errors/ForbiddenError"

import { NotFoundError } from "../../Posts/UpdatePost/errors/NotFoundError"

import { UnexpectedAttributesError } from "../../Types/attributes/errors/UnexpectedAttributesError"

import { MissingRequiredAttributeError } from "../../Types/attributes/errors/MissingRequiredAttributeError"



export interface PossibleErrors {

  "data.body.cannot_cast": CannotCastError,

  "data.body.missing_required_attribute": MissingRequiredAttributeError,

  "data.cannot_cast": CannotCastError,

  "data.id.cannot_cast": CannotCastError,

  "data.id.missing_required_attribute": MissingRequiredAttributeError,

  "data.missing_required_attribute": MissingRequiredAttributeError,

  "data.unexpected_attributes": UnexpectedAttributesError,

  "runtime.forbidden": ForbiddenError,

  "runtime.not_found": NotFoundError,

  "runtime.unauthenticated": UnauthenticatedError,

}


export type Error = UnauthenticatedError |
  CannotCastError |
  ForbiddenError |
  MissingRequiredAttributeError |
  NotFoundError |
  UnexpectedAttributesError
