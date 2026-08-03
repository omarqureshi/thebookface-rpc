

import { RuntimeError } from "../../../base/Error"

export class UnsupportedMediaTypeError extends RuntimeError<{
  content_type?: string
}> {
}
