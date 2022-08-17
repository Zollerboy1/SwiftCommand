import Foundation

fileprivate final actor IOActor {
#if !os(Windows)
    fileprivate func read(
        from fd: Int32,
        into buffer: UnsafeMutableRawBufferPointer
    ) async throws -> Int {
        while true {
#if canImport(Darwin)
            let read = Darwin.read
#elseif canImport(Glibc)
            let read = Glibc.read
#error("Unsupported platform!")
#endif
            let amount = read(fd, buffer.baseAddress, buffer.count)
            if amount >= 0 {
                return amount
            }
            let posixErrno = errno
            if errno != EINTR {
                throw NSError(
                    domain: NSPOSIXErrorDomain,
                    code: Int(posixErrno),
                    userInfo: [:]
                )
            }
        }
    }
#endif
    
    fileprivate func read(
        from handle: FileHandle,
        into buffer: UnsafeMutableRawBufferPointer
    ) async throws -> Int {
        try await withUnsafeThrowingContinuation { continuation in
            handle.readabilityHandler = { handle in
                handle.readabilityHandler = nil
                
                let data: Data
                if #available(macOS 10.15.4, *) {
                    do {
                        guard let _data =
                                try handle.read(upToCount: buffer.count) else {
                            continuation.resume(returning: 0)
                            return
                        }
                        
                        data = _data
                    } catch {
                        continuation.resume(throwing: error)
                        return
                    }
                } else {
                    data = handle.readData(ofLength: buffer.count)
                }
        
                data.copyBytes(to: buffer)
                continuation.resume(returning: data.count)
            }
        }
    }
    
    fileprivate static let `default` = IOActor()
}


@usableFromInline
internal struct _AsyncBytesBuffer {
    private struct Header {
        var readFunction: ((inout _AsyncBytesBuffer) async throws -> Int)? = nil
        var finished = false
    }
    
    private class Storage: ManagedBuffer<Header, UInt8> {
        var finished: Bool {
            get {
                self.header.finished
            }
            set {
                self.header.finished = newValue
            }
        }
    }
    
    fileprivate var readFunction: (inout Self) async throws -> Int {
        get {
            (self.storage as! Storage).header.readFunction!
        }
        set {
            (self.storage as! Storage).header.readFunction = newValue
        }
    }
    
    fileprivate var baseAddress: UnsafeMutableRawPointer {
        (self.storage as! Storage).withUnsafeMutablePointerToElements {
            .init($0)
        }
    }
    
    fileprivate var capacity: Int {
        (self.storage as! Storage).capacity
    }
    
    private var storage: AnyObject? = nil
    
    @usableFromInline
    internal var _nextPointer: UnsafeMutableRawPointer
    @usableFromInline
    internal var _endPointer: UnsafeMutableRawPointer
    
    fileprivate init(_capacity capacity: Int) {
        let s = Storage.create(minimumCapacity: capacity) { _ in
            return Header(readFunction: nil, finished: false)
        }
        
        self.storage = s
        self._nextPointer = s.withUnsafeMutablePointerToElements { .init($0) }
        self._endPointer = self._nextPointer
    }
    
    @inline(never) @usableFromInline
    internal mutating func _reloadBufferAndNext() async throws -> UInt8? {
        let storage = self.storage as! Storage
        if storage.finished {
            return nil
        }
        
        try Task.checkCancellation()
        
        self._nextPointer = storage.withUnsafeMutablePointerToElements {
            .init($0)
        }
        
        do {
            let readSize = try await self.readFunction(&self)
            if readSize == 0 {
                storage.finished = true
            }
        } catch {
            storage.finished = true
            throw error
        }
        
        return try await self._next()
    }
    
    @inlinable @inline(__always)
    internal mutating func _next() async throws -> UInt8? {
        if _fastPath(self._nextPointer != self._endPointer) {
            let byte = self._nextPointer.load(fromByteOffset: 0, as: UInt8.self)
            self._nextPointer = self._nextPointer + 1
            return byte
        }
        
        return try await self._reloadBufferAndNext()
    }
}

extension FileHandle {
    @usableFromInline
    internal struct CustomAsyncBytes: AsyncSequence {
        @usableFromInline
        internal typealias Element = UInt8
        
        @usableFromInline
        internal struct AsyncIterator: AsyncIteratorProtocol {
            static let bufferSize = 16384
            
            @usableFromInline
            internal var _buffer: _AsyncBytesBuffer
            
            fileprivate init(file: FileHandle) {
                self._buffer = _AsyncBytesBuffer(_capacity: Self.bufferSize)
                
#if !os(Windows)
                let fileDescriptor = file.fileDescriptor
#endif
                
                self._buffer.readFunction = { buf in
                    buf._nextPointer = buf.baseAddress
                    
                    let capacity = buf.capacity
                    
                    let bufPtr = UnsafeMutableRawBufferPointer(
                        start: buf._nextPointer,
                        count: capacity
                    )
                    
#if os(Windows)
                    let readSize = try await IOActor.default.read(
                        from: file,
                        into: bufPtr
                    )
#else
                    let readSize: Int
                    if fileDescriptor >= 0 {
                        readSize = try await IOActor.default.read(
                            from: fileDescriptor,
                            into: bufPtr
                        )
                    } else {
                        readSize = try await IOActor.default.read(
                            from: file,
                            into: bufPtr
                        )
                    }
#endif
                    
                    buf._endPointer = buf._nextPointer + readSize
                    return readSize
                }
            }
            
            @inlinable @inline(__always)
            public mutating func next() async throws -> UInt8? {
                return try await self._buffer._next()
            }
        }
        
        var handle: FileHandle
        
        fileprivate init(file: FileHandle) {
            handle = file
        }
        
        @usableFromInline
        internal func makeAsyncIterator() -> AsyncIterator {
            .init(file: handle)
        }
    }
    
    internal var bytes: CustomAsyncBytes {
        return CustomAsyncBytes(file: self)
    }
}
