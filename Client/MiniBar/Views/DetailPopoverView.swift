import SwiftUI
import AppKit

struct DetailPopoverView: View {
    @ObservedObject var vm: MonitorViewModel
    @State private var showingSettings: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            // 顶栏：服务器标题、运行时间与设置按钮
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
                // 核心指标卡片区
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
                        // 专为网络打造的无截断卡片：清晰展示实时速率 + 累计总吞吐
                        VStack(alignment: .leading, spacing: 4) {
                            Text("物理网络吞吐 (en0)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 6) {
                                Text("↓ \(formatDetailedSpeed(d.netRxBytesPerSec))")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                Text("↑ \(formatDetailedSpeed(d.netTxBytesPerSec))")
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                            
                            // 开机累计总吞吐量独立行展示，绝不省略号截断
                            Text("累计: ↓\(formatTotalBytes(d.totalRxBytes ?? 0))  ↑\(formatTotalBytes(d.totalTxBytes ?? 0))")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))

                        // 磁盘活动卡片
                        VStack(alignment: .leading, spacing: 4) {
                            Text("磁盘活动")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            
                            Text("R: \(formatDetailedSpeed(d.diskReadBytesPerSec))")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                            
                            Text("W: \(formatDetailedSpeed(d.diskWriteBytesPerSec))")
                                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                    }
                }

                // 完整铺开 10 个进程（以内存占用排序，无滚动条截断）
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

                    // 10 个进程完整直接平铺排布
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

                // 快捷运维工具
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
        .frame(width: 340) // 宽度加宽至 340pt，让所有文字与 10 个进程从容展开
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
