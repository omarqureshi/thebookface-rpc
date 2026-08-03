

import { DataError } from "../../../base/Error"

export class MissingRequiredAttributeError extends DataError<{
  attribute_name?: string
}> {
}
