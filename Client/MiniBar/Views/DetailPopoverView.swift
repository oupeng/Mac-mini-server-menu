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
                // 核心指标卡片
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        MetricCard(
                            title: "CPU 负荷",
                            value: String(format: "%.1f%%", d.cpuUsage),
                            subtitle: "\(Int(d.cpuTemp))°C  \(Int(d.powerWatts))W"
                        )
                        MetricCard(
                            title: "物理内存",
                            value: String(format: "%.1f%%", d.memPercent),
                            subtitle: "\(d.memUsedMB / 1024)G / \(d.memTotalMB / 1024)G"
                        )
                    }

                    HStack(spacing: 10) {
                        // 带有开机累计总吞吐量的物理网卡卡片
                        MetricCard(
                            title: "物理网络吞吐 (en0)",
                            value: "↓ \(formatDetailedSpeed(d.netRxBytesPerSec))",
                            subtitle: "↑ \(formatDetailedSpeed(d.netTxBytesPerSec))\n累计: ↓\(formatTotalBytes(d.totalRxBytes ?? 0))  ↑\(formatTotalBytes(d.totalTxBytes ?? 0))"
                        )

                        MetricCard(
                            title: "磁盘活动",
                            value: "R: \(formatDetailedSpeed(d.diskReadBytesPerSec))",
                            subtitle: "W: \(formatDetailedSpeed(d.diskWriteBytesPerSec))\nI/O 实时读写监控"
                        )
                    }
                }

                // 真实 Top 10 活跃进程列表
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("活跃进程 (Top 10)")
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

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 5) {
                            ForEach(d.topProcesses) { proc in
                                HStack {
                                    Text(proc.name)
                                        .font(.system(size: 11.5, weight: .regular))
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(proc.memMB) MB")
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    Text(String(format: "%.1f%%", proc.cpu))
                                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                        .frame(width: 45, alignment: .trailing)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 160) // 容纳 10 个进程的高品质滚动区
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))

                // 快捷直达运维工具
                HStack(spacing: 8) {
                    Button("打开屏幕镜像 (VNC)") {
                        if let url = URL(string: "vnc://\(vm.serverIP)") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)

                    Button("终端 SSH") {
                        if let url = URL(string: "ssh://\(vm.serverIP)") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
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
        .frame(width: 320)
    }

    private func formatUptime(_ seconds: Int) -> String {
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        return "\(days)天\(hours)时"
    }

    private func formatDetailedSpeed(_ bytes: UInt64) -> String {
        let kb = Double(bytes) / 1024.0
        if kb < 1024 { return String(format: "%.1f KB/s", kb) }
        return String(format: "%.2f MB/s", kb / 1024.0)
    }

    // 格式化开机累计总吞吐量 (GB / TB)
    private func formatTotalBytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / (1024.0 * 1024.0 * 1024.0)
        if gb < 1000 {
            return String(format: "%.1fG", gb)
        } else {
            return String(format: "%.2fT", gb / 1024.0)
        }
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
                .lineSpacing(2)
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
