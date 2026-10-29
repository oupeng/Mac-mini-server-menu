import SwiftUI
import Combine

public struct MetricsData: Codable {
    public let uptimeSeconds: Int
    public let loadAvg: [Double]
    public let cpuUsage: Double
    public let cpuTemp: Double
    public let powerWatts: Double
    public let memUsedMB: Int
    public let memTotalMB: Int
    public let memPercent: Double
    public let netRxBytesPerSec: UInt64
    public let netTxBytesPerSec: UInt64
    public let diskReadBytesPerSec: UInt64
    public let diskWriteBytesPerSec: UInt64
    public let topProcesses: [TopProcessItem]
}

public struct TopProcessItem: Codable, Identifiable {
    public var id: String { name }
    public let name: String
    public let cpu: Double
    public let memMB: Int
}

@MainActor
public final class MonitorViewModel: ObservableObject {
    @AppStorage("serverIP") public var serverIP: String = "192.168.31.25"
    @AppStorage("serverPort") public var serverPort: Int = 29876

    @Published public var data: MetricsData?
    @Published public var isOnline: Bool = false
    @Published public var cpuHistory: [Double] = Array(repeating: 0.0, count: 20)

    private var webSocketTask: URLSessionWebSocketTask?
    private var pingTimer: Timer?
    private var urlSession: URLSession?

    public init() {
        setupSession()
        connectWebSocket()
    }

    private func setupSession() {
        let config = URLSessionConfiguration.ephemeral
        // 核心技术点：清空代理字典，强制绕过系统 HTTP / HTTPS / SOCKS 代理直连局域网！
        config.connectionProxyDictionary = [:]
        config.timeoutIntervalForRequest = 3.0
        config.waitsForConnectivity = false
        self.urlSession = URLSession(configuration: config)
    }

    public func connectWebSocket() {
        disconnect()

        guard let session = urlSession,
              let url = URL(string: "ws://\(serverIP):\(serverPort)") else { return }

        let task = session.webSocketTask(with: url)
        self.webSocketTask = task
        task.resume()

        listenMessage()
        startHeartbeat()
    }

    public func fetch() { connectWebSocket() }
    public func startPolling() { connectWebSocket() }

    private func listenMessage() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch result {
                case .success(let message):
                    self.isOnline = true
                    switch message {
                    case .data(let data):
                        self.handleIncomingData(data)
                    case .string(let text):
                        if let data = text.data(using: .utf8) {
                            self.handleIncomingData(data)
                        }
                    @unknown default:
                        break
                    }
                    self.listenMessage()

                case .failure(let error):
                    print("[WebSocket Error] 详细报错:", error.localizedDescription)
                    self.isOnline = false
                    self.reconnectAfterDelay()
                }
            }
        }
    }

    private func handleIncomingData(_ payloadData: Data) {
        if let decoded = try? JSONDecoder().decode(MetricsData.self, from: payloadData) {
            self.data = decoded
            self.cpuHistory.append(decoded.cpuUsage)
            if self.cpuHistory.count > 20 { self.cpuHistory.removeFirst() }
        }
    }

    private func startHeartbeat() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let task = self.webSocketTask else { return }
                task.sendPing { error in
                    if error != nil {
                        Task { @MainActor [weak self] in
                            self?.isOnline = false
                        }
                    }
                }
            }
        }
    }

    private func reconnectAfterDelay() {
        disconnect()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            Task { @MainActor [weak self] in
                self?.connectWebSocket()
            }
        }
    }

    public func disconnect() {
        pingTimer?.invalidate()
        pingTimer = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }
}
