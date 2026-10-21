import AppKit
import Darwin

// Agent access: lets agents on this Mac (Claude Code, MCP clients, scripts)
// use the browser through the `mbga` command. The command talks to a Unix
// socket in the data folder; only the same macOS user can connect, and the
// socket exists only while Settings ▸ Agents allows it.

enum AgentSettings {
    static let enabledKey = "agentAccess"
    /// MBGA_DEBUG_AGENT=1 allows agents in a test copy without saving it
    /// (the preferences are shared with the copy in real use).
    static let debug = ProcessInfo.processInfo.environment["MBGA_DEBUG_AGENT"]?.isEmpty == false

    static var enabled: Bool { debug || UserDefaults.standard.bool(forKey: enabledKey) }

    /// Where the `mbga` command is installed by Settings.
    static var commandLink: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/mbga")
    }

    /// The `mbga` command inside the app.
    static var bundledCommand: URL? {
        Bundle.main.url(forResource: "mbga", withExtension: nil, subdirectory: "bin")
    }

    /// Links ~/.local/bin/mbga to the app's command. Returns an error to show.
    static func installCommand() -> String? {
        guard let command = bundledCommand else { return "The command isn't in this build of MBGA." }
        let link = commandLink
        do {
            try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: link)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: command)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

/// The socket. Each connection sends one JSON request per line,
/// {"argv": ["click", "e4"]}, and gets one JSON reply per line,
/// {"ok": true, "text": "..."}; commands run on the main thread, one at a
/// time per connection.
@MainActor
final class AgentServer {
    let path: String
    private let commands: AgentCommands
    private var listener: Int32 = -1
    private var source: DispatchSourceRead?

    init(store: BrowserStore, path: String) {
        self.path = path
        commands = AgentCommands(store: store)
        NotificationCenter.default.addObserver(self, selector: #selector(update),
                                               name: UserDefaults.didChangeNotification, object: nil)
        update()
    }

    @objc private func update() {
        if AgentSettings.enabled { start() } else { stop() }
    }

    private func start() {
        guard listener < 0 else { return }
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else {
            NSLog("agent socket path too long: %@", path)
            close(fd)
            return
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: path.utf8)
            buffer[path.utf8.count] = 0
        }
        // Only this user may connect, whatever the umask.
        let previous = umask(0o077)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        umask(previous)
        guard bound == 0, listen(fd, 8) == 0 else {
            NSLog("agent socket: %s", strerror(errno))
            close(fd)
            return
        }
        chmod(path, 0o600)
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK)
        listener = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .userInitiated))
        source.setEventHandler { [weak self] in
            while true {
                let client = accept(fd, nil, nil)
                guard client >= 0 else { break }
                var uid: uid_t = 0, gid: gid_t = 0
                guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else {
                    close(client)
                    continue
                }
                Thread.detachNewThread { [weak self] in self?.serve(client) }
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    private func stop() {
        guard listener >= 0 else { return }
        source?.cancel()
        source = nil
        listener = -1
        unlink(path)
    }

    /// Reads requests off one connection until it closes. Runs on its own
    /// thread; each command hops to the main thread.
    private nonisolated func serve(_ client: Int32) {
        defer { close(client) }
        // A connection is blocking; replies are written whole.
        _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL, 0) & ~O_NONBLOCK)
        var pending = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let count = read(client, &buffer, buffer.count)
            guard count > 0 else { return }
            pending.append(contentsOf: buffer[0..<count])
            while let newline = pending.firstIndex(of: 0x0A) {
                let line = pending[pending.startIndex..<newline]
                pending.removeSubrange(pending.startIndex...newline)
                let reply = handle(Data(line))
                var out = reply
                out.append(0x0A)
                let written = out.withUnsafeBytes { write(client, $0.baseAddress, $0.count) }
                guard written == out.count else { return }
            }
        }
    }

    private nonisolated func handle(_ line: Data) -> Data {
        guard let request = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let argv = request["argv"] as? [String], !argv.isEmpty
        else { return Self.encode(.failure("Expected {\"argv\": [\"command\", ...]}")) }
        let done = DispatchSemaphore(value: 0)
        let result = Box()
        Task { @MainActor [weak self] in
            guard let self else {
                result.reply = .failure("MBGA is closing")
                done.signal()
                return
            }
            result.reply = await commands.run(argv)
            done.signal()
        }
        done.wait()
        return Self.encode(result.reply ?? .failure("No reply"))
    }

    private nonisolated static func encode(_ reply: AgentReply) -> Data {
        let object: [String: Any]
        switch reply {
        case .success(let text): object = ["ok": true, "text": text]
        case .failure(let error): object = ["ok": false, "error": error]
        }
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{\"ok\":false}".utf8)
    }

    private final class Box: @unchecked Sendable {
        var reply: AgentReply?
    }
}

enum AgentReply: Sendable {
    case success(String)
    case failure(String)
}
