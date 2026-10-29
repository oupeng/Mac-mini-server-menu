import SwiftUI

struct MenuBarStatusView: View {
    @ObservedObject var vm: MonitorViewModel

    // 全面放大尺度后的总宽度，锁死定宽绝不抖动
    private let totalWidth: CGFloat = 230.0
    private let barHeight: CGFloat = 22.0

    var body: some View {
        HStack(spacing: 6) {
            if vm.isOnline, let d = vm.data {
                // 1. 温控与功耗 (放宽至 52pt，彻底消除 4... 1... 截断)
                HStack(spacing: 3) {
                    Text("\(Int(d.cpuTemp))°")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    Text("\(Int(d.powerWatts))W")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.65))
                }
                .monospacedDigit()
                .frame(width: 52, alignment: .center)

                WhiteDivider()

                // 2. 实时网络吞吐 (仅文字，字号放大至 9pt 等宽，定宽 52pt)
                VStack(alignment: .trailing, spacing: 0) {
                    HStack(spacing: 2) {
                        Text("↓")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                        Text(formatSpeed(d.netRxBytesPerSec))
                            .foregroundColor(.white)
                    }
                    HStack(spacing: 2) {
                        Text("↑")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                        Text(formatSpeed(d.netTxBytesPerSec))
                            .foregroundColor(.white.opacity(0.85))
                    }
                }
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .frame(width: 52, alignment: .trailing)

                WhiteDivider()

                // 3. 内存能量条 (加粗胶囊，定宽 20pt)
                HStack(spacing: 3) {
                    Text("M")
                        .font(.system(size: 8.5, weight: .heavy))
                        .foregroundColor(.white.opacity(0.6))
                    WhiteCapsuleBar(ratio: d.memPercent / 100.0)
                        .frame(width: 5.5, height: 15)
                }
                .frame(width: 20, alignment: .center)

                WhiteDivider()

                // 4. CPU 实时曲线 (高度升至 15pt，宽 28pt，定宽 38pt)
                HStack(spacing: 3) {
                    Text("C")
                        .font(.system(size: 8.5, weight: .heavy))
                        .foregroundColor(.white.opacity(0.6))
                    WhiteAreaSparkline(data: vm.cpuHistory)
                        .frame(width: 28, height: 15)
                }
                .frame(width: 38, alignment: .center)

                WhiteDivider()

                // 5. 磁盘活动 (加大波形至 20x15，定宽 32pt)
                HStack(spacing: 3) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.6))

                    WhiteDualSparkline(
                        topData: vm.diskReadHistory,
                        bottomData: vm.diskWriteHistory
                    )
                    .frame(width: 20, height: 15)
                }
                .frame(width: 32, alignment: .center)
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "desktopcomputer.trianglebadge.exclamationmark")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                    Text("Mac mini 离线")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                .frame(width: totalWidth, alignment: .center)
            }
        }
        .frame(width: totalWidth, height: barHeight)
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

// MARK: - 纯白细分隔条
struct WhiteDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.2))
            .frame(width: 0.5, height: 12)
    }
}

// MARK: - 纯白高清矢量图表（高度全面升级至 15pt）

/// CPU 面积图 (提升至 28x15)
struct WhiteAreaSparkline: View {
    let data: [Double]
    private let width: CGFloat = 28.0
    private let height: CGFloat = 15.0

    var body: some View {
        let count = data.count
        let step = count > 1 ? width / CGFloat(count - 1) : width

        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.12))

            Path { p in
                p.move(to: CGPoint(x: 0, y: height))
                for (i, val) in data.enumerated() {
                    let y = height - (CGFloat(val) * (height - 2)) - 1
                    p.addLine(to: CGPoint(x: CGFloat(i) * step, y: max(0, min(height, y))))
                }
                p.addLine(to: CGPoint(x: width, y: height))
                p.closeSubpath()
            }
            .fill(LinearGradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0.1)], startPoint: .top, endPoint: .bottom))

            Path { p in
                for (i, val) in data.enumerated() {
                    let x = CGFloat(i) * step
                    let y = height - (CGFloat(val) * (height - 2)) - 1
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(Color.white, lineWidth: 1.0)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}

/// 磁盘双向图 (提升至 20x15)
struct WhiteDualSparkline: View {
    let topData: [Double]
    let bottomData: [Double]

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let midY = h / 2.0
            let step = topData.count > 1 ? w / CGFloat(topData.count - 1) : w

            context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 2), with: .color(Color.white.opacity(0.12)))

            var midLine = Path()
            midLine.move(to: CGPoint(x: 0, y: midY))
            midLine.addLine(to: CGPoint(x: w, y: midY))
            context.stroke(midLine, with: .color(Color.white.opacity(0.25)), lineWidth: 0.5)

            var topPath = Path()
            for (i, val) in topData.enumerated() {
                let x = CGFloat(i) * step
                let y = midY - (CGFloat(val) * (midY - 1))
                if i == 0 { topPath.move(to: CGPoint(x: x, y: y)) } else { topPath.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(topPath, with: .color(Color.white), lineWidth: 1.0)

            var bottomPath = Path()
            for (i, val) in bottomData.enumerated() {
                let x = CGFloat(i) * step
                let y = midY + (CGFloat(val) * (midY - 1))
                if i == 0 { bottomPath.move(to: CGPoint(x: x, y: y)) } else { bottomPath.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(bottomPath, with: .color(Color.white.opacity(0.7)), lineWidth: 1.0)
        }
    }
}

/// 垂直能量胶囊 (加粗提升至 5.5x15)
struct WhiteCapsuleBar: View {
    let ratio: Double
    private let width: CGFloat = 5.5
    private let height: CGFloat = 15.0

    var body: some View {
        let fillH = max(2, height * CGFloat(min(max(ratio, 0), 1)))

        ZStack(alignment: .bottom) {
            Capsule()
                .fill(Color.white.opacity(0.18))
            Capsule()
                .fill(Color.white)
                .frame(width: width, height: fillH)
        }
        .frame(width: width, height: height)
    }
}
