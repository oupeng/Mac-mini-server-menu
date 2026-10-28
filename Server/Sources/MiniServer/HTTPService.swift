// HTTPService.swift
import Foundation
import Network

public final class HTTPService {
    private let listener: NWListener
    private let collector = MetricsCollector()

    public init(port: UInt16 = 29876) throws {
        self.listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
    }

    public func start() {
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        listener.stateUpdateHandler = { state in
            if state == .ready {
                print("[MiniServer] 监听端口 29876 就绪 (macOS 10.15 Catalina)")
            }
        }
        listener.start(queue: .global(qos: .utility))
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))
        connection.receive(minimumIncompleteLength: 4, maximumLength: 1024) { [weak self] data, _, isComplete, _ in
            guard let self = self, let _ = data else {
                connection.cancel()
                return
            }

            let payload = self.collector.collectPayload()
            guard let jsonData = try? JSONEncoder().encode(payload) else {
                connection.cancel()
                return
            }

            var header = "HTTP/1.1 200 OK\r\n"
            header += "Content-Type: application/json; charset=utf-8\r\n"
            header += "Access-Control-Allow-Origin: *\r\n"
            header += "Content-Length: \(jsonData.count)\r\n"
            header += "Connection: close\r\n\r\n"

            var responseData = header.data(using: .utf8)!
            responseData.append(jsonData)

            connection.send(content: responseData, completion: .contentProcessed({ _ in
                connection.cancel()
            }))
        }
    }
}
