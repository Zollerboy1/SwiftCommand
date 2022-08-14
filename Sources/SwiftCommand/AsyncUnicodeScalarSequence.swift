public struct AsyncUnicodeScalarSequence<Base>: AsyncSequence
where Base: AsyncSequence, Base.Element == UInt8 {
    public typealias Element = UnicodeScalar
    
    public struct AsyncIterator: AsyncIteratorProtocol {
        @usableFromInline
        internal var _base: Base.AsyncIterator
        @usableFromInline
        internal var _leftover: UInt8?
        
        internal init(_base base: Base.AsyncIterator) {
            self._base = base
            self._leftover = nil
        }
        
        @inlinable
        internal func _expectedContinuationCountForByte(_ byte: UInt8) -> Int? {
            if byte & 0b11100000 == 0b11000000 {
                return 1
            }
            
            if byte & 0b11110000 == 0b11100000 {
                return 2
            }
            
            if byte & 0b11111000 == 0b11110000 {
                return 3
            }
            
            if byte & 0b10000000 == 0b00000000 {
                return 0
            }
            
            if byte & 0b11000000 == 0b10000000 {
                // is a continuation itself
                return nil
            }
            
            // is an invalid value
            return nil
        }
        
        @inlinable
        internal mutating func _nextComplexScalar(_ first: UInt8) async rethrows
        -> UnicodeScalar? {
            guard let expectedContinuationCount =
                    self._expectedContinuationCountForByte(first) else {
                // We only reach here for invalid UTF8, so just return a
                // replacement character directly
                return "\u{FFFD}"
            }
            
            var bytes: (UInt8, UInt8, UInt8, UInt8) = (first, 0, 0, 0)
            var numContinuations = 0
            while numContinuations < expectedContinuationCount,
                  let next = try await self._base.next() {
                guard UTF8.isContinuation(next) else {
                    // We read one more byte than we needed due to an invalid
                    // missing continuation byte. Store it in `leftover` for
                    // next time
                    self._leftover = next
                    break
                }
                
                numContinuations += 1
                withUnsafeMutableBytes(of: &bytes) {
                    $0[numContinuations] = next
                }
            }
            return withUnsafeBytes(of: &bytes) {
                return String(decoding: $0, as: UTF8.self).unicodeScalars.first
            }
        }
        
        @inlinable
        public mutating func next() async rethrows -> UnicodeScalar? {
            if let leftover = self._leftover {
                self._leftover = nil
                return try await self._nextComplexScalar(leftover)
            }
            if let byte = try await self._base.next() {
                if UTF8.isASCII(byte) {
                    _onFastPath()
                    return UnicodeScalar(byte)
                }
                
                return try await self._nextComplexScalar(byte)
            }
            
            return nil
        }
    }
    
    private let base: Base
    
    internal init(_base base: Base) {
        self.base = base
    }
    
    public func makeAsyncIterator() -> AsyncIterator {
        return AsyncIterator(_base: base.makeAsyncIterator())
    }
}

extension AsyncSequence where Self.Element == UInt8 {
    /// A non-blocking sequence of `UnicodeScalar`s created by decoding the
    /// elements of `self` as utf-8.
    public var unicodeScalars: AsyncUnicodeScalarSequence<Self> {
        AsyncUnicodeScalarSequence(_base: self)
    }
}
