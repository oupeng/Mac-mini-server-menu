import SwiftUI

struct MenuBarStatusView: View {
    @ObservedObject var vm: MonitorViewModel

    var body: some View {
        HStack(spacing: 6) {
            if vm.isOnline, let d = vm.data {
                // 1. 温度与功耗模块
                HStack(spacing: 2) {
                    Text("\(Int(d.cpuTemp))°")
                        .foregroundColor(.primary)
                    Text("\(Int(d.powerWatts))W")
                        .foregroundColor(.secondary)
                }
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))

                // 原生微弱分隔条
                Divider().frame(height: 10).opacity(0.4)

                // 2. 网络吞吐模块（上下行数字 + 双向波形图）
                HStack(spacing: 3) {
                    VStack(alignment: .trailing, spacing: -1) {
                        Text(formatCompact(d.netRxBytesPerSec))
                            .foregroundColor(.blue)
                        Text(formatCompact(d.netTxBytesPerSec))
                            .foregroundColor(.cyan)
                    }
                    .font(.system(size: 8, weight: .bold, design: .monospaced))

                    // 实时双向网络波形
                    MiniDualSparkline(
                        topData: vm.netRxHistory,
                        bottomData: vm.netTxHistory,
                        topColor: .blue,
                        bottomColor: .cyan
                    )
                    .frame(width: 24, height: 13)
                }

                Divider().frame(height: 10).opacity(0.4)

                // 3. 内存能量胶囊
                HStack(spacing: 2.5) {
                    VStack(alignment: .leading, spacing: -1) {
                        Text("M")
                            .font(.system(size: 7, weight: .heavy))
                            .foregroundColor(.secondary)
                        Text("\(Int(d.memPercent))%")
                            .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                    }
                    
                    // 现代垂直胶囊指示条
                    MiniVerticalCapsule(ratio: d.memPercent / 100.0, tint: .teal)
                        .frame(width: 4.5, height: 13)
                }

                Divider().frame(height: 10).opacity(0.4)

                // 4. CPU 负载模块（百分比 + 平滑面积折线图）
                HStack(spacing: 2.5) {
                    VStack(alignment: .leading, spacing: -1) {
                        Text("C")
                            .font(.system(size: 7, weight: .heavy))
                            .foregroundColor(.secondary)
                        Text("\(Int(d.cpuUsage))%")
                            .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                    }

                    // CPU 平滑面积波形图
                    MiniAreaSparkline(data: vm.cpuHistory, tint: d.cpuUsage > 75 ? .red : .indigo)
                        .frame(width: 24, height: 13)
                }

                Divider().frame(height: 10).opacity(0.4)

                // 5. 磁盘活动微图
                HStack(spacing: 2) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    
                    MiniDualSparkline(
                        topData: vm.diskReadHistory,
                        bottomData: vm.diskWriteHistory,
                        topColor: .orange,
                        bottomColor: .purple
                    )
                    .frame(width: 18, height: 13)
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
        .padding(.horizontal, 2)
    }

    private func formatCompact(_ bytes: UInt64) -> String {
        let kb = Double(bytes) / 1024.0
        if kb < 1000 {
            return String(format: "%3.0fK", kb)
        } else {
            return String(format: "%3.1fM", kb / 1024.0)
        }
    }
}

// MARK: - 现代原生微型波形图组件 (原生 Path 纯矢量绘制，零开销)

/// 单轨平滑面积波形图 (CPU 专用)
struct MiniAreaSparkline: View {
    let data: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let step = data.count > 1 ? w / CGFloat(data.count - 1) : w

            ZStack(alignment: .bottom) {
                // 背景微弱槽
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.primary.opacity(0.06))

                // 渐变填充面
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h))
                    for (i, val) in data.enumerated() {
                        let y = h - (CGFloat(val) * (h - 2)) - 1
                        p.addLine(to: CGPoint(x: CGFloat(i) * step, y: max(0, min(h, y))))
                    }
                    p.addLine(to: CGPoint(x: w, y: h))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [tint.opacity(0.6), tint.opacity(0.1)], startPoint: .top, endPoint: .bottom))

                // 顶端折线
                Path { p in
                    for (i, val) in data.enumerated() {
                        let x = CGFloat(i) * step
                        let y = h - (CGFloat(val) * (h - 2)) - 1
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(tint, lineWidth: 1.0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }
}

/// 双向对称流动波形图 (网络 & 磁盘专用：上轨读/下，下轨写/上)
struct MiniDualSparkline: View {
    let topData: [Double]
    let bottomData: [Double]
    let topColor: Color
    let bottomColor: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let midY = h / 2.0
            let step = topData.count > 1 ? w / CGFloat(topData.count - 1) : w

            ZStack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.primary.opacity(0.06))

                // 中轴基准线
                Path { p in
                    p.move(to: CGPoint(x: 0, y: midY))
                    p.addLine(to: CGPoint(x: w, y: midY))
                }
                .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)

                // 上半部流向 (下行 / 读)
                Path { p in
                    for (i, val) in topData.enumerated() {
                        let x = CGFloat(i) * step
                        let y = midY - (CGFloat(val) * (midY - 1))
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(topColor, lineWidth: 1.0)

                // 下半部流向 (上行 / 写)
                Path { p in
                    for (i, val) in bottomData.enumerated() {
                        let x = CGFloat(i) * step
                        let y = midY + (CGFloat(val) * (midY - 1))
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(bottomColor, lineWidth: 1.0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }
}

/// 现代垂直圆角胶囊能量条 (内存专用)
struct MiniVerticalCapsule: View {
    let ratio: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let w = geo.size.width
            let fillH = max(2, h * CGFloat(min(max(ratio, 0), 1)))

            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Color.primary.opacity(0.1))
                Capsule()
                    .fill(tint)
                    .frame(width: w, height: fillH)
            }
        }
    }
}
