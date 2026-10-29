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
    @AppStorage("serverIP") public var serverIP: String = "192.168.1.100"
    @AppStorage("serverPort") public var serverPort: Int = 29876

    @Published public var data: MetricsData?
    @Published public var isOnline: Bool = false
    @Published public var cpuHistory: [Double] = Array(repeating: 0.0, count: 20)

    private var webSocketTask: URLSessionWebSocketTask?
    private var pingTimer: Timer?

    public init() {
        connectWebSocket()
    }

    public func connectWebSocket() {
        disconnect()

        guard let url = URL(string: "ws://\(serverIP):\(serverPort)") else { return }
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        self.webSocketTask = task
        task.resume()

        listenMessage()
        startHeartbeat()
    }

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
                    // 持续监听下一条推送
                    self.listenMessage()

                case .failure:
                    // 出现网络波动或 Mac mini 关机，瞬间感知并置为离线
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
            self?.webSocketTask?.sendPing { error in
                if error != nil {
                    Task { @MainActor [weak self] in
                        self?.isOnline = false
                    }
                }
            }
        }
    }

    private func reconnectAfterDelay() {
        disconnect()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.connectWebSocket()
        }
    }

    public func disconnect() {
        pingTimer?.invalidate()
        pingTimer = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }
}
