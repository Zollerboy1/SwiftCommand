import AsyncAlgorithms
import Foundation

#if canImport(WinSDK)
import WinSDK
#endif

/// Handle to a running or exited child process
///
/// This class is used to represent and manage child processes. A child process
/// is created via the ``Command`` struct, which configures the spawning process
/// and can itself be constructed using a builder-style interface.
///
/// There is no deinit implementation for child processes, so if you do not
/// ensure the ``ChildProcess`` has exited then it will continue to run, even
/// after the ``ChildProcess`` handle has gone out of scope.
///
/// Calling ``ChildProcess/wait()``,  ``ChildProcess/status``, or similar will
/// make the parent process wait until the child has actually exited before
/// continuing:
///
/// ```swift
/// let process = try Command.findInPath(withName: "cat")
///                          .addArgument("file.txt")
///                          .spawn()
///
/// let exitStatus = try process.wait()
/// ```
public final class ChildProcess<Stdin, Stdout, Stderr>
where Stdin: InputSource, Stdout: OutputDestination, Stderr: OutputDestination {
    /// An error that can be thrown while terminating a child process.
    public enum Error: Swift.Error, CustomStringConvertible {
        /// An error indicating that the output data could not be decoded as
        /// utf-8.
        case couldNotDecodeOutput
        /// An error indicating that the reason for the termination of the
        /// process is unknown.
        case unknownTerminationReason

        public var description: String {
            switch self {
            case .couldNotDecodeOutput:
                return "Could not decode output data as an utf-8 string"
            case .unknownTerminationReason:
                return
                    "The reason for the termination of the process is unknown"
            }
        }
    }


    /// A handle to a child process's standard input (stdin).
    ///
    /// ``ChildProcess/InputHandle`` allows writing to the stdin of a child
    /// process or closing it. Since it conforms to the `TextOutputStream`
    /// protocol, you can also use the `print()` function in conjunction with
    /// it.
    ///
    /// The handle can be obtained by accessing ``ChildProcess/stdin`` on a
    /// ``ChildProcess`` instance whose stdin is piped:
    ///
    /// ```swift
    /// let process = try Command.findInPath(withName: "cat")
    ///                          .setStdin(.pipe)
    ///                          .setStdout(.pipe)
    ///                          .spawn()
    ///
    /// var stdin = process.stdin
    ///
    /// print("Foo", to: &stdin)
    /// print("Bar", to: &stdin)
    ///
    /// let output = try await process.output
    ///
    /// print(output.stdout)
    /// // Prints 'Foo\nBar\n'
    /// ```
    public struct InputHandle: TextOutputStream {
        internal let pipe: Pipe

        fileprivate init(pipe: Pipe) {
            self.pipe = pipe
        }


        /// Writes the given string to the child process's stdin stream.
        ///
        /// An exception is thrown if this handle has been invalidated by a call
        /// to ``ChildProcess/InputHandle/close()``.
        ///
        /// - Parameters:
        ///   - string: The string to append to the child process's stdin.
        public func write(_ string: String) {
            if #available(macOS 10.15.4, *) {
                try! self.pipe.fileHandleForWriting
                    .write(contentsOf: string.data(using: .utf8)!)
            } else {
                self.pipe.fileHandleForWriting.write(string.data(using: .utf8)!)
            }
        }

        /// Writes the given data to the child process's stdin stream.
        ///
        /// An exception is thrown if this handle has been invalidated by a call
        /// to ``ChildProcess/InputHandle/close()``.
        ///
        /// - Parameters:
        ///   - data: The data to append to the child process's stdin.
        public func write<T: DataProtocol>(contentsOf data: T) {
            if #available(macOS 10.15.4, *) {
                try! self.pipe.fileHandleForWriting.write(contentsOf: data)
            } else {
                self.pipe.fileHandleForWriting.write(Data(data))
            }
        }


        /// Closes the child process's stdin stream, ensuring that the process
        /// does not block waiting for input from the parent anymore.
        ///
        /// This invalidates the input handle. If you try to keep writing to
        /// it, an exception is thrown.
        public func close() {
            try! self.pipe.fileHandleForWriting.close()
        }
    }

    /// A handle to a child process's standard output (stdout) or stderr.
    ///
    /// ``ChildProcess/OutputHandle`` allows reading from the stdout or stderr
    /// of a child process. You can access
    /// ``ChildProcess/OutputHandle/availableData`` or call
    /// ``ChildProcess/OutputHandle/read(upToCount:)`` to get the currently
    /// available data of the child process's output, or call
    /// ``ChildProcess/OutputHandle/readToEnd()`` to read data until the child
    /// process sends an end of file signal. The convenience accessors
    /// ``ChildProcess/OutputHandle/characters`` and
    /// ``ChildProcess/OutputHandle/lines`` are also available and give access
    /// to `AsyncSequence`'s, returning characters or lines output by the child
    /// process asynchronously.
    ///
    /// The handle can be obtained by accessing ``ChildProcess/stdout`` or
    /// ``ChildProcess/stderr`` on a ``ChildProcess`` instance whose stdout or
    /// stderr is respectively piped:
    ///
    /// ```swift
    /// let process = try Command.findInPath(withName: "echo")
    ///                          .addArguments("Foo", "Bar")
    ///                          .setStdout(.pipe)
    ///                          .spawn()
    ///
    /// for try await line in process.stdout.lines {
    ///     print(line)
    /// }
    /// // Prints 'Foo' and 'Bar'
    ///
    /// try process.wait()
    /// // Ensure the process is terminated before exiting the parent process
    /// ```
    public struct OutputHandle {
        /// An asynchronous sequence of characters, output by a child process.
        // Should be replaced by 'some AsyncSequence<Character>' as soon as that
        // is available.
        public struct AsyncCharacters: AsyncSequence {
            @usableFromInline
            internal typealias Base =
                AsyncCharacterSequence<FileHandle.CustomAsyncBytes>

            /// The type of element produced by this asynchronous sequence.
            public typealias Element = Character

            /// The type of asynchronous iterator that produces elements of this
            /// asynchronous sequence.
            public struct AsyncIterator: AsyncIteratorProtocol {
                @usableFromInline
                internal var _base: Base.AsyncIterator

                fileprivate init(_base: Base.AsyncIterator) {
                    self._base = _base
                }

                /// Asynchronously advances to the next element and returns it,
                /// or ends the sequence if there is no next element.
                ///
                /// - Returns: The next element, if it exists, or `nil` to
                ///            signal the end of the sequence.
                @inlinable
                public mutating func next() async throws -> Character? {
                    try await self._base.next()
                }
            }

            private let base: Base

            fileprivate init(_base base: Base) {
                self.base = base
            }

            /// Creates the asynchronous iterator that produces elements of this
            /// asynchronous sequence.
            ///
            /// - Returns: An instance of the `AsyncIterator` type used to
            ///            produce elements of the asynchronous sequence.
            public func makeAsyncIterator() -> AsyncIterator {
                .init(_base: self.base.makeAsyncIterator())
            }
        }

        /// An asynchronous sequence of characters, output by a child process.
        // Should be replaced by 'some AsyncSequence<String>' as soon as that is
        // available.
        public struct AsyncLines: AsyncSequence {
            @usableFromInline
            internal typealias Base =
                AsyncLineSequence<FileHandle.CustomAsyncBytes>

            /// The type of element produced by this asynchronous sequence.
            public typealias Element = String

            /// The type of asynchronous iterator that produces elements of this
            /// asynchronous sequence.
            public struct AsyncIterator: AsyncIteratorProtocol {
                @usableFromInline
                internal var _base: Base.AsyncIterator

                fileprivate init(_base: Base.AsyncIterator) {
                    self._base = _base
                }

                /// Asynchronously advances to the next element and returns it,
                /// or ends the sequence if there is no next element.
                ///
                /// - Returns: The next element, if it exists, or `nil` to
                ///            signal the end of the sequence.
                @inlinable
                public mutating func next() async throws -> String? {
                    try await self._base.next()
                }
            }

            private let base: Base

            fileprivate init(_base base: Base) {
                self.base = base
            }

            /// Creates the asynchronous iterator that produces elements of this
            /// asynchronous sequence.
            ///
            /// - Returns: An instance of the `AsyncIterator` type used to
            ///            produce elements of the asynchronous sequence.
            public func makeAsyncIterator() -> AsyncIterator {
                .init(_base: self.base.makeAsyncIterator())
            }
        }

        /// An asynchronous sequence of raw bytes, output by a child process.
        // Should be replaced by 'some AsyncSequence<UInt8>' as soon as that is
        // available.
        public struct AsyncBytes: AsyncSequence {
            @usableFromInline
            internal typealias Base = FileHandle.CustomAsyncBytes

            /// The type of element produced by this asynchronous sequence.
            public typealias Element = UInt8

            /// The type of asynchronous iterator that produces elements of this
            /// asynchronous sequence.
            public struct AsyncIterator: AsyncIteratorProtocol {
                @usableFromInline
                internal var _base: Base.AsyncIterator

                fileprivate init(_base: Base.AsyncIterator) {
                    self._base = _base
                }

                /// Asynchronously advances to the next element and returns it,
                /// or ends the sequence if there is no next element.
                ///
                /// - Returns: The next element, if it exists, or `nil` to
                ///            signal the end of the sequence.
                @inlinable
                public mutating func next() async throws -> UInt8? {
                    try await self._base.next()
                }
            }

            private let base: Base

            fileprivate init(_base base: Base) {
                self.base = base
            }

            /// Creates the asynchronous iterator that produces elements of this
            /// asynchronous sequence.
            ///
            /// - Returns: An instance of the `AsyncIterator` type used to
            ///            produce elements of the asynchronous sequence.
            public func makeAsyncIterator() -> AsyncIterator {
                .init(_base: self.base.makeAsyncIterator())
            }
        }


        internal let pipe: Pipe

        fileprivate init(pipe: Pipe) {
            self.pipe = pipe
        }


        /// The data currently available in the child process's output stream.
        ///
        /// This accessor reads up to a buffer of data and returns it; if no
        /// data is available, it blocks. Returns an empty `Data` object if the
        /// child process closed the stream.
        public var availableData: Data {
            self.pipe.fileHandleForReading.availableData
        }


        /// Reads up to the specified number of bytes of data synchronously from
        /// the child process's output stream.
        ///
        /// This method reads up to `count` bytes from the channel. Returns an
        /// empty `Data` object if the child process closed the stream.
        ///
        /// - Parameters:
        ///   - count: The number of bytes to read from the child process's
        ///            output stream.
        /// - Returns: The data currently available in the stream, up to `count`
        ///            number of bytes, or an empty `Data` object if the stream
        ///            is closed.
        public func read(upToCount count: Int) -> Data? {
            if #available(macOS 10.15.4, *) {
                return
                    try! self.pipe.fileHandleForReading.read(upToCount: count)
            } else {
                return self.pipe.fileHandleForReading.readData(ofLength: count)
            }
        }

        /// Reads data synchronously up to the end of file or maximum number of
        /// bytes from the child process's output stream.
        ///
        /// - Returns: The data in the stream until an end-of-file indicator is
        ///            encountered.
        public func readToEnd() -> Data? {
            if #available(macOS 10.15.4, *) {
                return try! self.pipe.fileHandleForReading.readToEnd()
            } else {
                return self.pipe.fileHandleForReading.readDataToEndOfFile()
            }
        }


        /// Returns an asynchronous sequence returning the decoded characters
        /// output by the child process.
        ///
        /// ```swift
        /// let process = try Command.findInPath(withName: "echo")
        ///                          .addArgument("Foo")
        ///                          .setStdout(.pipe)
        ///                          .spawn()
        ///
        /// for try await character in process.stdout.characters {
        ///     print(character)
        /// }
        /// // Prints 'F', 'o', 'o', and '\n'
        ///
        /// try process.wait()
        /// // Ensure the process is terminated before exiting the parent
        /// // process
        /// ```
        public var characters: AsyncCharacters {
            .init(_base:
                self.pipe.fileHandleForReading.customBytes.characterSequence)
        }

#if canImport(Darwin)
        /// Returns the `Foundation` provided asynchronous sequence returning
        /// the decoded characters output by the child process.
        ///
        /// ```swift
        /// let process = try Command.findInPath(withName: "echo")
        ///                          .addArgument("Foo")
        ///                          .setStdout(.pipe)
        ///                          .spawn()
        ///
        /// for try await character in process.stdout.nativeCharacters {
        ///     print(character)
        /// }
        /// // Prints 'F', 'o', 'o', and '\n'
        ///
        /// try process.wait()
        /// // Ensure the process is terminated before exiting the parent
        /// // process
        /// ```
        @available(macOS 12.0, *)
        public var nativeCharacters:
            Foundation.AsyncCharacterSequence<FileHandle.AsyncBytes> {
            self.pipe.fileHandleForReading.bytes.characters
        }
#endif

        /// Returns an asynchronous sequence returning the decoded lines output
        /// by the child process.
        ///
        /// ```swift
        /// let process = try Command.findInPath(withName: "echo")
        ///                          .addArgument("Foo")
        ///                          .setStdout(.pipe)
        ///                          .spawn()
        ///
        /// for try await line in process.stdout.lines {
        ///     print(line)
        /// }
        /// // Prints 'Foo' and 'Bar'
        ///
        /// try process.wait()
        /// // Ensure the process is terminated before exiting the parent
        /// // process
        /// ```
        public var lines: AsyncLines {
            .init(_base:
                self.pipe.fileHandleForReading.customBytes.lineSequence)
        }

#if canImport(Darwin)
        /// Returns the `Foundation` provided asynchronous sequence returning
        /// the decoded lines output by the child process.
        ///
        /// ```swift
        /// let process = try Command.findInPath(withName: "echo")
        ///                          .addArgument("Foo")
        ///                          .setStdout(.pipe)
        ///                          .spawn()
        ///
        /// for try await line in process.stdout.nativeLines {
        ///     print(line)
        /// }
        /// // Prints 'Foo' and 'Bar'
        ///
        /// try process.wait()
        /// // Ensure the process is terminated before exiting the parent
        /// // process
        /// ```
        @available(macOS 12.0, *)
        public var nativeLines:
            Foundation.AsyncLineSequence<FileHandle.AsyncBytes> {
            self.pipe.fileHandleForReading.bytes.lines
        }
#endif

        /// Returns an asynchronous sequence returning the raw bytes output by
        /// the child process.
        ///
        /// ```swift
        /// let process = try Command.findInPath(withName: "echo")
        ///                          .addArgument("Foo")
        ///                          .setStdout(.pipe)
        ///                          .spawn()
        ///
        /// for try await byte in process.stdout.bytes {
        ///     print(byte)
        /// }
        /// // Prints '70', '111', '111', and '10'
        ///
        /// try process.wait()
        /// // Ensure the process is terminated before exiting the parent
        /// // process
        /// ```
        public var bytes: AsyncBytes {
            .init(_base: self.pipe.fileHandleForReading.customBytes)
        }

#if canImport(Darwin)
        /// Returns the `Foundation` provided asynchronous sequence returning
        /// the raw bytes output by the child process.
        ///
        /// ```swift
        /// let process = try Command.findInPath(withName: "echo")
        ///                          .addArgument("Foo")
        ///                          .setStdout(.pipe)
        ///                          .spawn()
        ///
        /// for try await byte in process.stdout.nativeBytes {
        ///     print(byte)
        /// }
        /// // Prints '70', '111', '111', and '10'
        ///
        /// try process.wait()
        /// // Ensure the process is terminated before exiting the parent
        /// // process
        /// ```
        @available(macOS 12.0, *)
        public var nativeBytes: FileHandle.AsyncBytes {
            self.pipe.fileHandleForReading.bytes
        }
#endif
    }

    public struct MergedAsyncLines: AsyncSequence {
        @usableFromInline
        internal typealias Base = AsyncMerge2Sequence<
            AsyncLineSequence<FileHandle.CustomAsyncBytes>,
            AsyncLineSequence<FileHandle.CustomAsyncBytes>
        >

        /// The type of element produced by this asynchronous sequence.
        public typealias Element = String

        /// The type of asynchronous iterator that produces elements of this
        /// asynchronous sequence.
        public struct AsyncIterator: AsyncIteratorProtocol {
            @usableFromInline
            internal var _base: Base.AsyncIterator

            fileprivate init(_base: Base.AsyncIterator) {
                self._base = _base
            }

            /// Asynchronously advances to the next element and returns it,
            /// or ends the sequence if there is no next element.
            ///
            /// - Returns: The next element, if it exists, or `nil` to
            ///            signal the end of the sequence.
            @inlinable
            public mutating func next() async throws -> String? {
                try await self._base.next()
            }
        }

        private let base: Base

        fileprivate init(_base base: Base) {
            self.base = base
        }

        /// Creates the asynchronous iterator that produces elements of this
        /// asynchronous sequence.
        ///
        /// - Returns: An instance of the `AsyncIterator` type used to
        ///            produce elements of the asynchronous sequence.
        public func makeAsyncIterator() -> AsyncIterator {
            .init(_base: self.base.makeAsyncIterator())
        }
    }


    internal typealias GeneratingCommand = Command<Stdin, Stdout, Stderr>

    private let command: GeneratingCommand
    private let process: Process
    private let stdinPipe, stdoutPipe, stderrPipe: Pipe?
    private let closeStdinImplicitly: Bool

    private init(
        command: GeneratingCommand,
        process: Process,
        stdinPipe: Pipe?,
        stdoutPipe: Pipe?,
        stderrPipe: Pipe?,
        closeStdinImplicitly: Bool
    ) {
        self.command = command
        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
        self.closeStdinImplicitly = closeStdinImplicitly
    }


    internal static func spawn(
        withCommand command: GeneratingCommand
    ) throws -> ChildProcess<Stdin, Stdout, Stderr> {
        let process = Process()

        process.executableURL = command.executablePath.url
        process.arguments = command.arguments

        let environment: [String: String]
        if command.inheritEnvironment {
            environment = ProcessInfo.processInfo
                                     .environment
                                     .merging(command.environment) { $1 }
        } else {
            environment = command.environment
        }

        process.environment = environment

        if let cwd = command.cwd {
            process.currentDirectoryURL = cwd.url
        }


        let stdinPipe: Pipe?
        let closeStdinImplicitly: Bool
        switch command.stdin {
        case let pipeSource as PipeInputSource:
            stdinPipe = Pipe()
            closeStdinImplicitly = pipeSource.closeImplicitly
            process.standardInput = stdinPipe
        case let stdin:
            stdinPipe = nil
            closeStdinImplicitly = false
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
            switch try stdout.processOutput(forType: .stdout) {
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
            switch try stderr.processOutput(forType: .stderr) {
            case let .first(fileHandle):
                process.standardError = fileHandle
            case let .second(pipe):
                process.standardError = pipe
            }
        }


        try process.run()

        return .init(
            command: command,
            process: process,
            stdinPipe: stdinPipe,
            stdoutPipe: stdoutPipe,
            stderrPipe: stderrPipe,
            closeStdinImplicitly: closeStdinImplicitly
        )
    }


    /// The pid of the child process.
    public var identifier: Int32 {
        self.process.processIdentifier
    }

    /// Indicates, if the child process is still running.
    public var isRunning: Bool {
        self.process.isRunning
    }


    /// Checks to see if the child process has already terminated and returns
    /// the process's exit status if that's the case.
    ///
    /// - Note: This accessor is deprecated. Use
    ///         ``ChildProcess/statusIfAvailable`` instead.
    @available(*, deprecated, renamed: "statusIfAvailable")
    public var exitStatus: ExitStatus? {
        get throws {
            try self.statusIfAvailable
        }
    }

    /// Checks to see if the child process has already terminated and returns
    /// the process's exit status if that's the case.
    public var statusIfAvailable: ExitStatus? {
        get throws {
            if self.process.isRunning {
                return nil
            } else {
                return try self.createExitStatus().get()
            }
        }
    }


    /// Sends an interrupt signal (`SIGINT`) to the child process. This means
    /// that the child process is terminated, if it isn't intentionally ignoring
    /// this signal.
    ///
    /// Calling this method has no effect, if the child process has already
    /// terminated.
    public func interrupt() {
        self.process.interrupt()
    }

    /// Sends a terminate signal (`SIGTERM`) to the child process. This means
    /// that the child process is terminated, if it isn't intentionally ignoring
    /// this signal.
    ///
    /// Calling this method has no effect, if the child process has already
    /// terminated.
    public func terminate() {
        self.process.terminate()
    }

    /// Sends a kill signal (`SIGKILL`) to the child process. This normally
    /// means that the child process is immediately terminated, no matter what.
    ///
    /// Use this method cautiously, since the child process cannot react to it
    /// in any way.
    ///
    /// Calling this method has no effect, if the child process has already
    /// terminated.
    public func kill() {
        if self.process.isRunning {
#if canImport(WinSDK)
            WinSDK.TerminateProcess(self.process.processHandle, 1)
#elseif canImport(Darwin)
            Darwin.kill(self.process.processIdentifier, SIGKILL)
#elseif canImport(Glibc)
            Glibc.kill(self.process.processIdentifier, SIGKILL)
#else
#error("Unsupported platform!")
#endif
        }
    }


    /// Waits for the child process to exit completely, returning the status
    /// that it exited with.
    ///
    /// This method will continue to have the same return value after it has
    /// been called at least once.
    ///
    /// This blocks the current thread until the child process has terminated.
    ///
    /// The stdin handle to the child process – if stdin is piped – will be
    /// closed before waiting. This helps avoid deadlock: it ensures that the
    /// child process does not block waiting for input from the parent process,
    /// while the parent waits for the child to exit. If you want to disable
    /// implicit closing of the pipe, you can do so, by setting
    /// ``PipeInputSource/closeImplicitly`` to `false` on
    /// ``PipeInputSource``.
    ///
    /// - Returns: The exit status of the child process.
    @discardableResult
    public func wait() throws -> ExitStatus {
        try self.closePipedStdin()

        self.process.waitUntilExit()

        return try self.createExitStatus().get()
    }

    /// Waits for the child process to exit completely, returning the status
    /// that it exited with.
    ///
    /// This accessor will continue to have the same return value after it has
    /// been called at least once.
    ///
    /// This doesn't block the current thread and allows other tasks to run
    /// before the child process terminates.
    ///
    /// The stdin handle to the child process – if stdin is piped – will be
    /// closed before waiting. This helps avoid deadlock: it ensures that the
    /// child process does not block waiting for input from the parent process,
    /// while the parent waits for the child to exit. If you want to disable
    /// implicit closing of the pipe, you can do so, by setting
    /// ``PipeInputSource/closeImplicitly`` to `false` on
    /// ``PipeInputSource``.
    public var status: ExitStatus {
        get async throws {
            try self.closePipedStdin()

            return try await withCheckedThrowingContinuation { continuation in
                if self.process.isRunning {
                    self.process.terminationHandler = { [weak self] _ in
                        if let self = self {
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
#if os(Windows)
            return .success(.terminatedBySignal)
#else
            let signal = self.process.terminationStatus
            return .success(.terminatedBySignal(signal: signal))
#endif
#if canImport(Darwin)
        @unknown default:
            return .failure(Error.unknownTerminationReason)
#endif
        }
    }

    private func closePipedStdin() throws {
        if self.closeStdinImplicitly {
            try self.stdinPipe!.fileHandleForWriting.close()
        }
    }
}

extension ChildProcess where Stdin == PipeInputSource {
    /// The handle for writing to the child process’s standard input (stdin), if
    /// it is piped.
    public var stdin: InputHandle {
        .init(pipe: self.stdinPipe!)
    }
}

extension ChildProcess where Stdout == PipeOutputDestination {
    /// The handle for reading from the child process’s standard output
    /// (stdout), if it is piped.
    public var stdout: OutputHandle {
        .init(pipe: self.stdoutPipe!)
    }


    /// Simultaneously waits for the child process to exit and collects all
    /// remaining output on the stdout/stderr handles, returning a
    /// ``ProcessOutput`` instance.
    ///
    /// This blocks the current thread until the child process has terminated.
    ///
    /// The stdin handle to the child process – if stdin is piped – will be
    /// closed before waiting. This helps avoid deadlock: it ensures that the
    /// child process does not block waiting for input from the parent process,
    /// while the parent waits for the child to exit. If you want to disable
    /// implicit closing of the pipe, you can do so, by setting
    /// ``PipeInputSource/closeImplicitly`` to `false` on
    /// ``PipeInputSource``.
    ///
    /// - Note: This method can only be called when stdout is piped.
    ///
    /// - Returns: The collected output of the child process.
    public func waitWithOutput() throws -> ProcessOutput {
        try self.closePipedStdin()

        self.process.waitUntilExit()

        return try self.createProcessOutput().get()
    }

    /// Simultaneously waits for the child process to exit and collects all
    /// remaining output on the stdout/stderr handles, returning a
    /// ``ProcessOutput`` instance.
    ///
    /// This doesn't block the current thread and allows other tasks to run
    /// before the child process terminates.
    ///
    /// The stdin handle to the child process – if stdin is piped – will be
    /// closed before waiting. This helps avoid deadlock: it ensures that the
    /// child process does not block waiting for input from the parent process,
    /// while the parent waits for the child to exit. If you want to disable
    /// implicit closing of the pipe, you can do so, by setting
    /// ``PipeInputSource/closeImplicitly`` to `false` on
    /// ``PipeInputSource``.
    ///
    /// - Note: This accessor can only be called when stdout is piped.
    public var output: ProcessOutput {
        get async throws {
            try self.closePipedStdin()

            return try await withCheckedThrowingContinuation { continuation in
                if self.process.isRunning {
                    self.process.terminationHandler = { [weak self] _ in
                        if let self = self {
                            continuation
                                .resume(with: self.createProcessOutput())
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
                let stdoutData = self.stdoutPipe!.fileHandleForReading
                                                 .availableData
                guard let stdout = String(
                    data: stdoutData,
                    encoding: .utf8
                ) else {
                    return .failure(Error.couldNotDecodeOutput)
                }

                let stderrData = self.stderrPipe?.fileHandleForReading
                                                 .availableData
                let stderr = stderrData.flatMap {
                    String(data: $0, encoding: .utf8)
                }

                return .success(.init(
                    status: status,
                    stdoutData: stdoutData,
                    stdout: stdout,
                    stderrData: stderrData,
                    stderr: stderr
                ))
            }
    }
}

extension ChildProcess where Stderr == PipeOutputDestination {
    /// The handle for reading from the child process’s standard error output
    /// (stderr), if it is piped.
    public var stderr: OutputHandle {
        .init(pipe: self.stderrPipe!)
    }
}

extension ChildProcess where Stdout == PipeOutputDestination,
                             Stderr == PipeOutputDestination {
    /// Returns an asynchronous sequence returning the decoded lines output
    /// by the child process both from stdout and stderr.
    ///
    /// ```swift
    /// let echoProcess = try Command.findInPath(withName: "echo")
    ///                              .addArguments("Foo", "Bar")
    ///                              .setStdout(.pipe)
    ///                              .spawn()
    ///
    /// let teeProcess = try Command.findInPath(withName: "tee")
    ///                             .addArgument("/dev/stderr")
    ///                             .setStdin(.pipe(from: echoProcess.stdout))
    ///                             .setOutputs(.pipe)
    ///                             .spawn()
    ///
    /// for try await line in teeProcess.mergedOutputLines {
    ///     print(line)
    /// }
    /// // Prints 'Foo' and 'Bar' twice, maybe interleaved
    ///
    /// try teeProcess.wait()
    /// // Ensure the process is terminated before exiting the parent
    /// // process
    /// ```
    public var mergedOutputLines: MergedAsyncLines {
        .init(
            _base: merge(
                self.stdout.pipe.fileHandleForReading.customBytes.lineSequence,
                self.stderr.pipe.fileHandleForReading.customBytes.lineSequence
            )
        )
    }
}
