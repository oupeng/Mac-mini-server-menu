import Foundation
import Network

public final class WebSocketService {
    private let listener: NWListener
    private let collector = MetricsCollector()
    private var activeConnections: [NWConnection] = []
    private var pushTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.miniserver.ws", qos: .utility)

    public init(port: UInt16 = 29876) throws {
        // 配置原生 WebSocket 协议栈 (macOS 10.15+ 原生支持)
        let wsOptions = NWProtocolWebSocket.Options()
        let tcpOptions = NWProtocolTCP.Options()
        let params = NWParameters(tls: nil, tcp: tcpOptions)
        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        self.listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
    }

    public func start() {
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        listener.stateUpdateHandler = { state in
            if state == .ready {
                print("[MiniServer] WebSocket 监听就绪，端口: 29876 (macOS 10.15)")
            }
        }
        listener.start(queue: queue)
        startBroadcasting()
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self = self, let connection = connection else { return }
            switch state {
            case .ready:
                self.queue.async { self.activeConnections.append(connection) }
            case .failed, .cancelled:
                self.queue.async {
                    self.activeConnections.removeAll { $0 === connection }
                }
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    // 每秒主动向所有连接的 MacBook Pro 推送最新硬件指标
    private func startBroadcasting() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .seconds(1))
        timer.setEventHandler { [weak self] in
            guard let self = self, !self.activeConnections.isEmpty else { return }
            let payload = self.collector.collectPayload()
            guard let jsonData = try? JSONEncoder().encode(payload) else { return }

            // 原生打包成 WebSocket 文本帧
            let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
            let context = NWConnection.ContentContext(identifier: "metrics", metadata: [metadata])

            for conn in self.activeConnections {
                conn.send(content: jsonData, contentContext: context, isComplete: true, completion: .contentProcessed({ _ in }))
            }
        }
        timer.resume()
        self.pushTimer = timer
    }
}
