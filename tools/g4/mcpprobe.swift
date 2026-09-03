// mcpprobe.swift — G4 层1「标准 MCP 社区插件拿来即用」实测探针（A 层静默：无 UI/无前台/无键鼠）
//
// 设计口径：
//   · 报文镜像我方 StdioMCPClient.swift（initialize protocolVersion=2024-11-05 →
//     notifications/initialized → tools/list），保证探针结论对宿主有效（证据一致性）；
//   · 独立 JSON-RPC 行协议实现（仅 Foundation）——不链 SwiftPM 包，包零触碰；
//   · 只读安全姿态：initialize + tools/list 握手，**永不调用 tools/call**（社区包代码只被加载，
//     不被指挥）；子进程环境最小化（仅 PATH/HOME，HOME 由调用方指到沙箱）；超时必 kill。
// 用法: mcpprobe <超时秒> <标签> -- <命令> [参数...]
// 输出: 单行 JSON {label, ok, serverInfo, protocolVersion, toolCount, tools[], stderrTail, elapsedMs, err}
import Foundation

let args = CommandLine.arguments
guard args.count > 5, let timeout = Double(args[1]),
      let sep = args.firstIndex(of: "--"), sep + 1 < args.count else {
    FileHandle.standardError.write(Data("usage: mcpprobe <timeout> <label> -- <cmd> [args...]\n".utf8))
    exit(64)
}

let label = args[2]
let cmd = Array(args[(sep + 1)...])

final class LineBuffer: @unchecked Sendable {
    private var data = Data()
    private var lines: [String] = []
    private let lock = NSLock()
    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
        while let nl = data.firstIndex(of: 0x0A) {
            let line = Data(data[data.startIndex ..< nl])
            data.removeSubrange(data.startIndex ... nl)
            if let s = String(data: line, encoding: .utf8), !s.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append(s)
            }
        }
    }

    func nextLine(timeout: TimeInterval) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            lock.lock()
            if !lines.isEmpty {
                let line = lines.removeFirst()
                lock.unlock() // ⚠️ 必须显式解锁：早先 return-持锁版本实测双线程死锁（sample 定位），教训入档
                return line
            }
            lock.unlock()
            Thread.sleep(forTimeInterval: 0.05)
        }
        return nil
    }

    var lineCount: Int {
        lock.lock(); defer { lock.unlock() }
        return lines.count
    }
}

enum JSONLite {
    static func parse(_ s: String) -> [String: Any]? {
        guard let d = s.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        return o
    }

    static func stringify(_ o: Any) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: o), let s = String(data: d, encoding: .utf8) else { return "{}" }
        return s
    }
}

func emit(_ obj: [String: Any], rc: Int32) -> Never {
    print(JSONLite.stringify(obj))
    exit(rc)
}

let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
proc.arguments = cmd
var env: [String: String] = [:]
if let path = ProcessInfo.processInfo.environment["PATH"] {
    env["PATH"] = path
}

if let home = ProcessInfo.processInfo.environment["PROBE_HOME"] {
    env["HOME"] = home
}

if let nodePath = ProcessInfo.processInfo.environment["PROBE_PATH"] {
    env["PATH"] = nodePath
}

// 企业 MITM 网络（本机实证）：npx 子进程需显式 cafile 才信任证书链——按需透传两个白名单键
for key in ["npm_config_cafile", "NODE_EXTRA_CA_CERTS"] {
    if let v = ProcessInfo.processInfo.environment[key] {
        env[key] = v
    }
}

proc.environment = env

let pipe = Pipe()
let errPipe = Pipe()
let inPipe = Pipe()
proc.standardInput = inPipe
proc.standardOutput = pipe
proc.standardError = errPipe
let outBuf = LineBuffer()
let errBuf = LineBuffer()
pipe.fileHandleForReading.readabilityHandler = { h in outBuf.append(h.availableData) }
errPipe.fileHandleForReading.readabilityHandler = { h in errBuf.append(h.availableData) }

let start = Date()
do {
    try proc.run()
} catch {
    emit(["label": label, "ok": false, "err": "spawn failed: \(error)"], rc: 1)
}

func killAll() {
    if proc.isRunning {
        proc.terminate()
        Thread.sleep(forTimeInterval: 0.5)
        if proc.isRunning {
            kill(Int32(proc.processIdentifier), SIGKILL)
        }
    }
}

let stdin = inPipe
func send(_ obj: [String: Any]) {
    let line = JSONLite.stringify(obj) + "\n"
    stdin.fileHandleForWriting.write(Data(line.utf8))
}

// 与 StdioMCPClient 同款握手：initialize → notifications/initialized → tools/list
send(["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": [
    "protocolVersion": "2024-11-05",
    "capabilities": [String: Any](),
    "clientInfo": ["name": "swift-harness-g4probe", "version": "0.1"],
]])

var serverInfo = ""
var proto = ""
while true {
    guard let line = outBuf.nextLine(timeout: timeout) else {
        killAll()
        emit(["label": label, "ok": false, "err": "initialize timeout",
              "stderrTail": errBuf.lineCount], rc: 2)
    }
    guard let obj = JSONLite.parse(line), (obj["id"] as? Int) == 1 else { continue }
    if obj["error"] != nil {
        killAll()
        emit(["label": label, "ok": false, "err": "initialize rejected: \(JSONLite.stringify(obj["error"]!))"], rc: 3)
    }
    let result = obj["result"] as? [String: Any] ?? [:]
    let info = result["serverInfo"] as? [String: Any] ?? [:]
    serverInfo = "\(info["name"] ?? "?")/\(info["version"] ?? "?")"
    proto = result["protocolVersion"] as? String ?? "unknown"
    break
}

send(["jsonrpc": "2.0", "method": "notifications/initialized", "params": [String: Any]()])
send(["jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": [String: Any]()])

var toolNames: [String] = []
while true {
    guard let line = outBuf.nextLine(timeout: timeout) else {
        killAll()
        emit(["label": label, "ok": false, "err": "tools/list timeout", "serverInfo": serverInfo], rc: 4)
    }
    guard let obj = JSONLite.parse(line), (obj["id"] as? Int) == 2 else { continue }
    if obj["error"] != nil {
        killAll()
        emit(["label": label, "ok": false, "err": "tools/list rejected: \(JSONLite.stringify(obj["error"]!))",
              "serverInfo": serverInfo], rc: 5)
    }
    let result = obj["result"] as? [String: Any] ?? [:]
    let tools = result["tools"] as? [[String: Any]] ?? []
    toolNames = tools.compactMap { $0["name"] as? String }.prefix(50).map(\.self)
    break
}

killAll()
let elapsed = Int(Date().timeIntervalSince(start) * 1000)
emit(["label": label, "ok": true, "serverInfo": serverInfo, "protocolVersion": proto,
      "toolCount": toolNames.count, "tools": toolNames, "elapsedMs": elapsed], rc: 0)
