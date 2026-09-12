import Foundation

struct Trivial {
  let model: String
  func render() -> String {
    model.uppercased()
  }
  func unwrap(_ value: String?) -> String {
    guard let value else { return "" }
    return value
  }
}
