import RemoteCommand from '../../base/RemoteCommand'
import { type FoobaraError } from '../../base/Error'

// Replaced after generation — see script/generate_ts.rb. The generated
// version assumes Foobara's bearer-token Auth domain; this app uses a cookie,
// and RemoteCommand already sends credentials: "include".
export default class RequiresAuthCommand<Inputs, Result, Error extends FoobaraError<any>>
  extends RemoteCommand<Inputs, Result, Error> {
}
