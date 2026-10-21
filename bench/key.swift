// Sends one key press to MBGA, refusing if another app is frontmost.
// Usage: key <keycode> [cmd] [ctrl] [shift] [opt]
import AppKit

guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "dev.mbga.browser" else {
    FileHandle.standardError.write("MBGA is not frontmost\n".data(using: .utf8)!)
    exit(2)
}
let args = Array(CommandLine.arguments.dropFirst())
var flags: CGEventFlags = []
for m in args.dropFirst() {
    switch m {
    case "cmd": flags.insert(.maskCommand)
    case "ctrl": flags.insert(.maskControl)
    case "shift": flags.insert(.maskShift)
    case "opt": flags.insert(.maskAlternate)
    default: break
    }
}
let source = CGEventSource(stateID: .hidSystemState)
for down in [true, false] {
    let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(args[0])!, keyDown: down)!
    event.flags = flags
    event.post(tap: .cghidEventTap)
    usleep(30_000)
}
