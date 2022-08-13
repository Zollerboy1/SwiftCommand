import Foundation
import SystemPackage

public struct Command<Stdin: InputSource, Stdout: OutputDestination, Stderr: OutputDestination> {
    public enum Error: Swift.Error {
        case executableNotFound
    }

    public let executablePath: FilePath
    public let arguments: [String]
    public let environment: [String: String]
    public let cwd: FilePath?

    internal let inheritEnvironment: Bool

    internal let stdin: Stdin
    internal let stdout: Stdout
    internal let stderr: Stderr

    private init(
        executablePath: FilePath,
        arguments: [String],
        environment: [String: String],
        cwd: FilePath?,
        inheritEnvironment: Bool,
        stdin: Stdin,
        stdout: Stdout,
        stderr: Stderr
    ) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.environment = environment
        self.cwd = cwd

        self.inheritEnvironment = inheritEnvironment

        self.stdin = stdin
        self.stdout = stdout
        self.stderr = stderr
    }

    public init(executablePath: FilePath) throws
    where Stdin == UnspecifiedInputSource,
          Stdout == UnspecifiedOutputDestination,
          Stderr == UnspecifiedOutputDestination {
        guard FileManager.default.isExecutableFile(atPath: executablePath.string) else {
            throw Error.executableNotFound
        }

        self.init(
            executablePath: executablePath,
            arguments: [],
            environment: [:],
            cwd: nil,
            inheritEnvironment: true,
            stdin: .init(),
            stdout: .init(),
            stderr: .init()
        )
    }

    public static func findInPath(withName name: String) -> Command?
    where Stdin == UnspecifiedInputSource,
          Stdout == UnspecifiedOutputDestination,
          Stderr == UnspecifiedOutputDestination {
        guard let environmentPath = ProcessInfo.processInfo.environment["PATH"] else {
            return nil
        }

        guard let executablePath = environmentPath.split(separator: ":").lazy
            .compactMap(FilePath.init(substring:))
            .map({ $0.appending(name) })
            .first(where: { FileManager.default.isExecutableFile(atPath: $0.string) }) else {
            return nil
        }

        return .init(
            executablePath: executablePath,
            arguments: [],
            environment: [:],
            cwd: nil,
            inheritEnvironment: true,
            stdin: .init(),
            stdout: .init(),
            stderr: .init()
        )
    }


    public __consuming func addArguments(_ newArguments: [String]) -> Self {
        .init(
            executablePath: self.executablePath,
            arguments: self.arguments + newArguments,
            environment: self.environment,
            cwd: self.cwd,
            inheritEnvironment: self.inheritEnvironment,
            stdin: self.stdin,
            stdout: self.stdout,
            stderr: self.stderr
        )
    }

    public __consuming func addArguments(_ newArguments: String...) -> Self {
        self.addArguments(newArguments)
    }

    public __consuming func addArgument(_ newArgument: String) -> Self {
        self.addArguments(newArgument)
    }


    public __consuming func addEnvVariable(key: String, value: String) -> Self {
        var newEnvironment = self.environment

        newEnvironment[key] = value

        return .init(
            executablePath: self.executablePath,
            arguments: self.arguments,
            environment: newEnvironment,
            cwd: self.cwd,
            inheritEnvironment: self.inheritEnvironment,
            stdin: self.stdin,
            stdout: self.stdout,
            stderr: self.stderr
        )
    }

    public __consuming func addEnvVariables(_ newEnvironment: [String: String]) -> Self {
        .init(
            executablePath: self.executablePath,
            arguments: self.arguments,
            environment: self.environment.merging(newEnvironment) { old, new in new },
            cwd: self.cwd,
            inheritEnvironment: self.inheritEnvironment,
            stdin: self.stdin,
            stdout: self.stdout,
            stderr: self.stderr
        )
    }

    public __consuming func clearEnv() -> Self {
        .init(
            executablePath: self.executablePath,
            arguments: self.arguments,
            environment: [:],
            cwd: self.cwd,
            inheritEnvironment: false,
            stdin: self.stdin,
            stdout: self.stdout,
            stderr: self.stderr
        )
    }


    public __consuming func setCWD(_ newCWD: FilePath) -> Self {
        .init(
            executablePath: self.executablePath,
            arguments: self.arguments,
            environment: self.environment,
            cwd: newCWD,
            inheritEnvironment: self.inheritEnvironment,
            stdin: self.stdin,
            stdout: self.stdout,
            stderr: self.stderr
        )
    }


    public __consuming func setStdin<NewStdin: InputSource>(_ newStdin: NewStdin) -> Command<NewStdin, Stdout, Stderr> {
        .init(
            executablePath: self.executablePath,
            arguments: self.arguments,
            environment: self.environment,
            cwd: self.cwd,
            inheritEnvironment: self.inheritEnvironment,
            stdin: newStdin,
            stdout: self.stdout,
            stderr: self.stderr
        )
    }

    public __consuming func setStdout<NewStdout: OutputDestination>(_ newStdout: NewStdout) -> Command<Stdin, NewStdout, Stderr> {
        .init(
            executablePath: self.executablePath,
            arguments: self.arguments,
            environment: self.environment,
            cwd: self.cwd,
            inheritEnvironment: self.inheritEnvironment,
            stdin: self.stdin,
            stdout: newStdout,
            stderr: self.stderr
        )
    }

    public __consuming func setStderr<NewStderr: OutputDestination>(_ newStderr: NewStderr) -> Command<Stdin, Stdout, NewStderr> {
        .init(
            executablePath: self.executablePath,
            arguments: self.arguments,
            environment: self.environment,
            cwd: self.cwd,
            inheritEnvironment: self.inheritEnvironment,
            stdin: self.stdin,
            stdout: self.stdout,
            stderr: newStderr
        )
    }


    public func spawn() throws -> ChildProcess<Stdin, Stdout, Stderr> {
        try .spawn(withCommand: self)
    }

    
    @discardableResult
    public func wait() throws -> ExitStatus {
        if Stdin.self == UnspecifiedInputSource.self {
            return try self.setStdin(.null).spawn().wait()
        } else {
            return try self.spawn().wait()
        }
    }
    
    public var status: ExitStatus {
        get async throws {
            if Stdin.self == UnspecifiedInputSource.self {
                return try await self.setStdin(.null).spawn().status
            } else {
                return try await self.spawn().status
            }
        }
    }
}

extension Command where Stdout == UnspecifiedOutputDestination {
    public func waitForOutput() throws -> ProcessOutput {
        if Stdin.self == UnspecifiedInputSource.self {
            return try self.setStdin(.null).setStdout(.pipe).spawn().waitWithOutput()
        } else {
            return try self.setStdout(.pipe).spawn().waitWithOutput()
        }
    }

    public var output: ProcessOutput {
        get async throws {
            if Stdin.self == UnspecifiedInputSource.self {
                return try await self.setStdin(.null).setStdout(.pipe).spawn().output
            } else {
                return try await self.setStdout(.pipe).spawn().output
            }
        }
    }
}

extension Command where Stdout == PipeOutputDestination {
    public func waitForOutput() throws -> ProcessOutput {
        if Stdin.self == UnspecifiedInputSource.self {
            return try self.setStdin(.null).spawn().waitWithOutput()
        } else {
            return try self.spawn().waitWithOutput()
        }
    }

    public var output: ProcessOutput {
        get async throws {
            if Stdin.self == UnspecifiedInputSource.self {
                return try await self.setStdin(.null).spawn().output
            } else {
                return try await self.spawn().output
            }
        }
    }
}
