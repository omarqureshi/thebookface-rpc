
import { UnauthenticatedError } from "../../GlobalDomain/errors/Foobara/CommandConnector/UnauthenticatedError"

import { CannotCastError } from "../../GlobalDomain/errors/Foobara/Value/Processor/Casting/CannotCastError"

import { UnsupportedMediaTypeError } from "../../Uploads/Presign/errors/UnsupportedMediaTypeError"

import { UnexpectedAttributesError } from "../../Types/attributes/errors/UnexpectedAttributesError"

import { MissingRequiredAttributeError } from "../../Types/attributes/errors/MissingRequiredAttributeError"



export interface PossibleErrors {

  "data.cannot_cast": CannotCastError,

  "data.content_type.cannot_cast": CannotCastError,

  "data.content_type.missing_required_attribute": MissingRequiredAttributeError,

  "data.missing_required_attribute": MissingRequiredAttributeError,

  "data.unexpected_attributes": UnexpectedAttributesError,

  "runtime.unauthenticated": UnauthenticatedError,

  "runtime.unsupported_media_type": UnsupportedMediaTypeError,

}


export type Error = UnauthenticatedError |
  CannotCastError |
  MissingRequiredAttributeError |
  UnexpectedAttributesError |
  UnsupportedMediaTypeError
