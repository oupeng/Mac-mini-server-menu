import SwiftUI
import AppKit

struct DetailPopoverView: View {
    @ObservedObject var vm: MonitorViewModel
    @State private var showingSettings: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label("Mac mini (Server)", systemImage: "server.rack")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if let d = vm.data, !showingSettings {
                    Text("运行: \(formatUptime(d.uptimeSeconds))")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Button(action: { showingSettings.toggle() }) {
                    Image(systemName: showingSettings ? "xmark.circle.fill" : "gearshape")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            if showingSettings {
                SettingsView(vm: vm, isPresented: $showingSettings)
            } else if let d = vm.data, vm.isOnline {
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        // 核心修改：明确三行文本结构，利用进程数和平均负载填充，让卡片高度严丝合缝对齐
                        let loadStr = String(format: "%.2f, %.2f, %.2f", d.loadAvg[0], d.loadAvg[1], d.loadAvg[2])
                        MetricCard(
                            title: "CPU 负荷",
                            value: String(format: "%.1f%%", d.cpuUsage),
                            subtitle: "温控: \(Int(d.cpuTemp))°C  \(Int(d.powerWatts))W\n进程: \(d.processCount ?? 0) 个\n负载: \(loadStr)"
                        )
                        
                        let pressureLevel = d.memPressureLevel ?? 1
                        let pressureStr = pressureLevel >= 4 ? "危险" : (pressureLevel >= 2 ? "警告" : "正常")
                        let pPct = Int(d.memPressurePercent ?? 0)
                        
                        MetricCard(
                            title: "物理内存与压力",
                            value: String(format: "%.1f%%", d.memPercent),
                            subtitle: "容量: \(d.memUsedMB / 1024)G / \(d.memTotalMB / 1024)G\n压力: \(pressureStr) (\(pPct)%)\n交换: \(d.swapUsedMB ?? 0) MB"
                        )
                    }

                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("物理网络吞吐 (en0)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)

                            HStack(spacing: 6) {
                                Text("↓ \(formatDetailedSpeedNoDecimal(d.netRxBytesPerSec))")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                Text("↑ \(formatDetailedSpeedNoDecimal(d.netTxBytesPerSec))")
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundColor(.secondary)
                            }

                            Text("累计: ↓\(formatTotalBytes(d.totalRxBytes ?? 0))  ↑\(formatTotalBytes(d.totalTxBytes ?? 0))")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("全局磁盘活动 (所有介质)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)

                            Text("R: \(formatDetailedSpeedNoDecimal(d.diskReadBytesPerSec))")
                                .font(.system(size: 12, weight: .bold, design: .rounded))

                            Text("W: \(formatDetailedSpeedNoDecimal(d.diskWriteBytesPerSec))")
                                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                    }
                }

                if let volumes = d.diskVolumes, !volumes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("存储空间与健康")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("10分钟更新")
                                .font(.system(size: 9.5))
                                .foregroundColor(.secondary.opacity(0.7))
                        }

                        VStack(spacing: 7) {
                            ForEach(volumes) { vol in
                                VStack(spacing: 3) {
                                    HStack {
                                        Text(vol.name)
                                            .font(.system(size: 11.5, weight: .medium))
                                            .lineLimit(1)
                                        Spacer()
                                        Text("剩余 \(formatTotalBytes(vol.freeBytes))")
                                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.85))

                                        Text(vol.smartStatus)
                                            .font(.system(size: 8.5, weight: .medium))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(
                                                RoundedRectangle(cornerRadius: 3)
                                                    .fill(smartBadgeBackground(vol.smartStatus))
                                            )
                                            .foregroundColor(smartBadgeForeground(vol.smartStatus))
                                    }

                                    GeometryReader { g in
                                        ZStack(alignment: .leading) {
                                            Capsule()
                                                .fill(Color.white.opacity(0.12))
                                            Capsule()
                                                .fill(LinearGradient(colors: [Color.white.opacity(0.8), Color.white.opacity(0.5)], startPoint: .leading, endPoint: .trailing))
                                                .frame(width: max(2, g.size.width * CGFloat(min(max(vol.usedPercent / 100.0, 0), 1))))
                                        }
                                    }
                                    .frame(height: 4.5)
                                }
                            }
                        }
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("活跃进程 (按内存排序 Top 10)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("内存")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text("CPU")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .frame(width: 45, alignment: .trailing)
                    }

                    VStack(spacing: 5) {
                        ForEach(d.topProcesses) { proc in
                            HStack {
                                Text(proc.name)
                                    .font(.system(size: 11, weight: .regular))
                                    .lineLimit(1)
                                Spacer()
                                Text("\(proc.memMB) MB")
                                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.teal)
                                Text(String(format: "%.1f%%", proc.cpu))
                                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 45, alignment: .trailing)
                            }
                        }
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))

            } else {
                VStack(spacing: 8) {
                    Text("无法连接至 Mac mini (WebSocket)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.red)
                    Button("重新连接") { vm.connectWebSocket() }
                        .controlSize(.small)
                }
                .frame(height: 120)
            }
        }
        .padding(14)
        .frame(width: 340)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func formatUptime(_ seconds: Int) -> String {
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        return "\(days)天\(hours)时"
    }

    private func formatDetailedSpeedNoDecimal(_ bytes: UInt64) -> String {
        let kb = Double(bytes) / 1024.0
        if kb < 1024 { return String(format: "%.0f KB/s", kb) }
        return String(format: "%.0f MB/s", kb / 1024.0)
    }

    private func formatTotalBytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / (1024.0 * 1024.0 * 1024.0)
        if gb < 1000 {
            return String(format: "%.1fG", gb)
        } else {
            return String(format: "%.2fT", gb / 1024.0)
        }
    }

    private func smartBadgeBackground(_ status: String) -> Color {
        if status == "良好" { return Color.white.opacity(0.1) }
        if status == "故障" { return Color.red.opacity(0.2) }
        return Color.white.opacity(0.06)
    }

    private func smartBadgeForeground(_ status: String) -> Color {
        if status == "良好" { return Color.white.opacity(0.8) }
        if status == "故障" { return Color.red.opacity(0.9) }
        return Color.secondary
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
            
            // 将副标题排版规范化，无论几行都确保行距一致且置顶对齐
            Text(subtitle)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundColor(.secondary)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
    }
}

struct SettingsView: View {
    @ObservedObject var vm: MonitorViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mac mini 局域网设置")
                .font(.system(size: 12, weight: .bold))

            VStack(spacing: 8) {
                HStack {
                    Text("固定 IP:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(width: 55, alignment: .trailing)
                    TextField("IP", text: $vm.serverIP)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                }

                HStack {
                    Text("服务端口:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(width: 55, alignment: .trailing)
                    TextField("Port", value: $vm.serverPort, formatter: NumberFormatter())
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                }
            }

            Divider().opacity(0.4)

            HStack {
                Button("保存并重连") {
                    isPresented = false
                    vm.connectWebSocket()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Spacer()
                
                Button(role: .destructive) {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("退出 MiniBar", systemImage: "power")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(6)
    }
}
