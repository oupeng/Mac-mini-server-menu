import SwiftUI

struct MenuBarStatusView: View {
    @ObservedObject var vm: MonitorViewModel

    // 因为内存模块变宽，整体物理定宽扩充至 275.0
    private let totalWidth: CGFloat = 275.0
    private let barHeight: CGFloat = 22.0

    var body: some View {
        HStack(spacing: 5) {
            if vm.isOnline, let d = vm.data {
                // 1. 温控与功耗
                HStack(spacing: 3) {
                    Text("\(Int(d.cpuTemp))°")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    Text("\(Int(d.powerWatts))W")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.65))
                }
                .monospacedDigit()
                .frame(width: 52, alignment: .center)

                WhiteDivider()

                // 2. 实时网络吞吐
                VStack(alignment: .trailing, spacing: 0) {
                    HStack(spacing: 1) {
                        Text("↓")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                        Text(formatSpeedNoDecimal(d.netRxBytesPerSec))
                            .foregroundColor(.white)
                    }
                    HStack(spacing: 1) {
                        Text("↑")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                        Text(formatSpeedNoDecimal(d.netTxBytesPerSec))
                            .foregroundColor(.white.opacity(0.85))
                    }
                }
                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)

                WhiteDivider()

                // 3. 核心修改：内存压力面积图 (白/黄/红三档动态着色)
                let pressure = d.memPressureLevel ?? 1
                let memColor: Color = pressure >= 4 ? .red : (pressure >= 2 ? .yellow : .white)

                HStack(spacing: 3) {
                    Text("M")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundColor(memColor == .white ? .white.opacity(0.6) : memColor)
                    
                    // 完全替换为活动监视器风格的面积图，高度反映真实内存核心压力
                    WideAreaSparkline(data: vm.memPressureHistory, tint: memColor)
                        .frame(width: 30, height: 15)
                }
                .frame(width: 44, alignment: .center)

                WhiteDivider()

                // 4. CPU 实时曲线
                HStack(spacing: 3) {
                    Text("C")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundColor(.white.opacity(0.6))
                    WideAreaSparkline(data: vm.cpuHistory, tint: .white)
                        .frame(width: 30, height: 15)
                }
                .frame(width: 44, alignment: .center)

                WhiteDivider()

                // 5. 磁盘活动
                HStack(spacing: 3) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 9.5))
                        .foregroundColor(.white.opacity(0.6))

                    WideDualSparkline(
                        topData: vm.diskReadHistory,
                        bottomData: vm.diskWriteHistory
                    )
                    .frame(width: 30, height: 15)
                }
                .frame(width: 44, alignment: .center)
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
        .padding(.horizontal, 4)
        .frame(width: totalWidth, height: barHeight)
    }

    private func formatSpeedNoDecimal(_ bytes: UInt64) -> String {
        let kb = Double(bytes) / 1024.0
        if kb < 1000 {
            return String(format: "%.0fK", kb)
        } else {
            return String(format: "%.0fM", kb / 1024.0)
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

// 修改面积图使其支持外界传入动态色彩 (tint)
struct WideAreaSparkline: View {
    let data: [Double]
    var tint: Color = .white // 默认白色
    private let width: CGFloat = 30.0
    private let height: CGFloat = 15.0

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
            .fill(LinearGradient(colors: [tint.opacity(0.45), tint.opacity(0.1)], startPoint: .top, endPoint: .bottom))

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

struct WideDualSparkline: View {
    let topData: [Double]
    let bottomData: [Double]
    private let width: CGFloat = 30.0
    private let height: CGFloat = 15.0

    var body: some View {
        let midY: CGFloat = height / 2.0

        Canvas { context, _ in
            let step = topData.count > 1 ? width / CGFloat(topData.count - 1) : width

            context.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: width, height: height), cornerRadius: 1.5), with: .color(Color.white.opacity(0.12)))

            var midLine = Path()
            midLine.move(to: CGPoint(x: 0, y: midY))
            midLine.addLine(to: CGPoint(x: width, y: midY))
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
        .frame(width: width, height: height)
    }
}
