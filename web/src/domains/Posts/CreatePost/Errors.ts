
import { UnauthenticatedError } from "../../GlobalDomain/errors/Foobara/CommandConnector/UnauthenticatedError"

import { CannotCastError } from "../../GlobalDomain/errors/Foobara/Value/Processor/Casting/CannotCastError"

import { UnexpectedAttributesError } from "../../Types/attributes/errors/UnexpectedAttributesError"

import { MissingRequiredAttributeError } from "../../Types/attributes/errors/MissingRequiredAttributeError"



export interface PossibleErrors {

  "data.body.cannot_cast": CannotCastError,

  "data.cannot_cast": CannotCastError,

  "data.media.#.cannot_cast": CannotCastError,

  "data.media.#.content_type.cannot_cast": CannotCastError,

  "data.media.#.content_type.missing_required_attribute": MissingRequiredAttributeError,

  "data.media.#.height.cannot_cast": CannotCastError,

  "data.media.#.key.cannot_cast": CannotCastError,

  "data.media.#.key.missing_required_attribute": MissingRequiredAttributeError,

  "data.media.#.missing_required_attribute": MissingRequiredAttributeError,

  "data.media.#.unexpected_attributes": UnexpectedAttributesError,

  "data.media.#.width.cannot_cast": CannotCastError,

  "data.media.cannot_cast": CannotCastError,

  "data.unexpected_attributes": UnexpectedAttributesError,

  "runtime.unauthenticated": UnauthenticatedError,

}


export type Error = UnauthenticatedError |
  CannotCastError |
  MissingRequiredAttributeError |
  UnexpectedAttributesError
