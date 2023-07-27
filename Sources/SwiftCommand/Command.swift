import Foundation
@preconcurrency import SystemPackage

/// A process builder, providing fine-grained control over how a new process
/// should be spawned.
///
/// A default configuration can be generated using
/// ``Command/init(executablePath:)``, where `executablePath` gives a path to
/// the program to be executed, or using ``Command/findInPath(withName:)``,
/// where `name` is the name of a command line program available in `$PATH`.
/// Additional builder methods allow the configuration to be changed (for
/// example, by adding arguments) prior to spawning:
///
/// ```swift
/// let output = try Command.findInPath(withName: "echo")!
///                         .addArgument("Foo")
///                         .waitForOutput()
///
/// let foo = output.stdout
/// ```
///
/// A ``Command`` instance can be reused to spawn multiple processes. The
/// builder methods change the command without needing to immediately spawn the
/// process.
///
/// ```swift
/// let echoFoo = Command.findInPath(withName: "echo")!
///                      .addArgument("Foo")
/// let foo1 = try echoFoo.waitForOutput()
/// let foo2 = try echoFoo.waitForOutput()
/// ```
///
/// Similarly, you can call builder methods after spawning a process and then
/// spawn a new process with the modified settings.
///
/// ```swift
/// let listDir = Command.findInPath(withName: "ls")!
///
/// // Execute `ls` in the current directory of the program.
/// try listDir.wait()
///
/// print()
///
/// // Change `ls` to execute in the root directory.
/// let listRootDir = listDir.setCWD("/")
///
/// // And then execute `ls` again but in the root directory.
/// try listRootDir.wait()
/// ```
///
/// To wait for the child process to terminate, but not block the current
/// thread, you can use the `async`/`await` API on ``Command``, e.g.:
///
/// ```swift
/// let output = try await Command.findInPath(withName: "echo")!
///                               .addArgument("Foo")
///                               .output
///
/// print(output.stdout)
/// // Prints 'Foo\n'
/// ```
public struct Command<Stdin, Stdout, Stderr>: Equatable, Sendable
where Stdin: InputSource, Stdout: OutputDestination, Stderr: OutputDestination {
    /// An error that can be thrown while initializing a command.
    public enum Error: Swift.Error, CustomStringConvertible {
        /// An error indicating that no executable exists at the given path.
        case executableNotFound(path: FilePath)
        
        public var description: String {
            switch self {
            case let .executableNotFound(path):
                return "There is no executable at path '\(path)'"
            }
        }
    }


#if os(Windows)
    @inline(__always)
    private static var pathVariable: String { "Path" }
    @inline(__always)
    private static var pathSeparator: Character { ";" }
    @inline(__always)
    private static var executableExtension: String { ".exe" }
#else
    @inline(__always)
    private static var pathVariable: String { "PATH" }
    @inline(__always)
    private static var pathSeparator: Character { ":" }
    @inline(__always)
    private static var executableExtension: String { "" }
#endif


    /// The path of the executable file that will be invoked when this command
    /// is spawned.
    ///
    /// Can be used in conjunction with ``Command/findInPath(withName:)`` to
    /// find out the path of an executable in one of the directories contained
    /// in the `$PATH` environment variable:
    ///
    /// ```swift
    /// let path = Command.findInPath(withName: "echo")!.executablePath
    ///
    /// print(path)
    /// // Prints e.g. '/bin/echo'
    /// ```
    public let executablePath: FilePath
    
    /// The list of arguments that will be passed to the program when this
    /// command is spawned.
    public let arguments: [String]
    
    /// The environment dictionary that will be set for the program when this
    /// command is spawned.
    ///
    /// If ``Command/inheritEnvironment`` is `true`, this environment dictionary
    /// will be merged with the environment of the parent process before the
    /// command is spawned.
    public let environment: [String: String]
    
    /// Determines, if the environment of the child process inherits from the
    /// parent process's one.
    ///
    /// ``Command/inheritEnvironment`` is initially `true` but can be set to
    /// `false` by calling ``Command/clearEnv()``:
    ///
    /// ```swift
    /// try Command.findInPath(withName: "foo")
    ///            .clearEnv()
    ///            .wait()
    /// // Command 'foo' is executed without any environment variables.
    /// ```
    public let inheritEnvironment: Bool
    
    /// Determines the child process's working directory.
    ///
    /// If ``Command/cwd`` is `nil`, the working directory will not be changed.
    public let cwd: FilePath?

    internal let stdin: Stdin
    internal let stdout: Stdout
    internal let stderr: Stderr
    

    private init(
        executablePath: FilePath,
        arguments: [String],
        environment: [String: String],
        inheritEnvironment: Bool,
        cwd: FilePath?,
        stdin: Stdin,
        stdout: Stdout,
        stderr: Stderr
    ) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.environment = environment
        self.inheritEnvironment = inheritEnvironment
        self.cwd = cwd

        self.stdin = stdin
        self.stdout = stdout
        self.stderr = stderr
    }

    /// Initializes a command that executes the program at the given
    /// `executablePath` when spawned.
    ///
    /// This initializer checks, if an executable file exists at the given
    /// `executablePath`.
    ///
    /// - Parameters:
    ///   - executablePath: A `FilePath`, representing the program that should
    ///                     be executed when this command is spawned.
    public init(executablePath: FilePath)
    where Stdin == UnspecifiedInputSource,
          Stdout == UnspecifiedOutputDestination,
          Stderr == UnspecifiedOutputDestination {
        self.init(
            executablePath: executablePath,
            arguments: [],
            environment: [:],
            inheritEnvironment: true,
            cwd: nil,
            stdin: .init(),
            stdout: .init(),
            stderr: .init()
        )
    }

    /// Initializes a command by finding a command line program with the given
    /// `name` in one of the directories listed in the `$PATH` environment
    /// variable.
    ///
    /// Searches the directories listed in the `$PATH` environment variable for
    /// an executable file with the given `name`, exactly like the shell does,
    /// when you type a command in the terminal.
    ///
    /// This can be used in conjunction with ``Command/executablePath`` to get
    /// the path of a command line program:
    ///
    /// ```swift
    /// let path = Command.findInPath(withName: "echo")!.executablePath
    ///
    /// print(path)
    /// // Prints e.g. '/bin/echo'
    /// ```
    ///
    /// - Parameters:
    ///   - name: The name of the command line program to search for in `$PATH`.
    /// - Returns: An initialized command with the found program in
    ///            ``Command/executablePath``, or `nil`, if no program with the
    ///            given `name` could be found.
    public static func findInPath(withName name: String) -> Command?
    where Stdin == UnspecifiedInputSource,
          Stdout == UnspecifiedOutputDestination,
          Stderr == UnspecifiedOutputDestination {
        let nameWithExtension: String
        if !Self.executableExtension.isEmpty
            && !name.hasSuffix(Self.executableExtension) {
            nameWithExtension = name + Self.executableExtension
        } else {
            nameWithExtension = name
        }
        
        guard let environmentPath =
            ProcessInfo.processInfo.environment[Self.pathVariable] else {
            return nil
        }

        guard let executablePath =
            environmentPath.split(separator: Self.pathSeparator).lazy
            .compactMap(FilePath.init(substring:))
            .map({ $0.appending(nameWithExtension) })
            .first(where: {
                FileManager.default.isExecutableFile(atPath: $0.string)
            }) else {
            return nil
        }

        return .init(
            executablePath: executablePath,
            arguments: [],
            environment: [:],
            inheritEnvironment: true,
            cwd: nil,
            stdin: .init(),
            stdout: .init(),
            stderr: .init()
        )
    }


    /// Adds the provided list of arguments in order to the end of the current
    /// argument list.
    ///
    /// - Parameters:
    ///   - newArguments: An `Array` of argument strings, that will be added to
    ///                   the current arguments.
    /// - Returns: A new command instance with the updated argument list.
    public __consuming func addArguments(_ newArguments: [String]) -> Self {
        .init(
            executablePath: self.executablePath,
            arguments: self.arguments + newArguments,
            environment: self.environment,
            inheritEnvironment: self.inheritEnvironment,
            cwd: self.cwd,
            stdin: self.stdin,
            stdout: self.stdout,
            stderr: self.stderr
        )
    }

    /// Adds the provided list of arguments in order to the end of the current
    /// argument list.
    ///
    /// - Parameters:
    ///   - newArguments: One or more argument strings, that will be added to
    ///                   the current arguments.
    /// - Returns: A new command instance with the updated argument list.
    public __consuming func addArguments(_ newArguments: String...) -> Self {
        self.addArguments(newArguments)
    }

    /// Adds the provided argument to the end of the current argument list.
    ///
    /// - Parameters:
    ///   - newArguments: An argument string, that will be added to the current
    ///                   arguments.
    /// - Returns: A new command instance with the updated argument list.
    public __consuming func addArgument(_ newArgument: String) -> Self {
        self.addArguments(newArgument)
    }
    
    
    @available(*, deprecated, renamed: "setEnvVariable")
    public __consuming func addEnvVariable(key: String, value: String) -> Self {
        self.setEnvVariable(key: key, value: value)
    }

    /// Adds the provided environment variable to the current environment
    /// dictionary, or updates an already existing environment variable.
    ///
    /// - Parameters:
    ///   - key: The name of the environment variable to set.
    ///   - value: The value set to the environment variable.
    /// - Returns: A new command instance with the updated environment.
    public __consuming func setEnvVariable(key: String, value: String) -> Self {
        var newEnvironment = self.environment

        newEnvironment[key] = value

        return .init(
            executablePath: self.executablePath,
            arguments: self.arguments,
            environment: newEnvironment,
            inheritEnvironment: self.inheritEnvironment,
            cwd: self.cwd,
            stdin: self.stdin,
            stdout: self.stdout,
            stderr: self.stderr
        )
    }
    
    @available(*, deprecated, renamed: "setEnvVariables")
    public __consuming func addEnvVariables(
        _ newEnvVariables: [String: String]
    ) -> Self {
        self.setEnvVariables(newEnvVariables)
    }
    
    /// Merges the given environment dictionary with the current environment.
    ///
    /// If there are variables with the same name, the values of the given
    /// dictionary are used.
    ///
    /// - Parameters:
    ///   - newEnvVariables: A `Dictionary` containing the environment variables
    ///                      that should be updated/added to the current
    ///                      environment.
    /// - Returns: A new command instance with the updated environment.
    public __consuming func setEnvVariables(
        _ newEnvVariables: [String: String]
    ) -> Self {
        .init(
            executablePath: self.executablePath,
            arguments: self.arguments,
            environment: self.environment.merging(newEnvVariables) { $1 },
            inheritEnvironment: self.inheritEnvironment,
            cwd: self.cwd,
            stdin: self.stdin,
            stdout: self.stdout,
            stderr: self.stderr
        )
    }

    /// Clears the current environment dictionary and sets
    /// ``Command/inheritEnvironment`` to `false`.
    ///
    /// This method should be used if the child process should not inherit the
    /// environment of the parent process:
    ///
    /// ```swift
    /// try Command.findInPath(withName: "foo")
    ///            .clearEnv()
    ///            .wait()
    /// // Command 'foo' is executed without any environment variables.
    /// ```
    ///
    /// - Returns: A new command instance with a cleared environment.
    public __consuming func clearEnv() -> Self {
        .init(
            executablePath: self.executablePath,
            arguments: self.arguments,
            environment: [:],
            inheritEnvironment: false,
            cwd: self.cwd,
            stdin: self.stdin,
            stdout: self.stdout,
            stderr: self.stderr
        )
    }


    /// Sets the working directory of the child process to the given path.
    ///
    /// - Parameters:
    ///   - newCWD: A `FilePath`, representing the working directory of the
    ///             child process.
    /// - Returns: A new command instance with the given cwd.
    public __consuming func setCWD(_ newCWD: FilePath) -> Self {
        .init(
            executablePath: self.executablePath,
            arguments: self.arguments,
            environment: self.environment,
            inheritEnvironment: self.inheritEnvironment,
            cwd: newCWD,
            stdin: self.stdin,
            stdout: self.stdout,
            stderr: self.stderr
        )
    }


    /// Sets a different source for the child process's stdin handle.
    ///
    /// This can be used to give the child process input from a file, from the
    /// parent process itself, or even from the output of another child process:
    ///
    /// ```swift
    /// let catProcess = try Command.findInPath(withName: "cat")!
    ///         .setStdin(.read(fromFile: "SomeFile.txt"))
    ///         .setStdout(.pipe)
    ///         .spawn()
    ///
    /// let grepProcess = try Command.findInPath(withName: "grep")!
    ///         .addArgument("Ba")
    ///         .setStdin(.pipe(from: catProcess.stdout))
    ///         .setStdout(.pipe)
    ///         .spawn()
    ///
    /// for try await line in grepProcess.stdout.lines {
    ///     print(line)
    /// }
    /// // Prints all lines in 'SomeFile.txt' containing 'Ba'
    /// ```
    ///
    /// - Parameters:
    ///   - newStdin: An ``InputSource``, corresponding to the method of input,
    ///               the child process should use.
    /// - Returns: A new command instance with the given stdin source set.
    public __consuming func setStdin<NewStdin: InputSource>(
        _ newStdin: NewStdin
    ) -> Command<NewStdin, Stdout, Stderr> {
        .init(
            executablePath: self.executablePath,
            arguments: self.arguments,
            environment: self.environment,
            inheritEnvironment: self.inheritEnvironment,
            cwd: self.cwd,
            stdin: newStdin,
            stdout: self.stdout,
            stderr: self.stderr
        )
    }
    
    /// Sets a different destination for the child process's stdout handle.
    ///
    /// This can be used to channel the child process's output into a file, or
    /// to read it directly from the parent process:
    ///
    /// ```swift
    /// let output = try await Command.findInPath(withName: "echo")!
    ///                               .addArgument("Foo")
    ///                               .setStdout(.pipe)
    ///                               .output
    ///
    /// print(output.stdout)
    /// // Prints 'Foo\n'
    /// ```
    ///
    /// - Parameters:
    ///   - newStdout: An ``OutputDestination``, corresponding to the method of
    ///                output, the child process should use.
    /// - Returns: A new command instance with the given stdout destination set.
    public __consuming func setStdout<NewStdout: OutputDestination>(
        _ newStdout: NewStdout
    ) -> Command<Stdin, NewStdout, Stderr> {
        .init(
            executablePath: self.executablePath,
            arguments: self.arguments,
            environment: self.environment,
            inheritEnvironment: self.inheritEnvironment,
            cwd: self.cwd,
            stdin: self.stdin,
            stdout: newStdout,
            stderr: self.stderr
        )
    }
    
    /// Sets a different destination for the child process's stderr handle.
    ///
    /// This can be used to channel the child process's error output into a
    /// file, or to read it directly from the parent process:
    ///
    /// ```swift
    /// let output = try await Command.findInPath(withName: "cat")!
    ///         .addArgument("non_existing.txt")
    ///         .setStderr(.pipe)
    ///         .output
    ///
    /// print(output.stderr)
    /// // Prints 'cat: non_existing.txt: No such file or directory\n'
    /// // or similar
    /// ```
    ///
    /// - Parameters:
    ///   - newStderr: An ``OutputDestination``, corresponding to the method of
    ///                error output, the child process should use.
    /// - Returns: A new command instance with the given stderr destination set.
    public __consuming func setStderr<NewStderr: OutputDestination>(
        _ newStderr: NewStderr
    ) -> Command<Stdin, Stdout, NewStderr> {
        .init(
            executablePath: self.executablePath,
            arguments: self.arguments,
            environment: self.environment,
            inheritEnvironment: self.inheritEnvironment,
            cwd: self.cwd,
            stdin: self.stdin,
            stdout: self.stdout,
            stderr: newStderr
        )
    }


    /// Executes the command as a child process, returning a handle to it.
    ///
    /// By default, stdin, stdout, and stderr are inherited from the parent
    /// process.
    ///
    /// - Returns: A handle to the child process.
    public func spawn() throws -> ChildProcess<Stdin, Stdout, Stderr> {
        try .spawn(withCommand: self)
    }

    
    /// Executes the command as a child process, waits for it to complete, and
    /// returns its exit status.
    ///
    /// This blocks the current thread until the child process has terminated.
    ///
    /// By default, stdin, stdout, and stderr are inherited from the parent
    /// process.
    ///
    /// - Returns: The exit status of the child process.
    @discardableResult
    public func wait() throws -> ExitStatus {
        try self.spawn().wait()
    }
    
    /// Executes the command as a child process, waits for it to complete, and
    /// returns its exit status.
    ///
    /// This doesn't block the current thread and allows other tasks to run
    /// before the child process terminates.
    ///
    /// By default, stdin, stdout, and stderr are inherited from the parent
    /// process.
    public var status: ExitStatus {
        get async throws {
            try await self.spawn().status
        }
    }
}

extension Command where Stdout == UnspecifiedOutputDestination {
    /// Executes the command as a child process, waits for it to complete, and
    /// returns its collected output.
    ///
    /// This blocks the current thread until the child process has terminated.
    ///
    /// By default, stdout and stderr are captured (and used to provide the re-
    /// sulting output), while stdin is connected to `/dev/null`.
    ///
    /// - Note: This method can only be called when stdout is either still
    ///         unspecfied or when it is piped.
    ///
    /// - Returns: The collected output of the child process.
    public func waitForOutput() throws -> ProcessOutput {
        if Stdin.self == UnspecifiedInputSource.self {
            if Stderr.self == UnspecifiedInputSource.self {
                return try self.setStdin(.null)
                               .setStdout(.pipe)
                               .setStderr(.pipe)
                               .spawn()
                               .waitWithOutput()
            } else {
                return try self.setStdin(.null)
                               .setStdout(.pipe)
                               .spawn()
                               .waitWithOutput()
            }
        } else {
            if Stderr.self == UnspecifiedInputSource.self {
                return try self.setStdout(.pipe)
                               .setStderr(.pipe)
                               .spawn()
                               .waitWithOutput()
            } else {
                return try self.setStdout(.pipe)
                               .spawn()
                               .waitWithOutput()
            }
        }
    }

    /// Executes the command as a child process, waits for it to complete, and
    /// returns its collected stdout data.
    ///
    /// This blocks the current thread until the child process has terminated.
    ///
    /// By default, stdout and stderr are captured (and used to provide the re-
    /// sulting output), while stdin is connected to `/dev/null`.
    ///
    /// - Note: This method can only be called when stdout is either still
    ///         unspecfied or when it is piped.
    ///
    /// - Returns: The collected stdout data of the child process.
    public func waitForOutputData() throws -> Data {
        try self.waitForOutput().stdoutData
    }
    
    /// Executes the command as a child process, waits for it to complete, and
    /// returns its collected output.
    ///
    /// This doesn't block the current thread and allows other tasks to run
    /// before the child process terminates.
    ///
    /// By default, stdout and stderr are captured (and used to provide the re-
    /// sulting output), while stdin is connected to `/dev/null`.
    ///
    /// - Note: This accessor can only be called when stdout is either still
    ///         unspecfied or when it is piped.
    public var output: ProcessOutput {
        get async throws {
            if Stdin.self == UnspecifiedInputSource.self {
                if Stderr.self == UnspecifiedInputSource.self {
                    return try await self.setStdin(.null)
                                         .setStdout(.pipe)
                                         .setStderr(.pipe)
                                         .spawn()
                                         .output
                } else {
                    return try await self.setStdin(.null)
                                         .setStdout(.pipe)
                                         .spawn()
                                         .output
                }
            } else {
                if Stderr.self == UnspecifiedInputSource.self {
                    return try await self.setStdout(.pipe)
                                         .setStderr(.pipe)
                                         .spawn()
                                         .output
                } else {
                    return try await self.setStdout(.pipe)
                                         .spawn()
                                         .output
                }
            }
        }
    }
    
    /// Executes the command as a child process, waits for it to complete, and
    /// returns its collected stdout data.
    ///
    /// This doesn't block the current thread and allows other tasks to run
    /// before the child process terminates.
    ///
    /// By default, stdout and stderr are captured (and used to provide the re-
    /// sulting output), while stdin is connected to `/dev/null`.
    ///
    /// - Note: This accessor can only be called when stdout is either still
    ///         unspecfied or when it is piped.
    public var outputData: Data {
        get async throws {
            try await self.output.stdoutData
        }
    }
}

extension Command where Stdout == PipeOutputDestination {
    /// Executes the command as a child process, waits for it to complete, and
    /// returns its collected output.
    ///
    /// This blocks the current thread until the child process has terminated.
    ///
    /// By default, stdout and stderr are captured (and used to provide the re-
    /// sulting output), while stdin is connected to `/dev/null`.
    ///
    /// - Note: This method can only be called when stdout is either still
    ///         unspecfied or when it is piped.
    ///
    /// - Returns: The collected output of the child process.
    public func waitForOutput() throws -> ProcessOutput {
        if Stdin.self == UnspecifiedInputSource.self {
            if Stderr.self == UnspecifiedInputSource.self {
                return try self.setStdin(.null)
                               .setStderr(.pipe)
                               .spawn()
                               .waitWithOutput()
            } else {
                return try self.setStdin(.null)
                               .spawn()
                               .waitWithOutput()
            }
        } else {
            if Stderr.self == UnspecifiedInputSource.self {
                return try self.setStderr(.pipe)
                               .spawn()
                               .waitWithOutput()
            } else {
                return try self.spawn()
                               .waitWithOutput()
            }
        }
    }

    /// Executes the command as a child process, waits for it to complete, and
    /// returns its collected stdout data.
    ///
    /// This blocks the current thread until the child process has terminated.
    ///
    /// By default, stdout and stderr are captured (and used to provide the re-
    /// sulting output), while stdin is connected to `/dev/null`.
    ///
    /// - Note: This method can only be called when stdout is either still
    ///         unspecfied or when it is piped.
    ///
    /// - Returns: The collected stdout data of the child process.
    public func waitForOutputData() throws -> Data {
        try self.waitForOutput().stdoutData
    }
    
    /// Executes the command as a child process, waits for it to complete, and
    /// returns its collected output.
    ///
    /// This doesn't block the current thread and allows other tasks to run
    /// before the child process terminates.
    ///
    /// By default, stdout and stderr are captured (and used to provide the re-
    /// sulting output), while stdin is connected to `/dev/null`.
    ///
    /// - Note: This accessor can only be called when stdout is either still
    ///         unspecfied or when it is piped.
    public var output: ProcessOutput {
        get async throws {
            if Stdin.self == UnspecifiedInputSource.self {
                if Stderr.self == UnspecifiedInputSource.self {
                    return try await self.setStdin(.null)
                                         .setStderr(.pipe)
                                         .spawn()
                                         .output
                } else {
                    return try await self.setStdin(.null)
                                         .spawn()
                                         .output
                }
            } else {
                if Stderr.self == UnspecifiedInputSource.self {
                    return try await self.setStderr(.pipe)
                                         .spawn()
                                         .output
                } else {
                    return try await self.spawn()
                                         .output
                }
            }
        }
    }
    
    /// Executes the command as a child process, waits for it to complete, and
    /// returns its collected stdout data.
    ///
    /// This doesn't block the current thread and allows other tasks to run
    /// before the child process terminates.
    ///
    /// By default, stdout and stderr are captured (and used to provide the re-
    /// sulting output), while stdin is connected to `/dev/null`.
    ///
    /// - Note: This accessor can only be called when stdout is either still
    ///         unspecfied or when it is piped.
    public var outputData: Data {
        get async throws {
            try await self.output.stdoutData
        }
    }
}
