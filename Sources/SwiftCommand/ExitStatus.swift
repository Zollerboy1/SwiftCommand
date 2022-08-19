/// Describes the result of a child process after it has terminated.
public struct ExitStatus: Equatable, Sendable {
    private enum Status: Equatable, Sendable {
        case success
#if os(Windows)
        case terminatedBySignal
#else
        case terminatedBySignal(Int32)
#endif
        case error(Int32)
    }

    private let status: Status

    private init(status: Status) {
        self.status = status
    }


    internal static let success = ExitStatus(status: .success)

#if os(Windows)
    internal static let terminatedBySignal =
        ExitStatus(status: .terminatedBySignal)
#else
    internal static func terminatedBySignal(signal: Int32) -> ExitStatus {
        .init(status: .terminatedBySignal(signal))
    }
#endif

    internal static func error(exitCode: Int32) -> ExitStatus {
        .init(status: .error(exitCode))
    }


    /// Indicates, if termination of the child process was successful.
    ///
    /// Signal termination is not considered a success, and success is defined
    /// as a zero exit status.
    public var terminatedSuccessfully: Bool { self.status == .success }

    /// Indicates, if the child process was terminated by a signal.
    public var wasTerminatedBySignal: Bool {
        if case .terminatedBySignal = self.status {
            return true
        } else {
            return false
        }
    }

    /// Returns the exit code of the child process, if any.
    ///
    /// In Unix terms the return value is the exit code: the value passed to
    /// `exit`, if the process finished by calling `exit`. Note that on Unix the
    /// exit code is truncated to 8 bits, and that values that didn’t come from
    /// a program’s call to `exit` may be invented by the runtime system (often,
    /// for example, 255, 254, 127 or 126).
    ///
    /// This will return `nil` if the child process terminated successfully
    /// (this can also be checked using ``ExitStatus/terminatedSuccessfully``)
    /// or if it was terminated by a signal.
    public var exitCode: Int32? {
        if case let .error(exitCode) = self.status {
            return exitCode
        } else {
            return nil
        }
    }

#if os(Windows)
    @available(Windows, unavailable)
    public var terminationSignal: Int32? {
        nil
    }
#else
    public var terminationSignal: Int32? {
        if case let .terminatedBySignal(signal) = self.status {
            return signal
        } else {
            return nil
        }
    }
#endif
}
