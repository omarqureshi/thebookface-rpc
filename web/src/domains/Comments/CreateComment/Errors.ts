
import { PostNotFoundError } from "../../Comments/CreateComment/errors/PostNotFoundError"

import { UnauthenticatedError } from "../../GlobalDomain/errors/Foobara/CommandConnector/UnauthenticatedError"

import { CannotCastError } from "../../GlobalDomain/errors/Foobara/Value/Processor/Casting/CannotCastError"

import { UnexpectedAttributesError } from "../../Types/attributes/errors/UnexpectedAttributesError"

import { MissingRequiredAttributeError } from "../../Types/attributes/errors/MissingRequiredAttributeError"



export interface PossibleErrors {

  "data.body.cannot_cast": CannotCastError,

  "data.body.missing_required_attribute": MissingRequiredAttributeError,

  "data.cannot_cast": CannotCastError,

  "data.missing_required_attribute": MissingRequiredAttributeError,

  "data.parent_path.cannot_cast": CannotCastError,

  "data.post_id.cannot_cast": CannotCastError,

  "data.post_id.missing_required_attribute": MissingRequiredAttributeError,

  "data.unexpected_attributes": UnexpectedAttributesError,

  "runtime.post_not_found": PostNotFoundError,

  "runtime.unauthenticated": UnauthenticatedError,

}


export type Error = UnauthenticatedError |
  CannotCastError |
  MissingRequiredAttributeError |
  PostNotFoundError |
  UnexpectedAttributesError
