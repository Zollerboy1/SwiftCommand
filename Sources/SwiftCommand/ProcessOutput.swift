public struct ProcessOutput: Equatable, Sendable {
    public let status: ExitStatus
    public let stdout: String
    public let stderr: String?

    internal init(status: ExitStatus, stdout: String, stderr: String?) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }
}
