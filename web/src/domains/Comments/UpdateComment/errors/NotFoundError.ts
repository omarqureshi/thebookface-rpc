

import { RuntimeError } from "../../../base/Error"

export class NotFoundError extends RuntimeError<{
  path?: string
}> {
}
