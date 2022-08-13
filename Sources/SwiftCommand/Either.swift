public enum Either<First, Second> {
    case first(First)
    case second(Second)

    public init(first: First) {
        self = .first(first)
    }

    public init(second: Second) {
        self = .second(second)
    }

    public var first: First? {
        if case let .first(first) = self {
            return first
        } else {
            return nil
        }
    }

    public var second: Second? {
        if case let .second(second) = self {
            return second
        } else {
            return nil
        }
    }
}

extension Either: Equatable where First: Equatable, Second: Equatable {}
extension Either: Hashable where First: Hashable, Second: Hashable {}
extension Either: Sendable where First: Sendable, Second: Sendable {}
