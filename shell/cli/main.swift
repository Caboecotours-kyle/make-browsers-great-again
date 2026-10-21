import Foundation

// mbga: use the running MBGA browser from a terminal or an agent.
//   mbga <command> [args]   runs one command and prints the result
//   mbga mcp                serves the same commands over MCP (stdio)
// It talks to the socket MBGA opens while Settings ▸ Agents allows it.

let guide = """
mbga: drive the MBGA browser. Pages come back as short outlines with refs
([e12]) to act on; refs last until the page changes, then snapshot again.

  tabs [--all]                 list tabs (* on screen, > the one you use)
  open <url|search> [--focus]  new tab (behind the person's unless --focus)
  use tN | focus [tN] | close [tN]
  goto <url> | back | forward | reload [--hard]
  info                         title, url, status, console counts
  snapshot [--text] [--viewport] [--max N]
                               headings and everything usable, with refs;
                               --text adds paragraphs and list items
  read [--all] [--max N]       the page's text (main content by default)
  find <text>                  elements saying <text>, with refs
  click <ref> [--force]        real click; says where the page went
  fill <ref> <text> [--enter]  replace a field's text (type --append adds)
  press <key> [--times N]      Enter, Tab, Escape, ArrowDown, Shift+Tab, a…
  select <ref> <option>        choose in a <select>
  hover <ref> | scroll [down|up|top|bottom|<ref>] [px]
  wait load | <ms> | text <t> | gone <t>   [--timeout s]
  eval <js>                    run JavaScript in the page, print JSON
  screenshot [--full] [--out path]   PNG at CSS pixels; prints its path
  console [--errors] [--clear] messages since the page loaded

Refs can also be css=<selector> or text=<words> when you know the page.

  run <file.js | - | -e 'code'> [--timeout s]
      a script, run inside MBGA, with every command as an async function
      returning its text: open(url) → "tN", goto, click(target), fill(target,
      text, {enter: true}), press, select, wait('load' | ms | {text}),
      snapshot, read, find, screenshot, plus evaluate(fn, ...args) → the
      value fn returns in the page, and log(...). Whatever the script logs
      or returns is printed. One call for many steps:
        mbga run -e 'await open("news.ycombinator.com");
          return await evaluate(() => [...document.querySelectorAll(".titleline > a")]
            .slice(0, 5).map(a => a.textContent))'

Every page command takes --tab tN (default: the tab you opened or chose
last, else the one on screen). Typical loop: open → snapshot → click/fill →
snapshot. Prefer snapshot/read/find over screenshots: far fewer tokens.
"""

let socketPath = ProcessInfo.processInfo.environment["MBGA_SOCKET"]
    ?? FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/MBGA/agent.sock").path

enum Failure: Error {
    case message(String)
}

/// One connection to the browser, for any number of commands.
final class Browser {
    private let fd: Int32
    private var pending = Data()

    init() throws {
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            let bytes = Array(socketPath.utf8.prefix(buffer.count - 1))
            buffer.copyBytes(from: bytes)
            buffer[bytes.count] = 0
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard fd >= 0, connected == 0 else {
            close(fd)
            throw Failure.message("Can't reach MBGA. Open it and turn on Settings ▸ Agents ▸ \"Let agents use MBGA\".")
        }
    }

    deinit { close(fd) }

    func run(_ argv: [String]) throws -> String {
        var request = try JSONSerialization.data(withJSONObject: ["argv": argv])
        request.append(0x0A)
        let written = request.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        guard written == request.count else { throw Failure.message("MBGA closed the connection.") }
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            if let newline = pending.firstIndex(of: 0x0A) {
                let line = pending[pending.startIndex..<newline]
                pending.removeSubrange(pending.startIndex...newline)
                guard let reply = try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else {
                    throw Failure.message("MBGA sent something unexpected.")
                }
                if reply["ok"] as? Bool == true { return reply["text"] as? String ?? "" }
                throw Failure.message(reply["error"] as? String ?? "The command failed.")
            }
            let count = read(fd, &buffer, buffer.count)
            guard count > 0 else { throw Failure.message("MBGA closed the connection.") }
            pending.append(contentsOf: buffer[0..<count])
        }
    }
}

/// Splits a command line as a shell would: spaces, with quotes grouping.
func words(_ line: String) -> [String] {
    var out: [String] = [], current = "", quote: Character?, started = false
    var iterator = line.makeIterator()
    while let c = iterator.next() {
        if let q = quote {
            if c == q { quote = nil } else if c == "\\", q == "\"", let next = iterator.next() { current.append(next) } else { current.append(c) }
        } else if c == "\"" || c == "'" {
            quote = c
            started = true
        } else if c == " " || c == "\t" || c == "\n" {
            if started || !current.isEmpty { out.append(current) }
            current = ""
            started = false
        } else {
            current.append(c)
        }
    }
    if started || !current.isEmpty { out.append(current) }
    return out
}

// MARK: - MCP

/// MCP over stdio with a single tool taking a command line: one short
/// schema in the model's context instead of one per command.
func serveMCP() -> Never {
    var browser: Browser?
    let tool: [String: Any] = [
        "name": "browser",
        "description": "Use the MBGA browser on this Mac, as the person's own browser.\n\n" + guide,
        "inputSchema": [
            "type": "object",
            "properties": [
                "command": ["type": "string", "description": "An mbga command line, e.g. \"snapshot\" or \"click e12\" or \"fill e3 'hello' --enter\""],
                "script": ["type": "string", "description": "JavaScript for `run` (instead of command): many steps in one call"],
            ],
        ],
    ]
    func send(_ object: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }
    while let line = readLine(strippingNewline: true) {
        guard let message = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let method = message["method"] as? String else { continue }
        let id = message["id"]
        let params = message["params"] as? [String: Any] ?? [:]
        func reply(_ result: [String: Any]) {
            if let id { send(["jsonrpc": "2.0", "id": id, "result": result]) }
        }
        switch method {
        case "initialize":
            reply([
                "protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "mbga", "version": "1.0"],
            ])
        case "ping":
            reply([:])
        case "tools/list":
            reply(["tools": [tool]])
        case "tools/call":
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let argv = (arguments["script"] as? String).map { ["run", $0] } ?? words(arguments["command"] as? String ?? "")
            guard !argv.isEmpty else {
                reply(["content": [["type": "text", "text": guide]]])
                continue
            }
            do {
                if browser == nil { browser = try Browser() }
                let text: String
                do {
                    text = try browser!.run(argv)
                } catch {
                    // The browser may have restarted; try once on a new connection.
                    browser = try Browser()
                    text = try browser!.run(argv)
                }
                var content: [[String: Any]] = [["type": "text", "text": text]]
                // Screenshots come back as images the model can see.
                if ["screenshot", "shot"].contains(argv[0]), let path = text.components(separatedBy: " (").first,
                   let png = FileManager.default.contents(atPath: path) {
                    content.append(["type": "image", "data": png.base64EncodedString(), "mimeType": "image/png"])
                }
                reply(["content": content])
            } catch Failure.message(let text) {
                browser = nil
                reply(["content": [["type": "text", "text": text]], "isError": true])
            } catch {
                browser = nil
                reply(["content": [["type": "text", "text": error.localizedDescription]], "isError": true])
            }
        default:
            if let id {
                send(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Unknown method \(method)"]])
            }
        }
    }
    exit(0)
}

// MARK: - Main

let argv = Array(CommandLine.arguments.dropFirst())
if argv.isEmpty || ["help", "-h", "--help", "guide"].contains(argv[0]) {
    print(guide)
    exit(0)
}
if argv[0] == "mcp" { serveMCP() }
do {
    var argv = argv
    // A script goes over as its text.
    if argv[0] == "run" {
        guard argv.count >= 2 else { throw Failure.message("Usage: mbga run <file.js | - | -e 'code'>") }
        let rest = Array(argv.dropFirst(argv[1] == "-e" ? 3 : 2))
        let source: String
        if argv[1] == "-e", argv.count >= 3 {
            source = argv[2]
        } else if argv[1] == "-" {
            source = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        } else if let text = try? String(contentsOfFile: argv[1], encoding: .utf8) {
            source = text
        } else {
            throw Failure.message("Can't read \(argv[1]).")
        }
        argv = ["run", source] + rest
    }
    print(try Browser().run(argv))
} catch Failure.message(let text) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
    exit(1)
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
