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
    var viewModel: MonitorViewModel!
    private var cancellables = Set<AnyCancellable>()

    // 锁定状态栏长条物理宽度为 250pt
    private let fixedBarWidth: CGFloat = 275.0

    // 方案 A：现代 macOS 原生悬浮面板
    private var floatingPanel: ModernFloatingPanel!
    private var hostingController: NSHostingController<DetailPopoverView>!
    private var outsideClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        viewModel = MonitorViewModel()

        // 1. 创建状态栏项
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
        button.action = #selector(toggleFloatingPanel)

        // 2. 初始化现代无边框原生毛玻璃面板 (340pt 宽度)
        let detailView = DetailPopoverView(vm: viewModel)
        hostingController = NSHostingController(rootView: detailView)

        floatingPanel = ModernFloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 480))
        floatingPanel.contentViewController = hostingController
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

    /// 方案 A 核心：纯数学物理绝对居中定位（误差 0 像素）
    @objc func toggleFloatingPanel() {
        if floatingPanel.isVisible {
            hideFloatingPanel()
            return
        }

        guard let button = statusItem.button, let win = button.window else { return }

        NSApp.activate(ignoringOtherApps: true)

        // 1. 精确获取状态栏在当前显示器上的绝对屏幕 Rect (证实为 X=1027, 宽=250)
        let barScreenRect = win.convertToScreen(button.bounds)

        // 2. 计算弹窗自适应高度与绝对正中 X 坐标
        let panelWidth: CGFloat = 340.0
        let panelHeight = hostingController.view.fittingSize.height

        // 监控条真实物理中心: barScreenRect.midX (1152.0)
        // 弹窗绝对正中 X: 1152.0 - (340 / 2) = 982.0 (误差为 0)
        let targetX = barScreenRect.midX - (panelWidth / 2.0)
        let targetY = barScreenRect.minY - panelHeight - 6.0 // 悬停在菜单栏底下方 6pt 优雅间隙

        // 3. 屏幕边缘安全保护
        let currentScreen = win.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let safeX = max(10.0, min(currentScreen.frame.maxX - panelWidth - 10.0, targetX))

        // 4. 定位并流畅展现
        floatingPanel.setFrame(NSRect(x: safeX, y: targetY, width: panelWidth, height: panelHeight), display: true)
        floatingPanel.orderFront(nil)
        floatingPanel.makeKey()

        // 5. 注册全局事件：点击屏幕任何其他位置自动收起面板
        setupOutsideClickMonitor()
    }

    private func hideFloatingPanel() {
        floatingPanel.orderOut(nil)
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    private func setupOutsideClickMonitor() {
        if outsideClickMonitor != nil { return }
        // 捕获所有全局鼠标点击，实现原生收起
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.hideFloatingPanel()
            }
        }
    }
}

/// 现代 macOS 原生悬浮面板（与系统控制中心、Wi-Fi 弹窗一致的设计标准）
final class ModernFloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.isFloatingPanel = true
        self.level = .statusBar
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.animationBehavior = .utilityWindow
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = false
    }

    override var canBecomeKey: Bool {
        return true
    }
}
