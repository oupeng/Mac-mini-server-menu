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
    public let totalRxBytes: UInt64?       // 接收开机累计总下载
    public let totalTxBytes: UInt64?       // 接收开机累计总上传
    public let diskReadBytesPerSec: UInt64
    public let diskWriteBytesPerSec: UInt64
    public let topProcesses: [TopProcessItem]
}

public struct TopProcessItem: Codable, Identifiable {
    public var id: String { name + "\(cpu)" + "\(memMB)" }
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

    @Published public var cpuHistory: [Double] = Array(repeating: 0.0, count: 18)
    @Published public var netRxHistory: [Double] = Array(repeating: 0.0, count: 18)
    @Published public var netTxHistory: [Double] = Array(repeating: 0.0, count: 18)
    @Published public var diskReadHistory: [Double] = Array(repeating: 0.0, count: 18)
    @Published public var diskWriteHistory: [Double] = Array(repeating: 0.0, count: 18)

    private var webSocketTask: URLSessionWebSocketTask?
    private var pingTimer: Timer?
    private var urlSession: URLSession?

    public init() {
        setupSession()
        connectWebSocket()
    }

    private func setupSession() {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:] // 绕过系统代理
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

                case .failure:
                    self.isOnline = false
                    self.reconnectAfterDelay()
                }
            }
        }
    }

    private func handleIncomingData(_ payloadData: Data) {
        if let decoded = try? JSONDecoder().decode(MetricsData.self, from: payloadData) {
            self.data = decoded

            updateHistory(&cpuHistory, newRatio: decoded.cpuUsage / 100.0)
            updateHistory(&netRxHistory, newRatio: min(Double(decoded.netRxBytesPerSec) / (1024 * 1024 * 10), 1.0))
            updateHistory(&netTxHistory, newRatio: min(Double(decoded.netTxBytesPerSec) / (1024 * 1024 * 5), 1.0))
            updateHistory(&diskReadHistory, newRatio: min(Double(decoded.diskReadBytesPerSec) / (1024 * 1024 * 20), 1.0))
            updateHistory(&diskWriteHistory, newRatio: min(Double(decoded.diskWriteBytesPerSec) / (1024 * 1024 * 20), 1.0))
        }
    }

    private func updateHistory(_ array: inout [Double], newRatio: Double) {
        array.append(max(0.0, min(1.0, newRatio)))
        if array.count > 18 { array.removeFirst() }
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
