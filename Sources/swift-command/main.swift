// Used to test the SwiftCommand public interface

import Foundation
import SwiftCommand

// Echo the lines you input
Task<Void, Swift.Error> {
    let lines = FileHandle.standardInput.bytes.lines
    for try await line in lines {
        print("🎺 \(line)")
    }
}

RunLoop.main.run()

