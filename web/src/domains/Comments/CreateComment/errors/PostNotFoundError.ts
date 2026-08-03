

import { RuntimeError } from "../../../base/Error"

export class PostNotFoundError extends RuntimeError<{
  post_id?: string
}> {
}
