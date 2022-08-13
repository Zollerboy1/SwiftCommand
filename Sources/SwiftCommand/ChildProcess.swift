import Foundation

public final class ChildProcess<Stdin: InputSource, Stdout: OutputDestination, Stderr: OutputDestination> {
    public enum Error: Swift.Error {
        case couldNotDecodeOutput
        case outputNotPiped
        case unknownTerminationReason
    }


    public struct InputHandle: TextOutputStream {
        internal let pipe: Pipe

        fileprivate init(pipe: Pipe) {
            self.pipe = pipe
        }


        public func write(_ string: String) {
            if #available(macOS 10.15.4, *) {
                try! self.pipe.fileHandleForWriting.write(contentsOf: string.data(using: .utf8)!)
            } else {
                self.pipe.fileHandleForWriting.write(string.data(using: .utf8)!)
            }
        }

        public func write<T: DataProtocol>(contentsOf data: T) {
            if #available(macOS 10.15.4, *) {
                try! self.pipe.fileHandleForWriting.write(contentsOf: data)
            } else {
                self.pipe.fileHandleForWriting.write(Data(data))
            }
        }


        public func close() {
            try! self.pipe.fileHandleForWriting.close()
        }
    }

    public struct OutputHandle {
        @available(macOS 12.0, *)
        public struct AsyncCharacters: AsyncSequence { // Should be replaced by 'some AsyncSequence<Character>' as soon as that is available.
            public typealias Element = Character

            public struct AsyncIterator: AsyncIteratorProtocol {
                private var base: AsyncCharacterSequence<FileHandle.AsyncBytes>.AsyncIterator

                fileprivate init(_base base: AsyncCharacterSequence<FileHandle.AsyncBytes>.AsyncIterator) {
                    self.base = base
                }

                public mutating func next() async throws -> Character? {
                    try await self.base.next()
                }
            }

            private let base: AsyncCharacterSequence<FileHandle.AsyncBytes>

            fileprivate init(_base base: AsyncCharacterSequence<FileHandle.AsyncBytes>) {
                self.base = base
            }

            public func makeAsyncIterator() -> AsyncIterator {
                .init(_base: self.base.makeAsyncIterator())
            }
        }

        @available(macOS 12.0, *)
        public struct AsyncLines: AsyncSequence { // Should be replaced by 'some AsyncSequence<String>' as soon as that is available.
            public typealias Element = String

            public struct AsyncIterator: AsyncIteratorProtocol {
                private var base: AsyncLineSequence<FileHandle.AsyncBytes>.AsyncIterator

                fileprivate init(_base base: AsyncLineSequence<FileHandle.AsyncBytes>.AsyncIterator) {
                    self.base = base
                }

                public mutating func next() async throws -> String? {
                    try await self.base.next()
                }
            }

            private let base: AsyncLineSequence<FileHandle.AsyncBytes>

            fileprivate init(_base base: AsyncLineSequence<FileHandle.AsyncBytes>) {
                self.base = base
            }

            public func makeAsyncIterator() -> AsyncIterator {
                .init(_base: self.base.makeAsyncIterator())
            }
        }
        

        internal let pipe: Pipe

        fileprivate init(pipe: Pipe) {
            self.pipe = pipe
        }


        public var availableData: Data {
            self.pipe.fileHandleForReading.availableData
        }

        
        public func read(upToCount count: Int) -> Data? {
            if #available(macOS 10.15.4, *) {
                return try! self.pipe.fileHandleForReading.read(upToCount: count)
            } else {
                return self.pipe.fileHandleForReading.readData(ofLength: count)
            }
        }

        public func readToEnd() -> Data? {
            if #available(macOS 10.15.4, *) {
                return try! self.pipe.fileHandleForReading.readToEnd()
            } else {
                return self.pipe.fileHandleForReading.readDataToEndOfFile()
            }
        }


        @available(macOS 12.0, *)
        public var characters: AsyncCharacters {
            .init(_base: self.pipe.fileHandleForReading.bytes.characters)
        }

        @available(macOS 12.0, *)
        public var lines: AsyncLines {
            .init(_base: self.pipe.fileHandleForReading.bytes.lines)
        }
    }


    private let command: Command<Stdin, Stdout, Stderr>
    private let process: Process
    private let stdinPipe, stdoutPipe, stderrPipe: Pipe?

    private init(command: Command<Stdin, Stdout, Stderr>, process: Process, stdinPipe: Pipe?, stdoutPipe: Pipe?, stderrPipe: Pipe?) {
        self.command = command
        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
    }


    internal static func spawn(withCommand command: Command<Stdin, Stdout, Stderr>) throws -> ChildProcess<Stdin, Stdout, Stderr> {
        let process = Process()
        
        process.executableURL = command.executablePath.url
        process.arguments = command.arguments

        let environment: [String: String]
        if command.inheritEnvironment {
            environment = ProcessInfo.processInfo.environment.merging(command.environment) { old, new in new }
        } else {
            environment = command.environment
        }

        process.environment = environment

        if let cwd = command.cwd {
            process.currentDirectoryURL = cwd.url
        }


        let stdinPipe: Pipe?
        switch command.stdin {
        case is PipeInputSource:
            stdinPipe = Pipe()
            process.standardInput = stdinPipe
        case let stdin:
            stdinPipe = nil
            switch try stdin.processInput {
            case let .first(fileHandle):
                process.standardInput = fileHandle
            case let .second(pipe):
                process.standardInput = pipe
            }
        }


        let stdoutPipe: Pipe?
        switch command.stdout {
        case is PipeOutputDestination:
            stdoutPipe = Pipe()
            process.standardOutput = stdoutPipe
        case let stdout:
            stdoutPipe = nil
            switch try stdout.processOutput {
            case let .first(fileHandle):
                process.standardOutput = fileHandle
            case let .second(pipe):
                process.standardOutput = pipe
            }
        }


        let stderrPipe: Pipe?
        switch command.stderr {
        case is PipeOutputDestination:
            stderrPipe = Pipe()
            process.standardError = stderrPipe
        case let stderr:
            stderrPipe = nil
            switch try stderr.processOutput {
            case let .first(fileHandle):
                process.standardError = fileHandle
            case let .second(pipe):
                process.standardError = pipe
            }
        }


        try process.run()

        return .init(command: command, process: process, stdinPipe: stdinPipe, stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)
    }


    public var identifier: Int32 {
        self.process.processIdentifier
    }

    public var isRunning: Bool {
        self.process.isRunning
    }

    public var exitStatus: ExitStatus? {
        get throws {
            if self.process.isRunning {
                return nil
            } else {
                return try self.createExitStatus().get()
            }
        }
    }


    public func interrupt() {
        self.process.interrupt()
    }

    public func terminate() {
        self.process.terminate()
    }

    public func wait() throws -> ExitStatus {
        self.process.waitUntilExit()

        return try self.createExitStatus().get()
    }

    public var status: ExitStatus {
        get async throws {
            try await withCheckedThrowingContinuation { continuation in
                if self.process.isRunning {
                    self.process.terminationHandler = { [weak self] _ in
                        if let self {
                            continuation.resume(with: self.createExitStatus())
                        } else {
                            fatalError()
                        }
                    }
                } else {
                    continuation.resume(with: self.createExitStatus())
                }
            }
        }
    }


    private func createExitStatus() -> Result<ExitStatus, Error> {
        switch self.process.terminationReason {
        case .exit:
            let status = self.process.terminationStatus
            if status == 0 {
                return .success(.success)
            } else {
                return .success(.error(exitCode: status))
            }
        case .uncaughtSignal:
            return .success(.terminatedBySignal)
        @unknown default:
            return .failure(Error.unknownTerminationReason)
        }
    }
}

extension ChildProcess where Stdin == PipeInputSource {
    public var stdin: InputHandle {
        .init(pipe: self.stdinPipe!)
    }
}

extension ChildProcess where Stdout == PipeOutputDestination {
    public var stdout: OutputHandle {
        .init(pipe: self.stdoutPipe!)
    }


    public func waitWithOutput() throws -> ProcessOutput {
        self.process.waitUntilExit()

        return try self.createProcessOutput().get()
    }

    public var output: ProcessOutput {
        get async throws {
            try await withCheckedThrowingContinuation { continuation in
                if self.process.isRunning {
                    self.process.terminationHandler = { [weak self] _ in
                        if let self {
                            continuation.resume(with: self.createProcessOutput())
                        } else {
                            fatalError()
                        }
                    }
                } else {
                    continuation.resume(with: self.createProcessOutput())
                }
            }
        }
    }

    private func createProcessOutput() -> Result<ProcessOutput, Error> {
        self.createExitStatus()
            .flatMap { status in
                guard let stdout = String(data: self.stdoutPipe!.fileHandleForReading.availableData, encoding: .utf8) else {
                    return .failure(Error.couldNotDecodeOutput)
                }

                let stderr = (self.stderrPipe?.fileHandleForReading.availableData).flatMap { String(data: $0, encoding: .utf8) }

                return .success(.init(status: status, stdout: stdout, stderr: stderr))
            }
    }
}

extension ChildProcess where Stderr == PipeOutputDestination {
    public var stderr: OutputHandle {
        .init(pipe: self.stderrPipe!)
    }
}
