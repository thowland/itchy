import Foundation

struct Branching {
  func decide(_ n: Int) -> String {
    if n > 3 {
      return "big"
    }
    return "small"
  }
}
