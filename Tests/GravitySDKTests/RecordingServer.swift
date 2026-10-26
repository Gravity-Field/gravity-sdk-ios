import Foundation
import Network

/// Local HTTP server for wire-level tests: records every request body and
/// answers /visit and /event with `campaigns`, everything else with an empty
/// content list. Every answer carries `responseUser`.
final class RecordingServer: @unchecked Sendable {
    struct Request {
        let path: String
        let body: [String: Any]
    }

    private let queue = DispatchQueue(label: "RecordingServer")
    private let listener: NWListener
    private var requests: [Request] = []
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    // Accessed only on `queue`
    private var campaigns: [[String: Any]] = []
    private var content: [[String: Any]] = []
    private var responseUser: [String: Any] = ["uid": "server-uid", "ses": "server-ses"]

    private(set) var url = ""

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    func start() async throws {
        let url: String = try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            listener.stateUpdateHandler = { [weak listener] state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    continuation.resume(returning: "http://127.0.0.1:\(listener?.port?.rawValue ?? 0)")
                case .failed(let error):
                    resumed = true
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: queue)
        }
        self.url = url
    }

    func stop() {
        listener.cancel()
        queue.sync {
            connections.values.forEach { $0.cancel() }
            connections.removeAll()
        }
    }

    func reset(campaigns: [[String: Any]] = [], content: [[String: Any]] = [], responseUser: [String: Any] = ["uid": "server-uid", "ses": "server-ses"]) {
        queue.sync {
            requests.removeAll()
            self.campaigns = campaigns
            self.content = content
            self.responseUser = responseUser
        }
    }

    var recorded: [Request] {
        queue.sync { requests }
    }

    /// Waits until at least `count` requests arrived (async SDK flows).
    func waitFor(_ count: Int, timeout: TimeInterval = 5) async -> [Request] {
        let deadline = Date().addingTimeInterval(timeout)
        while recorded.count < count, Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return recorded
    }

    private func handle(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.connections[id] = nil
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = Self.parse(buffer) {
                self.requests.append(request)
                self.respond(connection, path: request.path)
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                self.receive(connection, buffer: buffer)
            }
        }
    }

    private static func parse(_ buffer: Data) -> Request? {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: buffer[..<headerEnd.lowerBound], as: UTF8.self)
        let lines = head.components(separatedBy: "\r\n")
        let contentLength = lines
            .first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { Int($0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)) }
            ?? 0
        guard buffer.count - headerEnd.upperBound >= contentLength else { return nil }
        let parts = lines.first?.split(separator: " ") ?? []
        let path = parts.count > 1 ? String(parts[1]) : ""
        let bodyData = buffer[headerEnd.upperBound..<(headerEnd.upperBound + contentLength)]
        let body = (try? JSONSerialization.jsonObject(with: Data(bodyData))) as? [String: Any] ?? [:]
        return Request(path: path, body: body)
    }

    private func respond(_ connection: NWConnection, path: String) {
        var json: [String: Any] = ["user": responseUser]
        if path.hasSuffix("/visit") || path.hasSuffix("/event") {
            json["campaigns"] = campaigns
        } else {
            json["data"] = content
        }
        let body = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        var response = Data(
            ("HTTP/1.1 200 OK\r\n"
                + "Content-Type: application/json\r\n"
                + "Content-Length: \(body.count)\r\n"
                + "Connection: close\r\n\r\n").utf8
        )
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
