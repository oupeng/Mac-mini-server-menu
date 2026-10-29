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

    // 核心参数：永久锁死状态栏宽度，绝无伸缩抖动
    private let fixedBarWidth: CGFloat = 185.0

    func applicationDidFinishLaunching(_ notification: Notification) {
        viewModel = MonitorViewModel()

        // 1. 创建固定宽度的状态栏项
        statusItem = NSStatusBar.system.statusItem(withLength: fixedBarWidth)
        guard let button = statusItem.button else { return }

        // 2. 初始渲染一次图像并绑定
        renderMenuBarImage()

        // 3. 核心：每当 WebSocket 推送新数据时，在主线程自动更新纯白图表
        viewModel.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.renderMenuBarImage()
                }
            }
            .store(in: &cancellables)

        // 4. 绑定点击弹窗事件
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
            // 宽度永远定死，禁止随着数字长度发生任何像素级抖动
            statusItem.length = fixedBarWidth
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
