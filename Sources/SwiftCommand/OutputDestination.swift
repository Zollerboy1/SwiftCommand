import Foundation
@preconcurrency import SystemPackage

/// Describes the type of output destination of a child process.
public protocol OutputDestination: Equatable, Sendable {
    /// Returns either a `FileHandle` or a `Pipe` that will function as the
    /// stdout or stderr handle of the child process.
    ///
    /// - Parameters:
    ///   - type: The type of the output, represented as an instance of
    ///           ``OutputType``.
    /// - Returns: Either a `FileHandle` or a `Pipe` that will be used as the
    ///            handle for the child process's corresponding output stream.
    func processOutput(
        forType type: OutputType
    ) throws -> Either<FileHandle, Pipe>
}

/// An output destination that is yet unspecified and acts as if it was an
/// ``InheritOutputDestination``.
public struct UnspecifiedOutputDestination: OutputDestination {
    internal init() {}

    /// Returns either a `FileHandle` or a `Pipe` that will function as the
    /// stdout or stderr handle of the child process.
    ///
    /// - Parameters:
    ///   - type: The type of the output, represented as an instance of
    ///           ``OutputType``.
    /// - Returns: Either a `FileHandle` or a `Pipe` that will be used as the
    ///            handle for the child process's corresponding output stream.
    public func processOutput(
        forType type: OutputType
    ) throws -> Either<FileHandle, Pipe> {
        switch type {
        case .stdout:
            return .first(.standardOutput)
        case .stderr:
            return .first(.standardError)
        }
    }
}

/// An output destination that connects the child process's stdout or stderr to
/// `/dev/null`.
public struct NullOutputDestination: OutputDestination {
    /// Returns either a `FileHandle` or a `Pipe` that will function as the
    /// stdout or stderr handle of the child process.
    ///
    /// - Parameters:
    ///   - type: The type of the output, represented as an instance of
    ///           ``OutputType``.
    /// - Returns: Either a `FileHandle` or a `Pipe` that will be used as the
    ///            handle for the child process's corresponding output stream.
    public func processOutput(
        forType type: OutputType
    ) throws -> Either<FileHandle, Pipe> {
        .first(.nullDevice)
    }
}

/// An output destination that inherits the stdout or stderr handle of the
/// parent process.
public struct InheritOutputDestination: OutputDestination {
    /// Returns either a `FileHandle` or a `Pipe` that will function as the
    /// stdout or stderr handle of the child process.
    ///
    /// - Parameters:
    ///   - type: The type of the output, represented as an instance of
    ///           ``OutputType``.
    /// - Returns: Either a `FileHandle` or a `Pipe` that will be used as the
    ///            handle for the child process's corresponding output stream.
    public func processOutput(
        forType type: OutputType
    ) throws -> Either<FileHandle, Pipe> {
        switch type {
        case .stdout:
            return .first(.standardOutput)
        case .stderr:
            return .first(.standardError)
        }
    }
}

/// An output destination that arranges a pipe between the parent and child
/// processes.
public struct PipeOutputDestination: OutputDestination {
    /// Returns either a `FileHandle` or a `Pipe` that will function as the
    /// stdout or stderr handle of the child process.
    ///
    /// - Parameters:
    ///   - type: The type of the output, represented as an instance of
    ///           ``OutputType``.
    /// - Returns: Either a `FileHandle` or a `Pipe` that will be used as the
    ///            handle for the child process's corresponding output stream.
    public func processOutput(
        forType type: OutputType
    ) throws -> Either<FileHandle, Pipe> {
        .second(.init())
    }
}

/// An output destination that lets the child process's stdout or stderr write
/// or append to a file.
public struct FileOutputDestination: OutputDestination {
    /// The `FilePath` where the stdout or stderr of the child process should
    /// write to.
    public let path: FilePath
    /// Indicates, if the file should be appended to rather than being
    /// overwritten.
    public let shouldAppend: Bool

    internal init(path: FilePath, appending shouldAppend: Bool) {
        self.path = path
        self.shouldAppend = shouldAppend
    }

    /// Returns either a `FileHandle` or a `Pipe` that will function as the
    /// stdout or stderr handle of the child process.
    ///
    /// - Parameters:
    ///   - type: The type of the output, represented as an instance of
    ///           ``OutputType``.
    /// - Returns: Either a `FileHandle` or a `Pipe` that will be used as the
    ///            handle for the child process's corresponding output stream.
    /// - Throws: An error if a file at the given ``FileOutputDestination/path``
    ///           does not exist.
    public func processOutput(
        forType type: OutputType
    ) throws -> Either<FileHandle, Pipe> {
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
    /// Creates a ``NullOutputDestination``.
    public static var null: Self { .init() }
}

extension OutputDestination where Self == InheritOutputDestination {
    /// Creates an ``InheritOutputDestination``.
    public static var inherit: Self { .init() }
}

extension OutputDestination where Self == PipeOutputDestination {
    /// Creates a ``PipeOutputDestination``.
    public static var pipe: Self { .init() }
}

extension OutputDestination where Self == FileOutputDestination {
    /// Creates a ``FileOutputDestination``.
    ///
    /// - Parameters:
    ///   - path: The `FilePath` where the stdout or stderr of the child process
    ///           should write to.
    ///   - shouldAppend: Indicates, if the file should be appended to rather
    ///                   than being overwritten.
    /// - Returns: A newly created ``FileOutputDestination``.
    public static func write(
        toFile path: FilePath,
        appending shouldAppend: Bool = false
    ) -> Self {
        .init(path: path, appending: shouldAppend)
    }
}
