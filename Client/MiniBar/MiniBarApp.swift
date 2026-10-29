import AppKit
import SwiftUI
import Combine

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    var statusItem: NSStatusItem!
    var popover = NSPopover()
    var viewModel: MonitorViewModel!
    private var cancellables = Set<AnyCancellable>()

    // 固定 250pt 宽度
    private let fixedBarWidth: CGFloat = 250.0

    func applicationDidFinishLaunching(_ notification: Notification) {
        viewModel = MonitorViewModel()

        statusItem = NSStatusBar.system.statusItem(withLength: fixedBarWidth)
        guard let button = statusItem.button else { return }

        renderMenuBarImage()

        viewModel.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.renderMenuBarImage()
                }
            }
            .store(in: &cancellables)

        button.target = self
        button.action = #selector(togglePopover)

        popover.contentViewController = NSHostingController(rootView: DetailPopoverView(vm: viewModel))
        popover.behavior = .transient
    }

    @MainActor
    private func renderMenuBarImage() {
        guard let button = statusItem?.button else { return }

        let view = MenuBarStatusView(vm: viewModel)
        let renderer = ImageRenderer(content: view)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0

        if let image = renderer.nsImage {
            image.isTemplate = false
            button.image = image
            button.imagePosition = .imageOnly
            statusItem.length = fixedBarWidth
        }
    }

    /// 诊断版本的点击响应：打印所有坐标数据并尝试呼出弹窗
    @objc func togglePopover() {
        guard let button = statusItem.button else {
            print("[MiniBar 诊断] ❌ 失败: statusItem.button 为空！")
            return
        }

        print("===================== [MiniBar 诊断开始] =====================")
        // 1. 鼠标屏幕绝对物理坐标
        let mouseLoc = NSEvent.mouseLocation
        print("[诊断 1] 鼠标屏幕绝对坐标: X = \(mouseLoc.x), Y = \(mouseLoc.y)")

        // 2. 主屏幕信息
        if let screen = NSScreen.main {
            print("[诊断 2] 主屏幕 Frame: \(screen.frame), 顶部 Y = \(screen.frame.maxY)")
        }

        // 3. 按钮本身的 bounds
        print("[诊断 3] button.bounds: \(button.bounds)")

        // 4. 按钮所在系统窗口的 Frame 与绝对转换
        if let win = button.window {
            print("[诊断 4] button.window Frame: \(win.frame)")
            print("[诊断 5] button 转换到屏幕的绝对坐标: \(win.convertToScreen(button.bounds))")
        } else {
            print("[诊断 4/5] ⚠️ button.window 不存在！")
        }

        if popover.isShown {
            print("[诊断 6] Popover 当前为打开状态，执行关闭")
            popover.performClose(nil)
            print("============================================================\n")
            return
        }

        NSApp.activate(ignoringOtherApps: true)

        // 触发系统原生弹出
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        // 5. 弹出后检查弹窗真实的窗口位置
        if let popoverWindow = popover.contentViewController?.view.window {
            print("[诊断 7] 💥 Popover 最终生成的真实窗口 Frame: \(popoverWindow.frame)")
        }
        print("===================== [MiniBar 诊断结束] =====================\n")

        popover.contentViewController?.view.window?.makeKey()
    }
}
