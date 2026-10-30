import Foundation
import Network

public final class WebSocketService {
    private let listener: NWListener
    private let collector = MetricsCollector()
    private var activeConnections: [NWConnection] = []
    private var pushTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.miniserver.ws", qos: .utility)

    public init(port: UInt16 = 29876) throws {
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
            switch state {
            case .ready:
                ServerLogger.shared.log("WebSocket 监听已就绪，端口: 29876")
            case .failed(let error):
                ServerLogger.shared.log("监听器发生严重失败: \(error.localizedDescription)", isError: true)
            case .cancelled:
                ServerLogger.shared.log("监听器已安全释放")
            default:
                break
            }
        }
        listener.start(queue: queue)
        startBroadcasting()
    }

    // 核心新增：提供安全彻底的关闭机制
    public func stop() {
        pushTimer?.cancel()
        pushTimer = nil
        
        for conn in activeConnections {
            conn.cancel()
        }
        activeConnections.removeAll()
        listener.cancel()
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self = self, let connection = connection else { return }
            switch state {
            case .ready:
                ServerLogger.shared.log("收到新连接: MacBook Client 已接入")
                self.queue.async { self.activeConnections.append(connection) }
            case .failed(let error):
                ServerLogger.shared.log("连接异常中断: \(error.localizedDescription)", isError: true)
                self.queue.async { self.activeConnections.removeAll { $0 === connection } }
            case .cancelled:
                ServerLogger.shared.log("Client 已主动断开连接")
                self.queue.async { self.activeConnections.removeAll { $0 === connection } }
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func startBroadcasting() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .seconds(1))
        timer.setEventHandler { [weak self] in
            guard let self = self, !self.activeConnections.isEmpty else { return }
            let payload = self.collector.collectPayload()
            guard let jsonData = try? JSONEncoder().encode(payload) else {
                ServerLogger.shared.log("JSON 打包失败，请检查数据模型", isError: true)
                return
            }

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
