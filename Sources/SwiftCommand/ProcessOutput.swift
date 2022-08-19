import Foundation

/// The output of a finished child process.
///
/// This is returned by either the ``Command/waitForOutput()-5zvk9`` method (or
/// the asynchronous ``Command/output-9f0ug`` accessor) of a ``Command``, or the
/// ``ChildProcess/waitWithOutput()`` method (or the asynchronous
/// ``ChildProcess/output`` accessor) of a ``ChildProcess``.
public struct ProcessOutput: Equatable, Sendable {
    /// The exit status of the child process.
    public let status: ExitStatus
    /// The output `Data`, captured from the stdout handle of the child process.
    public let stdoutData: Data
    /// The output `String`, captured from the stdout handle of the child
    /// process.
    public let stdout: String
    /// The output `Data`, captured from the stderr handle of the child process,
    /// if stderr was piped; `nil` otherwise.
    public let stderrData: Data?
    /// The output `String`, captured from the stderr handle of the child
    /// process, if stderr was piped; `nil` otherwise.
    public let stderr: String?

    internal init(
        status: ExitStatus,
        stdoutData: Data,
        stdout: String,
        stderrData: Data?,
        stderr: String?
    ) {
        self.status = status
        self.stdoutData = stdoutData
        self.stdout = stdout
        self.stderrData = stderrData
        self.stderr = stderr
    }
}
