import XCTest
@testable import SwiftCommand

final class SwiftCommandTests: XCTestCase {
    static let lines = ["Foo", "Bar", "Baz", "Test1", "Test2"]

    func testEcho() async throws {
        guard let command = Command.findInPath(withName: "echo") else {
            fatalError()
        }

        let process = try command.addArgument(Self.lines.joined(separator: "\n"))
                                 .setStdout(.pipe)
                                 .spawn()

        var linesIterator = Self.lines.makeIterator()

        if #available(macOS 12.0, *) {
            for try await line in process.stdout.lines {
                XCTAssertEqual(line, linesIterator.next())
            }
        } else {
            guard let data = process.stdout.readToEnd(),
                  let output = String(data: data, encoding: .utf8) else {
                fatalError()
            }

            for line in output.split(separator: "\n").map(String.init) {
                XCTAssertEqual(line, linesIterator.next())
            }
        }
    }

    func testComposition() async throws {
        let echoProcess = try Command.findInPath(withName: "echo")!
                                     .addArgument(Self.lines.joined(separator: "\n"))
                                     .setStdout(.pipe)
                                     .spawn()
        
        let grepProcess = try Command.findInPath(withName: "grep")!
                                     .addArgument("Test")
                                     .setStdin(.pipe(from: echoProcess.stdout))
                                     .setStdout(.pipe)
                                     .spawn()

        var linesIterator = Self.lines.filter({ $0.contains("Test") }).makeIterator()

        if #available(macOS 12.0, *) {
            for try await line in grepProcess.stdout.lines {
                XCTAssertEqual(line, linesIterator.next())
            }
        } else {
            guard let data = grepProcess.stdout.readToEnd(),
                  let output = String(data: data, encoding: .utf8) else {
                fatalError()
            }

            for line in output.split(separator: "\n").map(String.init) {
                XCTAssertEqual(line, linesIterator.next())
            }
        }
    }
    
    func testStderr() async throws {
        let output = try await Command.findInPath(withName: "cat")!
                                      .addArgument("non_existing.txt")
                                      .setStderr(.pipe)
                                      .output
        
        XCTAssertNotEqual(output.status, .success)
        XCTAssertEqual(output.stderr, "cat: non_existing.txt: No such file or directory\n")
    }
}
