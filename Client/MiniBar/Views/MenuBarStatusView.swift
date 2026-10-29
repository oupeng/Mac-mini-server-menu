import SwiftUI

struct MenuBarStatusView: View {
    @ObservedObject var vm: MonitorViewModel

    // 给定充足且绝对锁死的 248pt 宽度，杜绝一切裁切与抖动
    private let totalWidth: CGFloat = 248.0
    private let barHeight: CGFloat = 22.0

    var body: some View {
        HStack(spacing: 5) {
            if vm.isOnline, let d = vm.data {
                // 1. 温控与功耗 (分配 54pt，左侧留出充足安全边距)
                HStack(spacing: 3) {
                    Text("\(Int(d.cpuTemp))°")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    Text("\(Int(d.powerWatts))W")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.65))
                }
                .monospacedDigit()
                .frame(width: 54, alignment: .center)

                WhiteDivider()

                // 2. 实时网络吞吐 (分配 52pt，等宽数字)
                VStack(alignment: .trailing, spacing: 0) {
                    HStack(spacing: 2) {
                        Text("↓")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                        Text(formatSpeed(d.netRxBytesPerSec))
                            .foregroundColor(.white)
                    }
                    HStack(spacing: 2) {
                        Text("↑")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                        Text(formatSpeed(d.netTxBytesPerSec))
                            .foregroundColor(.white.opacity(0.85))
                    }
                }
                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .frame(width: 52, alignment: .trailing)

                WhiteDivider()

                // 3. 内存能量条 (分配 22pt)
                HStack(spacing: 3) {
                    Text("M")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundColor(.white.opacity(0.6))
                    WhiteCapsuleBar(ratio: d.memPercent / 100.0)
                        .frame(width: 5, height: 14)
                }
                .frame(width: 22, alignment: .center)

                WhiteDivider()

                // 4. CPU 实时曲线 (分配 38pt)
                HStack(spacing: 3) {
                    Text("C")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundColor(.white.opacity(0.6))
                    WhiteAreaSparkline(data: vm.cpuHistory)
                        .frame(width: 28, height: 14)
                }
                .frame(width: 38, alignment: .center)

                WhiteDivider()

                // 5. 磁盘活动 (分配 34pt，右侧留足边距防遮挡)
                HStack(spacing: 3) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 9.5))
                        .foregroundColor(.white.opacity(0.6))

                    WhiteDualSparkline(
                        topData: vm.diskReadHistory,
                        bottomData: vm.diskWriteHistory
                    )
                    .frame(width: 18, height: 14)
                }
                .frame(width: 34, alignment: .center)
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "desktopcomputer.trianglebadge.exclamationmark")
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                    Text("Mac mini 离线")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                .frame(width: totalWidth, alignment: .center)
            }
        }
        .padding(.horizontal, 4) // 核心：左右内边距留足，避免紧贴边缘被削切
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

struct WhiteDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.2))
            .frame(width: 0.5, height: 11)
    }
}

struct WhiteAreaSparkline: View {
    let data: [Double]
    private let width: CGFloat = 28.0
    private let height: CGFloat = 14.0

    var body: some View {
        let count = data.count
        let step = count > 1 ? width / CGFloat(count - 1) : width

        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 1.5)
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
        .clipShape(RoundedRectangle(cornerRadius: 1.5))
    }
}

struct WhiteDualSparkline: View {
    let topData: [Double]
    let bottomData: [Double]

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let midY = h / 2.0
            let step = topData.count > 1 ? w / CGFloat(topData.count - 1) : w

            context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 1.5), with: .color(Color.white.opacity(0.12)))

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

struct WhiteCapsuleBar: View {
    let ratio: Double
    private let width: CGFloat = 5.0
    private let height: CGFloat = 14.0

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
