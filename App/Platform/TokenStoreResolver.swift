import Foundation
import ItchyServices

/// Which token store a launch gets (D-11).
///
/// A decision, and one worth naming rather than inlining: a launch pointed at a
/// throwaway store must not read or write the real Keychain item. The UI suite
/// runs that way, and so does any experiment run against a scratch directory.
///
/// Getting this wrong is not a wrong answer but a hang: macOS asks the person
/// whether this binary may read an item a differently-signed build created, and
/// an automated run has nobody to ask.
enum TokenStoreResolver {
  static func store(for options: LaunchOptions) -> any MCPTokenStore {
    guard !options.usesTemporaryStorage else { return InMemoryTokenStore() }
    return MCPTokenKeychain()
  }
}
