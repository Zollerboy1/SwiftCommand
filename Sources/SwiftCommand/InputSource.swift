import Foundation
@preconcurrency import SystemPackage

public protocol InputSource: Equatable, Sendable {
    var processInput: Either<FileHandle?, Pipe> { get throws }
}

public struct UnspecifiedInputSource: InputSource {
    internal init() {}

    public var processInput: Either<FileHandle?, Pipe> {
        .first(nil)
    }
}

public struct NullInputSource: InputSource {
    public var processInput: Either<FileHandle?, Pipe> {
        .first(.nullDevice)
    }
}

public struct InheritInputSource: InputSource {
    public var processInput: Either<FileHandle?, Pipe> {
        .first(nil)
    }
}

public struct PipeInputSource: InputSource {
    public var processInput: Either<FileHandle?, Pipe> {
        .second(.init())
    }
}

public struct FileInputSource: InputSource {
    private let path: FilePath

    public init(path: FilePath) {
        self.path = path
    }

    public var processInput: Either<FileHandle?, Pipe> {
        get throws {
            try .first(.init(forReadingFrom: self.path.url))
        }
    }
}

public struct PipeFromInputSource: InputSource {
    internal let pipe: Pipe

    public init<Stdin, Stdout, Stderr>(handle: ChildProcess<Stdin, Stdout, Stderr>.OutputHandle) {
        self.pipe = handle.pipe
    }

    public var processInput: Either<FileHandle?, Pipe> {
        .second(self.pipe)
    }
    
    public static func ==(lhs: Self, rhs: Self) -> Bool {
        lhs.pipe === rhs.pipe
    }
}

extension InputSource where Self == NullInputSource {
    public static var null: Self { .init() }
}

extension InputSource where Self == InheritInputSource {
    public static var inherit: Self { .init() }
}

extension InputSource where Self == PipeInputSource {
    public static var pipe: Self { .init() }
}

extension InputSource where Self == FileInputSource {
    public static func read(fromFile path: FilePath) -> Self {
        .init(path: path)
    }
}

extension InputSource where Self == PipeFromInputSource {
    public static func pipe<Stdin, Stdout, Stderr>(from handle: ChildProcess<Stdin, Stdout, Stderr>.OutputHandle) -> Self {
        .init(handle: handle)
    }
}
