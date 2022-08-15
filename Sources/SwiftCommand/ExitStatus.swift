/// Describes the result of a child process after it has terminated.
public struct ExitStatus: Equatable, Sendable {
    private enum Status: Equatable, Sendable {
        case success
        case terminatedBySignal
        case error(Int32)
    }

    private let status: Status

    private init(status: Status) {
        self.status = status
    }


    internal static let success = ExitStatus(status: .success)
    internal static let terminatedBySignal =
        ExitStatus(status: .terminatedBySignal)

    internal static func error(exitCode: Int32) -> ExitStatus {
        .init(status: .error(exitCode))
    }


    /// Indicates, if termination of the child process was successful.
    ///
    /// Signal termination is not considered a success, and success is defined
    /// as a zero exit status.
    public var terminatedSuccessfully: Bool { self.status == .success }

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
}
