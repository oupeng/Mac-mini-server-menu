import AppKit
import SwiftUI
import Combine

@main
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        viewModel = MonitorViewModel()

        // 1. 创建状态栏项
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }

        // 2. 初始渲染一次图像并绑定
        renderMenuBarImage()

        // 3. 核心：每当 WebSocket 推送新数据时，自动更新高清状态栏图表
        viewModel.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.renderMenuBarImage()
            }
            .store(in: &cancellables)

        // 4. 绑定点击弹窗事件
        button.target = self
        button.action = #selector(togglePopover)

        popover.contentViewController = NSHostingController(rootView: DetailPopoverView(vm: viewModel))
        popover.behavior = .transient
    }

    /// 现代 macOS 官方标准方案：将 SwiftUI 视图以超高清方式渲染为 NSImage 跨进程投射到控制中心
    private func renderMenuBarImage() {
        guard let button = statusItem?.button else { return }

        let view = MenuBarStatusView(vm: viewModel)
        let renderer = ImageRenderer(content: view)
        // 匹配 MacBook Pro 原生屏幕的 2.0x 视网膜缩放比
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0

        if let image = renderer.nsImage {
            // 设置为 false 以保留完整的原生彩色（蓝色网速、青色上行、紫色磁盘等）
            image.isTemplate = false
            button.image = image
            button.imagePosition = .imageOnly
            statusItem.length = image.size.width
        }
    }

    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
