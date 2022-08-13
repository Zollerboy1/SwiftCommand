import Foundation
@preconcurrency import SystemPackage

public protocol OutputDestination: Equatable, Sendable {
    var processOutput: Either<FileHandle?, Pipe> { get throws }
}

public struct UnspecifiedOutputDestination: OutputDestination {
    internal init() {}

    public var processOutput: Either<FileHandle?, Pipe> {
        .first(nil)
    }
}

public struct NullOutputDestination: OutputDestination {
    public var processOutput: Either<FileHandle?, Pipe> {
        .first(.nullDevice)
    }
}

public struct InheritOutputDestination: OutputDestination {
    public var processOutput: Either<FileHandle?, Pipe> {
        .first(nil)
    }
}

public struct PipeOutputDestination: OutputDestination {
    public var processOutput: Either<FileHandle?, Pipe> {
        .second(.init())
    }
}

public struct FileOutputDestination: OutputDestination {
    private let path: FilePath
    private let shouldAppend: Bool

    public init(path: FilePath, appending shouldAppend: Bool) {
        self.path = path
        self.shouldAppend = shouldAppend
    }

    public var processOutput: Either<FileHandle?, Pipe> {
        get throws {
            let fileHandle = try FileHandle(forWritingTo: self.path.url)
            if self.shouldAppend {
                if #available(macOS 10.15.4, *) {
                    try fileHandle.seekToEnd()
                } else {
                    fileHandle.seekToEndOfFile()
                }
            }

            return .first(fileHandle)
        }
    }
}

extension OutputDestination where Self == NullOutputDestination {
    public static var null: Self { .init() }
}

extension OutputDestination where Self == InheritOutputDestination {
    public static var inherit: Self { .init() }
}

extension OutputDestination where Self == PipeOutputDestination {
    public static var pipe: Self { .init() }
}

extension OutputDestination where Self == FileOutputDestination {
    public static func write(toFile path: FilePath, appending shouldAppend: Bool = false) -> Self {
        .init(path: path, appending: shouldAppend)
    }
}
