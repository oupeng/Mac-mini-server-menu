import SwiftUI

struct MenuBarStatusView: View {
    @ObservedObject var vm: MonitorViewModel

    var body: some View {
        HStack(spacing: 5) {
            if vm.isOnline, let d = vm.data {
                // 1. 温度与功耗模块
                HStack(spacing: 2) {
                    Text("\(Int(d.cpuTemp))°")
                        .foregroundColor(.primary)
                    Text("\(Int(d.powerWatts))W")
                        .foregroundColor(.secondary)
                }
                .font(.system(size: 10, weight: .semibold, design: .rounded))

                // 原生细分隔线
                Rectangle()
                    .fill(Color.primary.opacity(0.2))
                    .frame(width: 0.5, height: 11)

                // 2. 实时网络吞吐（上下行文字 + 双向微型波形）
                HStack(spacing: 2) {
                    VStack(alignment: .trailing, spacing: -2) {
                        Text(formatSpeed(d.netRxBytesPerSec))
                            .foregroundColor(.blue)
                        Text(formatSpeed(d.netTxBytesPerSec))
                            .foregroundColor(.cyan)
                    }
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))

                    // 固定 24x12 的双向矢量流动图
                    FixedDualSparkline(
                        topData: vm.netRxHistory,
                        bottomData: vm.netTxHistory,
                        topColor: .blue,
                        bottomColor: .cyan
                    )
                    .frame(width: 24, height: 12)
                }

                Rectangle()
                    .fill(Color.primary.opacity(0.2))
                    .frame(width: 0.5, height: 11)

                // 3. 内存能量条模块 (带 M 标签 + 垂直能量条)
                HStack(spacing: 2) {
                    VStack(alignment: .trailing, spacing: -2) {
                        Text("M")
                            .font(.system(size: 6.5, weight: .black))
                            .foregroundColor(.secondary)
                        Text("\(Int(d.memPercent))%")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                    }
                    FixedCapsuleBar(ratio: d.memPercent / 100.0, tint: .teal)
                        .frame(width: 4, height: 12)
                }

                Rectangle()
                    .fill(Color.primary.opacity(0.2))
                    .frame(width: 0.5, height: 11)

                // 4. CPU 负载模块 (带 C 标签 + 实时平滑面积折线图)
                HStack(spacing: 2) {
                    VStack(alignment: .trailing, spacing: -2) {
                        Text("C")
                            .font(.system(size: 6.5, weight: .black))
                            .foregroundColor(.secondary)
                        Text("\(Int(d.cpuUsage))%")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                    }
                    FixedAreaSparkline(data: vm.cpuHistory, tint: d.cpuUsage > 75 ? .red : .indigo)
                        .frame(width: 24, height: 12)
                }

                Rectangle()
                    .fill(Color.primary.opacity(0.2))
                    .frame(width: 0.5, height: 11)

                // 5. 磁盘 I/O 读写波形模块
                HStack(spacing: 2) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)

                    FixedDualSparkline(
                        topData: vm.diskReadHistory,
                        bottomData: vm.diskWriteHistory,
                        topColor: .orange,
                        bottomColor: .purple
                    )
                    .frame(width: 18, height: 12)
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "desktopcomputer.trianglebadge.exclamationmark")
                        .symbolRenderingMode(.multicolor)
                    Text("Mac mini 离线")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 3)
        .fixedSize() // 核心关键：强制命令 macOS 菜单栏撑开到真实宽度，绝不截断！
    }

    private func formatSpeed(_ bytes: UInt64) -> String {
        let kb = Double(bytes) / 1024.0
        if kb < 1000 {
            return String(format: "%3.0fK", kb)
        } else {
            return String(format: "%3.1fM", kb / 1024.0)
        }
    }
}

// MARK: - 纯矢量定宽微型图表（彻底弃用 GeometryReader，彻底杜绝尺寸坍缩）

/// CPU 面积平滑图 (固定 24x12)
struct FixedAreaSparkline: View {
    let data: [Double]
    let tint: Color

    private let width: CGFloat = 24.0
    private let height: CGFloat = 12.0

    var body: some View {
        let count = data.count
        let step = count > 1 ? width / CGFloat(count - 1) : width

        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.primary.opacity(0.08))

            // 面积填充
            Path { p in
                p.move(to: CGPoint(x: 0, y: height))
                for (i, val) in data.enumerated() {
                    let y = height - (CGFloat(val) * (height - 2)) - 1
                    p.addLine(to: CGPoint(x: CGFloat(i) * step, y: max(0, min(height, y))))
                }
                p.addLine(to: CGPoint(x: width, y: height))
                p.closeSubpath()
            }
            .fill(LinearGradient(colors: [tint.opacity(0.65), tint.opacity(0.15)], startPoint: .top, endPoint: .bottom))

            // 顶端折线
            Path { p in
                for (i, val) in data.enumerated() {
                    let x = CGFloat(i) * step
                    let y = height - (CGFloat(val) * (height - 2)) - 1
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(tint, lineWidth: 1.0)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 1.5))
    }
}

/// 双向对称流动波形图 (网络 24x12 / 磁盘 18x12)
struct FixedDualSparkline: View {
    let topData: [Double]
    let bottomData: [Double]
    let topColor: Color
    let bottomColor: Color

    var body: some View {
        // 使用自身 frame 约束，中轴定在 6.0
        let h: CGFloat = 12.0
        let midY: CGFloat = 6.0

        Canvas { context, size in
            let w = size.width
            let step = topData.count > 1 ? w / CGFloat(topData.count - 1) : w

            // 底板
            context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 1.5), with: .color(Color.primary.opacity(0.08)))

            // 中轴线
            var midLine = Path()
            midLine.move(to: CGPoint(x: 0, y: midY))
            midLine.addLine(to: CGPoint(x: w, y: midY))
            context.stroke(midLine, with: .color(Color.primary.opacity(0.2)), lineWidth: 0.5)

            // 上轨（下行 / 读）
            var topPath = Path()
            for (i, val) in topData.enumerated() {
                let x = CGFloat(i) * step
                let y = midY - (CGFloat(val) * (midY - 1))
                if i == 0 { topPath.move(to: CGPoint(x: x, y: y)) } else { topPath.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(topPath, with: .color(topColor), lineWidth: 1.0)

            // 下轨（上行 / 写）
            var bottomPath = Path()
            for (i, val) in bottomData.enumerated() {
                let x = CGFloat(i) * step
                let y = midY + (CGFloat(val) * (midY - 1))
                if i == 0 { bottomPath.move(to: CGPoint(x: x, y: y)) } else { bottomPath.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(bottomPath, with: .color(bottomColor), lineWidth: 1.0)
        }
    }
}

/// 垂直能量胶囊条 (固定 4x12)
struct FixedCapsuleBar: View {
    let ratio: Double
    let tint: Color

    private let width: CGFloat = 4.0
    private let height: CGFloat = 12.0

    var body: some View {
        let fillH = max(2, height * CGFloat(min(max(ratio, 0), 1)))

        ZStack(alignment: .bottom) {
            Capsule()
                .fill(Color.primary.opacity(0.12))
            Capsule()
                .fill(tint)
                .frame(width: width, height: fillH)
        }
        .frame(width: width, height: height)
    }
}
