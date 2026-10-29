import SwiftUI
import AppKit

struct DetailPopoverView: View {
    @ObservedObject var vm: MonitorViewModel
    @State private var showingSettings: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            // 顶栏：服务器标题与操作
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
                // 1. 核心指标区
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        MetricCard(
                            title: "CPU 负荷",
                            value: String(format: "%.1f%%", d.cpuUsage),
                            subtitle: "\(Int(d.cpuTemp))°C  \(Int(d.powerWatts))W"
                        )
                        
                        // 核心变更：内存与详细压力展示
                        let pressureLevel = d.memPressureLevel ?? 1
                        let pressureStr = pressureLevel >= 4 ? "危险 (Critical)" : (pressureLevel >= 2 ? "警告 (Warning)" : "正常 (Normal)")
                        MetricCard(
                            title: "物理内存与压力",
                            value: String(format: "%.1f%%", d.memPercent),
                            subtitle: "\(d.memUsedMB / 1024)G / \(d.memTotalMB / 1024)G\n压力: \(pressureStr)  已交换: \(d.swapUsedMB ?? 0)M"
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
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                        .frame(maxWidth: .infinity, alignment: .leading)
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

                // 3. 活跃进程
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

                // 4. 底部快捷按钮（只保留 1 个打开屏幕镜像）
                HStack {
                    Spacer()
                    Button("打开屏幕镜像") {
                        if let url = URL(string: "vnc://DPHomedeMac-mini.local") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                    Spacer()
                }
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
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundColor(.secondary)
                .lineSpacing(2) // 增加行距，避免三行文字过于拥挤
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
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
