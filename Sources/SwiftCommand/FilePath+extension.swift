import SystemPackage
import Foundation

extension FilePath {
    public init?(substring: Substring) {
        self.init(String(substring))
    }


    public var url: URL {
        if #available(macOS 13.0, *) {
            return .init(filePath: self.string)
        } else {
            return .init(fileURLWithPath: self.string)
        }
    }
}
