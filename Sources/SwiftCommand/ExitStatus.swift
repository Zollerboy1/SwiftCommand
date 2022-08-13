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
    internal static let terminatedBySignal = ExitStatus(status: .terminatedBySignal)

    internal static func error(exitCode: Int32) -> ExitStatus {
        .init(status: .error(exitCode))
    }


    public var terminatedSuccessfully: Bool { self.status == .success }

    public var exitCode: Int32? {
        if case let .error(exitCode) = self.status {
            return exitCode
        } else {
            return nil
        }
    }
}
