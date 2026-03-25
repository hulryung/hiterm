import AppKit
import GhosttyKit

let ret = ghostty_init(
    UInt(CommandLine.argc),
    CommandLine.unsafeArgv
)
guard ret == GHOSTTY_SUCCESS else {
    print("ghostty_init failed: \(ret)")
    exit(1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
