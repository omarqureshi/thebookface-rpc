
import { ForbiddenError } from "../../Comments/UpdateComment/errors/ForbiddenError"

import { NotFoundError } from "../../Comments/UpdateComment/errors/NotFoundError"

import { UnauthenticatedError } from "../../GlobalDomain/errors/Foobara/CommandConnector/UnauthenticatedError"

import { CannotCastError } from "../../GlobalDomain/errors/Foobara/Value/Processor/Casting/CannotCastError"

import { UnexpectedAttributesError } from "../../Types/attributes/errors/UnexpectedAttributesError"

import { MissingRequiredAttributeError } from "../../Types/attributes/errors/MissingRequiredAttributeError"



export interface PossibleErrors {

  "data.body.cannot_cast": CannotCastError,

  "data.body.missing_required_attribute": MissingRequiredAttributeError,

  "data.cannot_cast": CannotCastError,

  "data.missing_required_attribute": MissingRequiredAttributeError,

  "data.path.cannot_cast": CannotCastError,

  "data.path.missing_required_attribute": MissingRequiredAttributeError,

  "data.post_id.cannot_cast": CannotCastError,

  "data.post_id.missing_required_attribute": MissingRequiredAttributeError,

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
