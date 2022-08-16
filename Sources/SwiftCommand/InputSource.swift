#if canImport(Darwin) && swift(>=5.7)
import Foundation
#else
@preconcurrency import Foundation
#endif

@preconcurrency import SystemPackage

/// Describes the type of input source of a child process.
public protocol InputSource: Equatable, Sendable {
    /// Returns either a `FileHandle` or a `Pipe` that will function as the
    /// stdin handle of the child process.
    var processInput: Either<FileHandle, Pipe> { get throws }
}

/// An input source that is yet unspecified and acts as if it was an
/// ``InheritInputSource``.
public struct UnspecifiedInputSource: InputSource {
    internal init() {}

    /// Returns either a`FileHandle` or a `Pipe` that will function as the
    /// stdin handle of the child process.
    public var processInput: Either<FileHandle, Pipe> {
        .first(.standardInput)
    }
}

/// An input source that connects the child process's stdin to `/dev/null`.
public struct NullInputSource: InputSource {
    /// Returns either a`FileHandle` or a `Pipe` that will function as the
    /// stdin handle of the child process.
    public var processInput: Either<FileHandle, Pipe> {
        .first(.nullDevice)
    }
}

/// An input source that inherits the stdin handle of the parent process.
public struct InheritInputSource: InputSource {
    /// Returns either a`FileHandle` or a `Pipe` that will function as the
    /// stdin handle of the child process.
    public var processInput: Either<FileHandle, Pipe> {
        .first(.standardInput)
    }
}

/// An input source that arranges a pipe between the parent and child processes.
public struct PipeInputSource: InputSource {
    /// Indicates, if the created pipe should be implicitly closed when
    /// ``ChildProcess/wait()`` or ``ChildProcess/waitWithOutput()`` (or
    /// one of their async counterparts ``ChildProcess/status`` or
    /// ``ChildProcess/output``) is called on a ``ChildProcess`` instance.
    public let closeImplicitly: Bool
    
    internal init(closeImplicitly: Bool = true) {
        self.closeImplicitly = closeImplicitly
    }
    
    /// Returns either a`FileHandle` or a `Pipe` that will function as the
    /// stdin handle of the child process.
    public var processInput: Either<FileHandle, Pipe> {
        .second(.init())
    }
}

/// An input source that lets the stdin of the child process read from a file.
public struct FileInputSource: InputSource {
    /// The `FilePath` where the stdin of the child process should read from.
    public let path: FilePath

    internal init(path: FilePath) {
        self.path = path
    }

    /// Returns either a`FileHandle` or a `Pipe` that will function as the
    /// stdin handle of the child process.
    ///
    /// - Throws: An error if a file at the given ``FileInputSource/path`` does
    ///           not exist.
    public var processInput: Either<FileHandle, Pipe> {
        get throws {
            try .first(.init(forReadingFrom: self.path.url))
        }
    }
}

/// An input source that arranges a pipe from the output of another child
/// process to this child process's stdin.
public struct PipeFromInputSource: InputSource {
    internal let pipe: Pipe

    internal init<Stdin, Stdout, Stderr>(
        handle: ChildProcess<Stdin, Stdout, Stderr>.OutputHandle
    ) {
        self.pipe = handle.pipe
    }

    /// Returns either a`FileHandle` or a `Pipe` that will function as the
    /// stdin handle of the child process.
    public var processInput: Either<FileHandle, Pipe> {
        .second(self.pipe)
    }
    
    public static func ==(lhs: Self, rhs: Self) -> Bool {
        lhs.pipe === rhs.pipe
    }
}

extension InputSource where Self == NullInputSource {
    /// Creates a ``NullInputSource``.
    public static var null: Self { .init() }
}

extension InputSource where Self == InheritInputSource {
    /// Creates an ``InheritInputSource``.
    public static var inherit: Self { .init() }
}

extension InputSource where Self == PipeInputSource {
    /// Creates a ``PipeInputSource``.
    public static var pipe: Self { .init(closeImplicitly: true) }
    
    /// Creates a ``PipeInputSource``.
    ///
    /// - Parameters:
    ///   - closeImplicitly: Indicates, if the created pipe should be implicitly
    ///                      closed when ``ChildProcess/wait()`` or
    ///                      ``ChildProcess/waitWithOutput()`` (or one of their
    ///                      async counterparts ``ChildProcess/status`` or
    ///                      ``ChildProcess/output``) is called on a
    ///                      ``ChildProcess`` instance.
    /// - Returns: A newly created ``PipeInputSource``.
    public static func pipe(closeImplicitly: Bool) -> Self {
        .init(closeImplicitly: closeImplicitly)
    }
}

extension InputSource where Self == FileInputSource {
    /// Creates a ``FileInputSource``.
    ///
    /// - Parameters:
    ///   - path: The `FilePath` where the stdin of the child process should
    ///           read from.
    /// - Returns: A newly created ``FileInputSource``.
    public static func read(fromFile path: FilePath) -> Self {
        .init(path: path)
    }
}

extension InputSource where Self == PipeFromInputSource {
    /// Creates a ``PipeFromInputSource``.
    ///
    /// - Parameters:
    ///   - handle: The ``ChildProcess/OutputHandle`` corresponding to the child
    ///             process's output, which should be piped to the stdin of this
    ///             child process.
    /// - Returns: A newly created ``PipeFromInputSource``.
    public static func pipe<Stdin, Stdout, Stderr>(
        from handle: ChildProcess<Stdin, Stdout, Stderr>.OutputHandle
    ) -> Self {
        .init(handle: handle)
    }
}
