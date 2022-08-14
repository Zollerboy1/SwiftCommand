public struct AsyncCharacterSequence<Base>: AsyncSequence
where Base: AsyncSequence, Base.Element == UInt8 {
    @usableFromInline
    internal typealias Underlying = AsyncUnicodeScalarSequence<Base>
    
    public typealias Element = Character
    
    public struct AsyncIterator: AsyncIteratorProtocol {
        @usableFromInline
        internal var _remaining: Underlying.AsyncIterator
        @usableFromInline
        internal var _accumulator: String
        
        fileprivate init(_underlying underlying: Underlying.AsyncIterator) {
            self._remaining = underlying
            self._accumulator = ""
        }
        
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
