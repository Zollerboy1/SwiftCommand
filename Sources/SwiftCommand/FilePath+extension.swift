import SystemPackage
import Foundation

extension FilePath {
    /// Convenience initializer for creating a `FilePath` from a `Substring`.
    public init(substring: Substring) {
        self.init(String(substring))
    }


    /// Creates a `Foundation.URL` from this `FilePath`.
    public var url: URL {
        if #available(macOS 13.0, *) {
            return .init(filePath: self.string)
        } else {
            return .init(fileURLWithPath: self.string)
        }
    }
}
