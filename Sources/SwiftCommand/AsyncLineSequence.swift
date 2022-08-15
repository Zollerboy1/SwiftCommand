/// A non-blocking sequence of newline-separated `String`s created by decoding
/// the elements of `Base` as utf-8.
public struct AsyncLineSequence<Base>: AsyncSequence
where Base: AsyncSequence, Base.Element == UInt8 {
    /// The type of element produced by this asynchronous sequence.
    public typealias Element = String
    
    /// The type of asynchronous iterator that produces elements of this
    /// asynchronous sequence.
    public struct AsyncIterator: AsyncIteratorProtocol {
        public typealias Element = String
        
        @usableFromInline
        internal var _base: Base.AsyncIterator
        @usableFromInline
        internal var _buffer: Array<UInt8>
        @usableFromInline
        internal var _leftover: UInt8?
        
        internal init(_base base: Base.AsyncIterator) {
            self._base = base
            self._buffer = []
            self._leftover = nil
        }
        
        /// Asynchronously advances to the next element and returns it, or ends
        /// the sequence if there is no next element.
        ///
        /// - Returns: The next element, if it exists, or `nil` to signal the
        ///            end of the sequence.
        @inlinable
        public mutating func next() async rethrows -> String? {
            /*
             0D 0A: CR-LF
             0A | 0B | 0C | 0D: LF, VT, FF, CR
             E2 80 A8:  U+2028 (LINE SEPARATOR)
             E2 80 A9:  U+2029 (PARAGRAPH SEPARATOR)
             */
            let _CR: UInt8 = 0x0D
            let _LF: UInt8 = 0x0A
            let _NEL_PREFIX: UInt8 = 0xC2
            let _NEL_SUFFIX: UInt8 = 0x85
            let _SEPARATOR_PREFIX: UInt8 = 0xE2
            let _SEPARATOR_CONTINUATION: UInt8 = 0x80
            let _SEPARATOR_SUFFIX_LINE: UInt8 = 0xA8
            let _SEPARATOR_SUFFIX_PARAGRAPH: UInt8 = 0xA9
            
            func yield() -> String? {
                defer {
                    self._buffer.removeAll(keepingCapacity: true)
                }
                
                if self._buffer.isEmpty {
                    return nil
                }
                
                return String(decoding: self._buffer, as: UTF8.self)
            }
            
            func nextByte() async throws -> UInt8? {
                defer {
                    self._leftover = nil
                }
                
                if let leftover = self._leftover {
                    return leftover
                }
                
                return try await self._base.next()
            }
            
            while let first = try await nextByte() {
                switch first {
                case _CR:
                    let result = yield()
                    // Swallow up any subsequent LF
                    guard let next = try await self._base.next() else {
                        // if we ran out of bytes, the last byte was a CR
                        return result
                    }
                    
                    if next != _LF {
                        self._leftover = next
                    }
                    
                    if let result = result {
                        return result
                    }
                    
                    continue
                case _LF..<_CR:
                    guard let result = yield() else {
                        continue
                    }
                    
                    return result
                case _NEL_PREFIX:
                    // this may be used to compose other UTF8 characters
                    guard let next = try await self._base.next() else {
                        // technically invalid UTF8 but it should be repaired
                        // to "\u{FFFD}"
                        self._buffer.append(first)
                        return yield()
                    }
                    
                    if next != _NEL_SUFFIX {
                        self._buffer.append(first)
                        self._buffer.append(next)
                    } else {
                        guard let result = yield() else {
                            continue
                        }
                        
                        return result
                    }
                case _SEPARATOR_PREFIX:
                    // Try to read: 80 [A8 | A9].
                    // If we can't, then we put the byte in the buffer for
                    // error correction
                    guard let next = try await self._base.next() else {
                        self._buffer.append(first)
                        return yield()
                    }
                    
                    guard next == _SEPARATOR_CONTINUATION else {
                        self._buffer.append(first)
                        self._buffer.append(next)
                        continue
                    }
                    
                    guard let fin = try await self._base.next() else {
                        self._buffer.append(first)
                        self._buffer.append(next)
                        return yield()
                    }
                    
                    guard fin == _SEPARATOR_SUFFIX_LINE
                            || fin == _SEPARATOR_SUFFIX_PARAGRAPH else {
                        self._buffer.append(first)
                        self._buffer.append(next)
                        self._buffer.append(fin)
                        continue
                    }
                    
                    if let result = yield() {
                        return result
                    }
                    
                    continue
                default:
                    self._buffer.append(first)
                }
            }
            // Don't emit an empty newline when there is no more content
            // (e.g. end of file)
            if !self._buffer.isEmpty {
                return yield()
            }
            
            return nil
        }
        
    }
    
    private let base: Base
    
    internal init(_base base: Base) {
        self.base = base
    }
    
    /// Creates the asynchronous iterator that produces elements of this
    /// asynchronous sequence.
    ///
    /// - Returns: An instance of the `AsyncIterator` type used to produce
    ///            elements of the asynchronous sequence.
    public func makeAsyncIterator() -> AsyncIterator {
        return AsyncIterator(_base: self.base.makeAsyncIterator())
    }
}

extension AsyncSequence where Self.Element == UInt8 {
    /// A non-blocking sequence of newline-separated `String`s created by
    /// decoding the elements of `self` as utf-8.
    public var lines: AsyncLineSequence<Self> {
        AsyncLineSequence(_base: self)
    }
}
