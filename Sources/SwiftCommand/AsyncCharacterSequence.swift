/// A non-blocking sequence of `Character`s created by decoding the elements of
/// `Base` as utf-8.
public struct AsyncCharacterSequence<Base>: AsyncSequence
where Base: AsyncSequence, Base.Element == UInt8 {
    @usableFromInline
    internal typealias Underlying = AsyncUnicodeScalarSequence<Base>
    
    /// The type of element produced by this asynchronous sequence.
    public typealias Element = Character
    
    /// The type of asynchronous iterator that produces elements of this
    /// asynchronous sequence.
    public struct AsyncIterator: AsyncIteratorProtocol {
        @usableFromInline
        internal var _remaining: Underlying.AsyncIterator
        @usableFromInline
        internal var _accumulator: String
        
        fileprivate init(_underlying underlying: Underlying.AsyncIterator) {
            self._remaining = underlying
            self._accumulator = ""
        }
        
        /// Asynchronously advances to the next element and returns it, or ends
        /// the sequence if there is no next element.
        ///
        /// - Returns: The next element, if it exists, or `nil` to signal the
        ///            end of the sequence.
        @inlinable
        public mutating func next() async rethrows -> Character? {
            while let scalar = try await self._remaining.next() {
                self._accumulator.unicodeScalars.append(scalar)
                if self._accumulator.count > 1 {
                    return self._accumulator.removeFirst()
                }
            }
            
            if self._accumulator.count > 0 {
                return self._accumulator.removeFirst()
            } else {
                return nil
            }
        }
    }
    
    private let underlying: Underlying
    
    internal init(_base base: Base) {
        self.underlying = .init(_base: base)
    }
    
    /// Creates the asynchronous iterator that produces elements of this
    /// asynchronous sequence.
    ///
    /// - Returns: An instance of the `AsyncIterator` type used to produce
    ///            elements of the asynchronous sequence.
    public func makeAsyncIterator() -> AsyncIterator {
        return AsyncIterator(_underlying: self.underlying.makeAsyncIterator())
    }
}

extension AsyncSequence where Self.Element == UInt8 {
    /// A non-blocking sequence of `Character`s created by decoding the
    /// elements of `self` as utf-8.
    public var characters: AsyncCharacterSequence<Self> {
        AsyncCharacterSequence(_base: self)
    }
}
