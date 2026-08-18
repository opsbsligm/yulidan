import Foundation

// MARK: - 错误

/// HTTP 解析/协议错误
public enum HTTPError: Error, Sendable {
    /// 请求行不合法（格式错误）
    case badRequestLine
    /// 请求头行不合法
    case badHeaderLine
    /// 请求头超出上限
    case oversizedHead
}

// MARK: - 请求

/// HTTP/1.1 请求（解析结果）
public struct HTTPRequest: Sendable {
    public let method: String
    /// 路径（不含 query）
    public let path: String
    /// query 参数（已 URL 解码）
    public let query: [String: String]
    /// 请求头（key 统一小写）
    public let headers: [String: String]
    public var body: Data

    public init(method: String, path: String, query: [String: String], headers: [String: String], body: Data) {
        self.method = method
        self.path = path
        self.query = query
        self.headers = headers
        self.body = body
    }

    /// 取请求头（大小写不敏感）
    public func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }

    /// 声明的正文长度（无 Content-Length 时为 0）
    public var contentLength: Int {
        Int(header("content-length") ?? "0") ?? 0
    }
}

public extension HTTPRequest {
    /// 解析请求头部分（不含正文）。
    ///
    /// - Parameters:
    ///   - head: 截至空行（\r\n\r\n）前的全部文本
    ///   - bodyPrefix: 空行之后已随头一起到达的正文前缀（可为空）
    static func parseHead(_ head: String, bodyPrefix: Data) throws -> HTTPRequest {
        let lines = head.components(separatedBy: "\r\n")
        guard let requestLine = lines.first, !requestLine.isEmpty else {
            throw HTTPError.badRequestLine
        }
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3 else {
            throw HTTPError.badRequestLine
        }
        let version = parts[2].trimmingCharacters(in: .whitespaces)
        guard version == "HTTP/1.0" || version == "HTTP/1.1" else {
            throw HTTPError.badRequestLine
        }
        let method = parts[0].trimmingCharacters(in: .whitespaces)
        guard !method.isEmpty else {
            throw HTTPError.badRequestLine
        }
        let target = String(parts[1])

        // 拆分 path 与 query
        var path = target
        var query: [String: String] = [:]
        if let qIndex = target.firstIndex(of: "?") {
            path = String(target[..<qIndex])
            let queryString = String(target[target.index(after: qIndex)...])
            for pair in queryString.components(separatedBy: "&") where !pair.isEmpty {
                let kv = pair.components(separatedBy: "=")
                let key = kv.count > 1 ? kv[0] : pair
                let value = kv.count > 1 ? kv[1] : ""
                query[HTTPRequest.percentDecode(key)] = HTTPRequest.percentDecode(value)
            }
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else {
                throw HTTPError.badHeaderLine
            }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else {
                throw HTTPError.badHeaderLine
            }
            headers[key] = value
        }
        return HTTPRequest(method: method, path: path, query: query, headers: headers, body: bodyPrefix)
    }

    /// URL 解码（失败时原样返回）
    static func percentDecode(_ raw: String) -> String {
        raw.removingPercentEncoding ?? raw
    }
}

// MARK: - 响应

/// HTTP/1.1 响应
public struct HTTPResponse: Sendable {
    public var status: Int
    /// 响应头（key 小写；content-length 由 render 统一计算）
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    public static func json(_ data: Data, status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status, headers: ["content-type": "application/json; charset=utf-8"], body: data)
    }

    public static func text(_ string: String, status: Int = 200, contentType: String = "text/plain; charset=utf-8") -> HTTPResponse {
        HTTPResponse(status: status, headers: ["content-type": contentType], body: Data(string.utf8))
    }

    public static func notFound(message: String = "not found") -> HTTPResponse {
        .errorJSON(message, status: 404)
    }

    public static func badRequest(_ message: String) -> HTTPResponse {
        .errorJSON(message, status: 400)
    }

    public static func methodNotAllowed(_ message: String) -> HTTPResponse {
        .errorJSON(message, status: 405)
    }

    public static func tooLarge(_ message: String = "request body too large") -> HTTPResponse {
        .errorJSON(message, status: 413)
    }

    public static func serverError(_ message: String) -> HTTPResponse {
        .errorJSON(message, status: 500)
    }

    private static func errorJSON(_ message: String, status: Int) -> HTTPResponse {
        let payload: [String: String] = ["error": message]
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
        return .json(data, status: status)
    }

    /// 渲染为线上字节（统一 Connection: close，浏览器兼容）
    public func render() -> Data {
        var output = "HTTP/1.1 \(status) \(Self.reasonPhrase(for: status))\r\n"
        for (key, value) in headers {
            let k = key.lowercased()
            if k == "content-length" || k == "connection" {
                continue
            }
            output += "\(k): \(value)\r\n"
        }
        output += "content-length: \(body.count)\r\n"
        output += "connection: close\r\n"
        output += "\r\n"
        return Data(output.utf8) + body
    }

    private static let reasonPhrases: [Int: String] = [
        200: "OK", 201: "Created", 202: "Accepted", 400: "Bad Request", 401: "Unauthorized",
        404: "Not Found", 405: "Method Not Allowed", 408: "Request Timeout",
        413: "Payload Too Large", 429: "Too Many Requests",
        500: "Internal Server Error", 502: "Bad Gateway", 503: "Service Unavailable",
    ]

    public static func reasonPhrase(for status: Int) -> String {
        reasonPhrases[status] ?? "Unknown"
    }
}
