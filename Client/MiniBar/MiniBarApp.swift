import SwiftUI
import AppKit

@main
struct MiniBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover = NSPopover()
    var viewModel: MonitorViewModel!
    private var hostingView: PassthroughHostingView<MenuBarStatusView>!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 在主线程上下文中初始化 ViewModel
        viewModel = MonitorViewModel()

        // 1. 创建真正支持可变宽度的系统级状态栏项 (Variable Length)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem.button else { return }

        // 2. 将 SwiftUI 菜单栏完整视图嵌入 AppKit
        let statusView = MenuBarStatusView(vm: viewModel)
        hostingView = PassthroughHostingView(rootView: statusView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        button.addSubview(hostingView)

        // 3. 约束自动撑开：让宽度完全由 SwiftUI 内部所有图表决定
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: button.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])

        // 4. 点击事件绑定
        button.target = self
        button.action = #selector(togglePopover)

        // 5. 初始化弹出窗口 (带原生三角指示箭头的悬浮窗)
        popover.contentViewController = NSHostingController(rootView: DetailPopoverView(vm: viewModel))
        popover.behavior = .transient
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

/// 核心黑魔法：穿透点击，让 SwiftUI 负责完美渲染，所有点击无缝触发状态栏按钮
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil // 穿透给父级 NSStatusBarButton
    }

    override var intrinsicContentSize: NSSize {
        let size = fittingSize
        return NSSize(width: max(size.width, 30), height: 22)
    }
}
