

import { RuntimeError } from "../../../base/Error"

export class ForbiddenError extends RuntimeError<{
  path?: string
}> {
}
