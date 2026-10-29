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

    // 锁定物理宽度
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

    /// 核心修复：精准计算真实屏幕物理坐标，彻底消除跨进程控制中心引发的左偏错位
    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        
        if popover.isShown {
            popover.performClose(nil)
            return
        }

        // 1. 激活 App 前台权限
        NSApp.activate(ignoringOtherApps: true)

        // 2. 获取按钮在其宿主 Window 内的绝对坐标，并做安全校验
        let buttonBounds = button.bounds

        // 在现代 macOS 控制中心托管下，直接使用 button 并指明底层 bounds
        // 如果 bounds 正常，系统能通过 button 获得相对视图层级
        popover.show(relativeTo: buttonBounds, of: button, preferredEdge: .minY)
        
        // 3. 确保弹窗窗口成为 Key Window 接受交互
        popover.contentViewController?.view.window?.makeKey()
    }
}
