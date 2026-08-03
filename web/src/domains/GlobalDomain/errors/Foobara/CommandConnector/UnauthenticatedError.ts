

import { RuntimeError } from "../../../../base/Error"

export class UnauthenticatedError extends RuntimeError<Record<string, never>> {
}
