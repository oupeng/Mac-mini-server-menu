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
        // 自动响应客户端的心跳 Ping 帧
        wsOptions.autoReplyPing = true

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 5 // 5秒空闲即发探测包

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

    public func stop() {
        pushTimer?.cancel()
        pushTimer = nil

        queue.async {
            for conn in self.activeConnections {
                // 安全发送关闭帧给客户端
                let metadata = NWProtocolWebSocket.Metadata(opcode: .close)
                let context = NWConnection.ContentContext(identifier: "close", metadata: [metadata])
                conn.send(content: nil, contentContext: context, isComplete: true, completion: .contentProcessed({ _ in
                    conn.cancel()
                }))
            }
            self.activeConnections.removeAll()
            self.listener.cancel()
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self = self, let connection = connection else { return }
            switch state {
            case .ready:
                ServerLogger.shared.log("收到新连接: 客户端已接入")
                self.queue.async {
                    self.activeConnections.append(connection)
                    // 核心修复：连接就绪后立刻启动持续的 receive 接收循环
                    self.receiveNextMessage(on: connection)
                }
            case .failed(let error):
                ServerLogger.shared.log("连接异常中断: \(error.localizedDescription)", isError: true)
                self.cleanupConnection(connection)
            case .cancelled:
                ServerLogger.shared.log("连接已彻底注销释放")
                self.cleanupConnection(connection)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    /// 核心修复：持续读取客户端的数据、握手与 Pong，杜绝缓冲区打满和静默断连
    private func receiveNextMessage(on connection: NWConnection) {
        connection.receiveMessage { [weak self, weak connection] (content, context, isComplete, error) in
            guard let self = self, let connection = connection else { return }

            if let error = error {
                ServerLogger.shared.log("读取客户端消息失败: \(error.localizedDescription)", isError: true)
                self.cleanupConnection(connection)
                return
            }

            // 检查是否是关闭帧
            if let metadata = context?.protocolMetadata.first as? NWProtocolWebSocket.Metadata,
               metadata.opcode == .close {
                ServerLogger.shared.log("客户端请求正常关闭连接")
                self.cleanupConnection(connection)
                return
            }

            // 循环持续监听下一次消息输入
            self.queue.async {
                self.receiveNextMessage(on: connection)
            }
        }
    }

    private func cleanupConnection(_ connection: NWConnection) {
        queue.async {
            self.activeConnections.removeAll { $0 === connection }
            connection.cancel()
        }
    }

    private func startBroadcasting() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .seconds(1))
        timer.setEventHandler { [weak self] in
            guard let self = self, !self.activeConnections.isEmpty else { return }
            let payload = self.collector.collectPayload()
            guard let jsonData = try? JSONEncoder().encode(payload) else {
                ServerLogger.shared.log("JSON 数据编码失败", isError: true)
                return
            }

            let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
            let context = NWConnection.ContentContext(identifier: "metrics", metadata: [metadata])

            for conn in self.activeConnections {
                conn.send(content: jsonData, contentContext: context, isComplete: true, completion: .contentProcessed({ [weak self, weak conn] sendError in
                    if let sendError = sendError, let conn = conn {
                        ServerLogger.shared.log("推送数据失败，清理断开的连接: \(sendError.localizedDescription)", isError: true)
                        self?.cleanupConnection(conn)
                    }
                }))
            }
        }
        timer.resume()
        self.pushTimer = timer
    }
}
