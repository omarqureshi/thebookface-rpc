

import { DataError } from "../../../base/Error"

export class UnexpectedAttributesError extends DataError<{
  unexpected_attributes?: string[]
  allowed_attributes?: string[]
}> {
}
