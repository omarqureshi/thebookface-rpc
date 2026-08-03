
import { UnauthenticatedError } from "../../GlobalDomain/errors/Foobara/CommandConnector/UnauthenticatedError"

import { CannotCastError } from "../../GlobalDomain/errors/Foobara/Value/Processor/Casting/CannotCastError"

import { NotFoundError } from "../../Reactions/ToggleReaction/errors/NotFoundError"

import { UnsupportedReactionError } from "../../Reactions/ToggleReaction/errors/UnsupportedReactionError"

import { UnexpectedAttributesError } from "../../Types/attributes/errors/UnexpectedAttributesError"

import { MissingRequiredAttributeError } from "../../Types/attributes/errors/MissingRequiredAttributeError"



export interface PossibleErrors {

  "data.cannot_cast": CannotCastError,

  "data.emoji.cannot_cast": CannotCastError,

  "data.emoji.missing_required_attribute": MissingRequiredAttributeError,

  "data.missing_required_attribute": MissingRequiredAttributeError,

  "data.post_id.cannot_cast": CannotCastError,

  "data.post_id.missing_required_attribute": MissingRequiredAttributeError,

  "data.target.cannot_cast": CannotCastError,

  "data.target.missing_required_attribute": MissingRequiredAttributeError,

  "data.unexpected_attributes": UnexpectedAttributesError,

  "runtime.not_found": NotFoundError,

  "runtime.unauthenticated": UnauthenticatedError,

  "runtime.unsupported_reaction": UnsupportedReactionError,

}


export type Error = UnauthenticatedError |
  CannotCastError |
  MissingRequiredAttributeError |
  NotFoundError |
  UnexpectedAttributesError |
  UnsupportedReactionError
