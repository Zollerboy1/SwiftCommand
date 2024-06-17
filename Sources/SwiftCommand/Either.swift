/// The enum ``Either`` with cases ``Either/first(_:)`` and
/// ``Either/second(_:)`` is a general purpose sum type with two cases.
///
/// The ``Either`` type is symmetric and treats its cases the same way, without
/// preference (for representing success or error, use the `Result` enum from
/// Swift's standard library instead).
public enum Either<First, Second> {
    /// A value of type `First`.
    case first(First)
    /// A value of type `Second`.
    case second(Second)

    /// A convenience initializer for when no type context is available
    public init(first: First) {
        self = .first(first)
    }

    /// A convenience initializer for when no type context is available
    public init(second: Second) {
        self = .second(second)
    }

    /// Returns `true` if the value is the ``Either/first(_:)`` case.
    public var isFirst: Bool {
        guard case .first = self else {
            return false
        }
        return true
    }

    /// Converts the first case of `Either<F, S>` to `F?`.
    public var first: First? {
        guard case .first(let first) = self else {
            return nil
        }
        return first
    }

    /// Returns `true` if the value is the ``Either/second(_:)`` case.
    public var isSecond: Bool {
        guard case .second = self else {
            return false
        }
        return true
    }

    /// Converts the second case of `Either<F, S>` to `S?`.
    public var second: Second? {
        guard case .second(let second) = self else {
            return nil
        }
        return second
    }

    /// Converts `Either<F, S>` to `Either<S, F>`.
    public var flipped: Either<Second, First> {
        switch self {
        case .first(let first):
            return .second(first)
        case .second(let second):
            return .first(second)
        }
    }

    /// Applies the closure `transformFirst` to the value in case
    /// ``Either/first(_:)`` if it is present rewrapping the result in
    /// ``Either/first(_:)``.
    ///
    /// - Parameter transformFirst: A closure transforming a value of type
    ///                             `First` into a value of type `NewFirst`.
    /// - Returns: A new instance of ``Either``, containing either the result
    ///            of the `transformFirst` closure or the value in case
    ///            ``Either/second(_:)``.
    public func mapFirst<NewFirst>(
        _ transformFirst: (First) throws -> NewFirst
    ) rethrows -> Either<NewFirst, Second> {
        switch self {
        case .first(let first):
            return .first(try transformFirst(first))
        case .second(let second):
            return .second(second)
        }
    }

    /// Applies the closure `transformSecond` to the value in case
    /// ``Either/second(_:)`` if it is present rewrapping the result in
    /// ``Either/second(_:)``.
    ///
    /// - Parameter transformSecond: A closure transforming a value of type
    ///                              `Second` into a value of type `NewSecond`.
    /// - Returns: A new instance of ``Either``, containing either the value in
    ///            case ``Either/first(_:)`` or the result of the
    ///            `transformSecond` closure.
    public func mapSecond<NewSecond>(
        _ transformSecond: (Second) throws -> NewSecond
    ) rethrows -> Either<First, NewSecond> {
        switch self {
        case .first(let first):
            return .first(first)
        case .second(let second):
            return .second(try transformSecond(second))
        }
    }
}

extension Either: Equatable where First: Equatable, Second: Equatable {}
extension Either: Hashable where First: Hashable, Second: Hashable {}
extension Either: Sendable where First: Sendable, Second: Sendable {}
