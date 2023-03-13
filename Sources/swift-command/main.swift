// Used to test the SwiftCommand public interface

import Foundation
import SwiftCommand

// Echo the lines you input
Task<Void, Swift.Error> {
    let bytes: SwiftCommand.AsyncBytes = FileHandle.standardInput.bytes
    for try await line in bytes.lines {
        print("🎺 \(line)")
    }
}

RunLoop.main.run()

