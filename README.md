# SwiftCommand

A wrapper around `Foundation.Process`, inspired by Rust's
`std::process::Command`. This package makes it easy to call command line
programs and handle their I/O.

## Installation

You can install this package using the Swift Package Manager, by including it in
the dependencies of your package:

```swift
let package = Package(
    // ...
    dependencies: [
        // other dependencies...
        .package(
            url: "https://github.com/Zollerboy1/SwiftCommand.git",
            from: "1.0.0"
        ),
    ],
    // ...
)
```

## Usage

Using this package is very easy.

Before you start, make sure that you've imported the `SwiftCommand` module:

```swift
import SwiftCommand
```

Now it can be used like this:

```swift
let output = try Command.findInPath(withName: "echo")!
                        .addArgument("Foo")
                        .waitForOutput()

print(output.stdout)
// Prints 'Foo\n'
```

This blocks the thread until the command terminates. You can use the
`async`/`await` API instead, if you want to do other work while waiting for the
command to terminate:

```swift
let output = try await Command.findInPath(withName: "echo")!
                              .addArgument("Foo")
                              .output

print(output.stdout)
// Prints 'Foo\n'
```

### Specifying command I/O

Suppose that you have a file called `SomeFile.txt` that looks like this:

```
Foo
Bar
Baz
```

You can then set stdin and stdout of commands like this:

```swift
let catProcess = try Command.findInPath(withName: "cat")!
                            .setStdin(.read(fromFile: "SomeFile.txt"))
                            .setStdout(.pipe)
                            .spawn()

let grepProcess = try Command.findInPath(withName: "grep")!
                             .addArgument("Ba")
                             .setStdin(.pipe(from: catProcess.stdout))
                             .setStdout(.pipe)
                             .spawn()

for try await line in grepProcess.stdout.lines {
    print(line)
}
// Prints 'Bar' and 'Baz'

try catProcess.wait()
try grepProcess.wait()
// Ensure the processes are terminated before exiting the parent process
```

This is doing in Swift, what you would normally write in a terminal like this:

```bash
cat < SomeFile.txt | grep Ba
```

If you don't specify stdin, stdout, or stderr, and also don't capture the output
(using e.g. `waitForOutput()`), then they will by default inherit the
corresponding handle of the parent process. E.g. the stdout of the following
program is `Bar\n`:

```swift
import SwiftCommand

try Command.findInPath(withName: "echo")!
           .addArgument("Bar")
           .wait()
```
