// Brings the app with the given process ID to the front.
// Usage: activate <pid>
import AppKit

guard CommandLine.arguments.count == 2, let pid = pid_t(CommandLine.arguments[1]),
      let app = NSRunningApplication(processIdentifier: pid) else {
    FileHandle.standardError.write("usage: activate <pid of a running app>\n".data(using: .utf8)!)
    exit(2)
}
app.activate()
for _ in 0..<40 where NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
    usleep(50_000)
}
exit(NSWorkspace.shared.frontmostApplication?.processIdentifier == pid ? 0 : 1)
