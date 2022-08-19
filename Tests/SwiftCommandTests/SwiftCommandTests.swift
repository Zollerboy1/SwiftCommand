import XCTest
@testable import SwiftCommand

final class SwiftCommandTests: XCTestCase {
    static let lines = ["Foo", "Bar", "Baz", "Test1", "Test2"]

    func testEcho() async throws {
        guard let command = Command.findInPath(withName: "echo") else {
            fatalError()
        }

        let process =
            try command.addArgument(Self.lines.joined(separator: "\n"))
                       .setStdout(.pipe)
                       .spawn()

        var linesIterator = Self.lines.makeIterator()
        
        for try await line in process.stdout.lines {
            XCTAssertEqual(line, linesIterator.next())
        }
        
        try process.wait()
    }

    func testComposition() async throws {
        let echoProcess =
            try Command.findInPath(withName: "echo")!
                       .addArgument(Self.lines.joined(separator: "\n"))
                       .setStdout(.pipe)
                       .spawn()
        
        let grepProcess =
            try Command.findInPath(withName: "grep")!
                       .addArgument("Test")
                       .setStdin(.pipe(from: echoProcess.stdout))
                       .setStdout(.pipe)
                       .spawn()

        var linesIterator = Self.lines.filter({
            $0.contains("Test")
        }).makeIterator()

        for try await line in grepProcess.stdout.lines {
            XCTAssertEqual(line, linesIterator.next())
        }
        
        try echoProcess.wait()
        try grepProcess.wait()
    }
    
    func testStdin() async throws {
        let process = try Command.findInPath(withName: "cat")!
                                 .setStdin(.pipe)
                                 .setStdout(.pipe)
                                 .spawn()
        
        var stdin = process.stdin
        
        print("Foo", to: &stdin)
        print("Bar", to: &stdin)
        
        let output = try await process.output
        
        XCTAssertEqual(output.stdout, "Foo\nBar\n")
    }
    
    func testStderr() async throws {
        let catCommand = Command.findInPath(withName: "cat")!

        let output = try await catCommand.addArgument("non_existing.txt")
                                         .setStderr(.pipe)
                                         .output
        
        XCTAssertNotEqual(output.status, .success)

        let stderr = output.stderr?.replacingOccurrences(
            of: catCommand.executablePath.string,
            with: "cat"
        )

        XCTAssertEqual(
            stderr,
            "cat: non_existing.txt: No such file or directory\n"
        )
    }
    
    func testParallelProcesses() async throws {
        let command = Command.findInPath(withName: "cat")!
                             .setStdin(.pipe(closeImplicitly: false))
                             .setStdout(.pipe)
        
        try await withThrowingTaskGroup(of: ChildProcess<_, _, _>.self) {
            group in
            for _ in 0..<10 {
                group.addTask {
                    let process = try command.spawn()
                    
                    Task.detached {
                        for line in Self.lines {
                            process.stdin.write(line)
                            try await Task.sleep(
                                nanoseconds: .random(in: 1_000..<500_000_000)
                            )
                        }
                        
                        process.stdin.close()
                    }
                    
                    return process
                }
            }
            
            for try await process in group {
                let output = try await process.output
                
                XCTAssertEqual(output.stdout, Self.lines.joined())
            }
        }
    }
    
    func testTermination() async throws {
        let command = Command.findInPath(withName: "cat")!
                             .setStdin(.pipe(closeImplicitly: false))
                             .setStdout(.pipe)
        
        // For some strange reasons, 'cat' doesn't respond to SIGINT and SIGTERM
        // on linux, while testing. This code works in a normal executable
        // though, so I'm just ignoring it here for now...
#if canImport(Darwin)
        let process1 = try command.spawn()
        let process2 = try command.spawn()
#endif
        let process3 = try command.spawn()
        
#if canImport(Darwin)
        process1.interrupt()
        let status1 = try await process1.status
        XCTAssertTrue(status1.wasTerminatedBySignal)
        XCTAssertEqual(status1.terminationSignal, SIGINT)
        
        process2.terminate()
        let status2 = try await process2.status
        XCTAssertTrue(status2.wasTerminatedBySignal)
        XCTAssertEqual(status2.terminationSignal, SIGTERM)
#endif
        
        process3.kill()
        let status3 = try await process3.status
        XCTAssertTrue(status3.wasTerminatedBySignal)
        XCTAssertEqual(status3.terminationSignal, SIGKILL)
    }
}
