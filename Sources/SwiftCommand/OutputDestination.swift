import Foundation
@preconcurrency import SystemPackage

public protocol OutputDestination: Equatable, Sendable {
    func processOutput(forType type: OutputType) throws -> Either<FileHandle, Pipe>
}

public struct UnspecifiedOutputDestination: OutputDestination {
    internal init() {}

    public func processOutput(forType type: OutputType) throws -> Either<FileHandle, Pipe> {
        switch type {
        case .stdout:
            return .first(.standardOutput)
        case .stderr:
            return .first(.standardError)
        }
    }
}

public struct NullOutputDestination: OutputDestination {
    public func processOutput(forType type: OutputType) throws -> Either<FileHandle, Pipe> {
        .first(.nullDevice)
    }
}

public struct InheritOutputDestination: OutputDestination {
    public func processOutput(forType type: OutputType) throws -> Either<FileHandle, Pipe> {
        switch type {
        case .stdout:
            return .first(.standardOutput)
        case .stderr:
            return .first(.standardError)
        }
    }
}

public struct PipeOutputDestination: OutputDestination {
    public func processOutput(forType type: OutputType) throws -> Either<FileHandle, Pipe> {
        .second(.init())
    }
}

public struct FileOutputDestination: OutputDestination {
    public let path: FilePath
    public let shouldAppend: Bool

    public init(path: FilePath, appending shouldAppend: Bool) {
        self.path = path
        self.shouldAppend = shouldAppend
    }

    public func processOutput(forType type: OutputType) throws -> Either<FileHandle, Pipe> {
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
