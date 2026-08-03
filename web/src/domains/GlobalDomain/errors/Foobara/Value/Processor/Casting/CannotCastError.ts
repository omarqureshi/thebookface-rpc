

import { DataError } from "../../../../../../base/Error"

export class CannotCastError extends DataError<{
  cast_to?: any
  value?: any
  attribute_name?: string
}> {
}
