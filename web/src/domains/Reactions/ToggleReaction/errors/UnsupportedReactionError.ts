

import { RuntimeError } from "../../../base/Error"

export class UnsupportedReactionError extends RuntimeError<{
  emoji?: string
}> {
}
