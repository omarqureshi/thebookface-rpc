import RemoteCommand from '../../base/RemoteCommand'
import { type FoobaraError } from '../../base/Error'

// Replaced after generation — see script/generate_ts.rb. The generated version
// assumes Foobara's own Auth domain, whose helpers are not generated for an
// app that does not use it.
export default class RequiresAuthCommand<Inputs, Result, Error extends FoobaraError<any>>
  extends RemoteCommand<Inputs, Result, Error> {
}
