import SwiftUI

struct MenuBarStatusView: View {
    @ObservedObject var vm: MonitorViewModel

    var body: some View {
        HStack(spacing: 6) {
            if vm.isOnline, let d = vm.data {
                // 1. 温度与功耗模块
                HStack(spacing: 3) {
                    Text("\(Int(d.cpuTemp))°")
                        .foregroundColor(.primary)
                    Text("\(Int(d.powerWatts))W")
                        .foregroundColor(.secondary)
                }
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))

                DividerLine()

                // 2. 实时网络吞吐 (上下行数值 + 双向波形图)
                HStack(spacing: 3) {
                    VStack(alignment: .trailing, spacing: -2) {
                        Text(formatSpeed(d.netRxBytesPerSec))
                            .foregroundColor(.blue)
                        Text(formatSpeed(d.netTxBytesPerSec))
                            .foregroundColor(.cyan)
                    }
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))

                    FixedDualSparkline(
                        topData: vm.netRxHistory,
                        bottomData: vm.netTxHistory,
                        topColor: .blue,
                        bottomColor: .cyan
                    )
                    .frame(width: 26, height: 12)
                }

                DividerLine()

                // 3. 内存能量条 (带 M 标签 + 垂直能量柱)
                HStack(spacing: 2.5) {
                    VStack(alignment: .trailing, spacing: -2) {
                        Text("M")
                            .font(.system(size: 6.5, weight: .black))
                            .foregroundColor(.secondary)
                        Text("\(Int(d.memPercent))%")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                    }
                    FixedCapsuleBar(ratio: d.memPercent / 100.0, tint: .teal)
                        .frame(width: 4.5, height: 12)
                }

                DividerLine()

                // 4. CPU 负载模块 (带 C 标签 + 平滑面积折线图)
                HStack(spacing: 2.5) {
                    VStack(alignment: .trailing, spacing: -2) {
                        Text("C")
                            .font(.system(size: 6.5, weight: .black))
                            .foregroundColor(.secondary)
                        Text("\(Int(d.cpuUsage))%")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                    }
                    FixedAreaSparkline(data: vm.cpuHistory, tint: d.cpuUsage > 75 ? .red : .indigo)
                        .frame(width: 26, height: 12)
                }

                DividerLine()

                // 5. 磁盘活动波形图
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
                    .frame(width: 20, height: 12)
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "desktopcomputer.trianglebadge.exclamationmark")
                        .symbolRenderingMode(.multicolor)
                    Text("Mac mini 离线")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 22)
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

struct DividerLine: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.18))
            .frame(width: 0.5, height: 10)
    }
}

// MARK: - 矢量图表组件

struct FixedAreaSparkline: View {
    let data: [Double]
    let tint: Color

    private let width: CGFloat = 26.0
    private let height: CGFloat = 12.0

    var body: some View {
        let count = data.count
        let step = count > 1 ? width / CGFloat(count - 1) : width

        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.primary.opacity(0.08))

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

struct FixedDualSparkline: View {
    let topData: [Double]
    let bottomData: [Double]
    let topColor: Color
    let bottomColor: Color

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let midY = h / 2.0
            let step = topData.count > 1 ? w / CGFloat(topData.count - 1) : w

            context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 1.5), with: .color(Color.primary.opacity(0.08)))

            var midLine = Path()
            midLine.move(to: CGPoint(x: 0, y: midY))
            midLine.addLine(to: CGPoint(x: w, y: midY))
            context.stroke(midLine, with: .color(Color.primary.opacity(0.2)), lineWidth: 0.5)

            var topPath = Path()
            for (i, val) in topData.enumerated() {
                let x = CGFloat(i) * step
                let y = midY - (CGFloat(val) * (midY - 1))
                if i == 0 { topPath.move(to: CGPoint(x: x, y: y)) } else { topPath.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(topPath, with: .color(topColor), lineWidth: 1.0)

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

struct FixedCapsuleBar: View {
    let ratio: Double
    let tint: Color

    private let width: CGFloat = 4.5
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
