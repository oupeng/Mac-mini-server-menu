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

    // 锁定物理宽度为 250pt
    private let fixedBarWidth: CGFloat = 250.0

    // 居中锚点视图（用于绕过 NSStatusBarButton 的 24pt 私有左偏机制）
    private var centerAnchorView: CenterAnchorView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        viewModel = MonitorViewModel()

        statusItem = NSStatusBar.system.statusItem(withLength: fixedBarWidth)
        guard let button = statusItem.button else { return }

        // 核心技术点：在 250pt 的几何正中心 (X=124~126) 埋下透明穿透锚点
        let anchor = CenterAnchorView(frame: NSRect(x: (fixedBarWidth / 2.0) - 1.0, y: 0, width: 2.0, height: 22.0))
        button.addSubview(anchor)
        self.centerAnchorView = anchor

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

    /// 选项 1 落地：小三角箭头永远 100% 精准对准长条正中心
    @objc func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }

        guard let anchor = centerAnchorView else { return }

        NSApp.activate(ignoringOtherApps: true)

        // 关键：以正中心的普通 NSView 为基准弹出，彻底破除系统的左偏判定！
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}

/// 纯透明且彻底穿透点击的中心锚点视图（绝不干扰任何鼠标交互）
final class CenterAnchorView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil // 彻底穿透给底层的状态栏按钮，保障全长条点击响应
    }
}
