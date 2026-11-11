import Foundation

/// A placeholder for the app's first piece of domain logic. Replace it with the
/// real thing, and keep this package free of UI frameworks so its tests stay fast.
public struct Greeting: Sendable, Equatable {
    public let name: String

    public init(name: String) {
        self.name = name
    }

    public var text: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Hello!" : "Hello, \(trimmed)!"
    }
}
