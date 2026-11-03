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
        // 自动响应客户端心跳
        wsOptions.autoReplyPing = true

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 10 

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
                    self.receiveNextMessage(on: connection)
                }
            case .failed(let error):
                // 只有物理掉线、网线拔出等非正常退出才报错误
                let nsError = error as NSError
                if nsError.code != 0 && nsError.code != Int(POSIXError.ECANCELED.rawValue) {
                    ServerLogger.shared.log("网络物理链路断开: \(error.localizedDescription)", isError: true)
                }
                self.cleanupConnection(connection)
            case .cancelled:
                // 安全注销，静默移除，不重复报警
                self.queue.async {
                    self.activeConnections.removeAll { $0 === connection }
                }
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    /// 核心核查点：全面拦截正常的系统级退出（Code 0 和 Code 89）
    private func receiveNextMessage(on connection: NWConnection) {
        connection.receiveMessage { [weak self, weak connection] (content, context, isComplete, error) in
            guard let self = self, let connection = connection else { return }

            if let error = error {
                let nsError = error as NSError
                // Code 0: 客户端合盖/退出主动断连 (EOF)
                // Code 89 (ECANCELED): 服务端或系统主动取消该连接
                if nsError.code == 0 || nsError.code == Int(POSIXError.ECANCELED.rawValue) {
                    ServerLogger.shared.log("客户端已离线 (休眠、断网或退出)")
                } else {
                    ServerLogger.shared.log("读取客户端消息失败: \(error.localizedDescription)", isError: true)
                }
                self.cleanupConnection(connection)
                return
            }

            // 识别客户端的优雅关闭帧
            if let metadata = context?.protocolMetadata.first as? NWProtocolWebSocket.Metadata,
               metadata.opcode == .close {
                ServerLogger.shared.log("收到客户端优雅关闭通知")
                self.cleanupConnection(connection)
                return
            }

            // 保持持续监听
            self.queue.async {
                self.receiveNextMessage(on: connection)
            }
        }
    }

    private func cleanupConnection(_ connection: NWConnection) {
        queue.async {
            if self.activeConnections.contains(where: { $0 === connection }) {
                self.activeConnections.removeAll { $0 === connection }
                connection.cancel()
            }
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
                        let nsError = sendError as NSError
                        // 推送失败时同样过滤 Code 0 / 89
                        if nsError.code != 0 && nsError.code != Int(POSIXError.ECANCELED.rawValue) {
                            ServerLogger.shared.log("向客户端推送失败: \(sendError.localizedDescription)", isError: true)
                        }
                        self?.cleanupConnection(conn)
                    }
                }))
            }
        }
        timer.resume()
        self.pushTimer = timer
    }
}
