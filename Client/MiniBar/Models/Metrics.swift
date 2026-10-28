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

    private var timer: Timer?

    public init() {
        startPolling()
    }

    public func startPolling() {
        timer?.invalidate()
        fetch()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.fetch()
            }
        }
    }

    public func fetch() {
        guard let url = URL(string: "http://\(serverIP):\(serverPort)/metrics") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.0

        URLSession.shared.dataTask(with: request) { [weak self] payloadData, _, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let payloadData = payloadData,
                   let decoded = try? JSONDecoder().decode(MetricsData.self, from: payloadData) {
                    self.data = decoded
                    self.isOnline = true
                    self.cpuHistory.append(decoded.cpuUsage)
                    if self.cpuHistory.count > 20 { self.cpuHistory.removeFirst() }
                } else {
                    self.isOnline = false
                }
            }
        }.resume()
    }
}
