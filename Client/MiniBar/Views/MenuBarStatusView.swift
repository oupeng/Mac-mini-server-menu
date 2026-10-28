import SwiftUI

struct MenuBarStatusView: View {
    @ObservedObject var vm: MonitorViewModel

    var body: some View {
        HStack(spacing: 7) {
            if vm.isOnline, let d = vm.data {
                // 1. 温度与功耗 (微型紧凑数字)
                HStack(spacing: 3) {
                    Text("\(Int(d.cpuTemp))°")
                    Text("\(Int(d.powerWatts))W")
                        .foregroundColor(.secondary)
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))

                Divider().frame(height: 11)

                // 2. 实时网速
                HStack(spacing: 2) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.blue)
                    Text(formatSpeed(d.netRxBytesPerSec))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))

                    Image(systemName: "arrow.up")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.cyan)
                    Text(formatSpeed(d.netTxBytesPerSec))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }

                Divider().frame(height: 11)

                // 3. 内存与 CPU 原生微型指示条
                HStack(spacing: 4) {
                    MiniProgressBar(label: "M", value: d.memPercent / 100.0, tint: .teal)
                    MiniProgressBar(label: "C", value: d.cpuUsage / 100.0, tint: d.cpuUsage > 75 ? .red : .blue)
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "desktopcomputer.trianglebadge.exclamationmark")
                        .symbolRenderingMode(.multicolor)
                    Text("Mac mini 离线")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private func formatSpeed(_ bytes: UInt64) -> String {
        let kb = Double(bytes) / 1024.0
        if kb < 1000 {
            return String(format: "%.0fK", kb)
        } else {
            return String(format: "%.1fM", kb / 1024.0)
        }
    }
}

// 原生 macOS 26 微型紧凑刻度条
struct MiniProgressBar: View {
    let label: String
    let value: Double
    let tint: Color

    var body: some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy))
                .foregroundColor(.secondary)
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 5, height: 12)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(tint)
                    .frame(width: 5, height: max(2, 12 * CGFloat(min(max(value, 0), 1))))
            }
        }
    }
}
