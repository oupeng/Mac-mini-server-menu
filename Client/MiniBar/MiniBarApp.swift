import AppKit
import SwiftUI
import Combine

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    // 纯原生入口：启动系统事件循环，彻底杜绝无窗口自动退出
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // 声明为纯菜单栏后台常驻应用
        app.run()
    }

    var statusItem: NSStatusItem!
    var popover = NSPopover()
    var viewModel: MonitorViewModel!
    private var hostingView: PassthroughHostingView<MenuBarStatusView>!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. 初始化数据驱动
        viewModel = MonitorViewModel()

        // 2. 创建原生可变宽度的状态栏项
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }

        // 3. 将 SwiftUI 图表视图嵌入 AppKit 按钮
        let statusView = MenuBarStatusView(vm: viewModel)
        hostingView = PassthroughHostingView(rootView: statusView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: button.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])

        // 4. 核心：动态更新状态栏宽度，绝不让宽度变为 0
        updateStatusItemLength()
        viewModel.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItemLength()
            }
            .store(in: &cancellables)

        // 5. 绑定点击与弹窗
        button.target = self
        button.action = #selector(togglePopover)

        popover.contentViewController = NSHostingController(rootView: DetailPopoverView(vm: viewModel))
        popover.behavior = .transient

        print("[MiniBar] 状态栏应用已启动并稳稳常驻！")
    }

    private func updateStatusItemLength() {
        guard let button = statusItem?.button, let hostingView = hostingView else { return }
        let targetWidth = max(hostingView.fittingSize.width, 36)
        statusItem.length = targetWidth
        button.needsLayout = true
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

/// 穿透点击，让 SwiftUI 负责完美渲染，所有点击无缝触发状态栏按钮
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override var intrinsicContentSize: NSSize {
        let size = fittingSize
        return NSSize(width: max(size.width, 36), height: 22)
    }
}
