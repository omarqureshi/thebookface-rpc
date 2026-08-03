

import { RuntimeError } from "../../../base/Error"

export class NotFoundError extends RuntimeError<{
  post_id?: string
}> {
}
