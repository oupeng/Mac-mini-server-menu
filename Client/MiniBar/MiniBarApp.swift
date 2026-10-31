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

    // 状态栏长条物理宽度
    private let fixedBarWidth: CGFloat = 275.0

    // 现代无箭头原生悬浮面板
    private var floatingPanel: ModernFloatingPanel!
    private var hostingController: NSHostingController<DetailPopoverView>!
    private var outsideClickMonitor: Any?

    // 息屏与锁屏状态标记（屏幕熄灭期间完全停止绘制）
    private var isDisplaySleeping: Bool = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        viewModel = MonitorViewModel()

        // 1. 初始化状态栏项
        statusItem = NSStatusBar.system.statusItem(withLength: fixedBarWidth)
        guard let button = statusItem.button else { return }

        renderMenuBarImage()

        // 2. 订阅数据源驱动重绘
        viewModel.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.renderMenuBarImage()
                }
            }
            .store(in: &cancellables)

        // 3. 注册系统级息屏/亮屏通知（休眠、合盖时立刻挂起绘制，唤醒后首帧补齐）
        setupDisplaySleepWatchers()

        button.target = self
        button.action = #selector(toggleFloatingPanel)

        // 4. 初始化详情悬浮面板
        let detailView = DetailPopoverView(vm: viewModel)
        hostingController = NSHostingController(rootView: detailView)

        floatingPanel = ModernFloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 480))
        floatingPanel.contentViewController = hostingController
    }

    /// 屏幕休眠监控：合盖或息屏时安全挂起渲染
    private func setupDisplaySleepWatchers() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        
        wsCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isDisplaySleeping = true
            }
        }
        
        wsCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isDisplaySleeping = false
                self?.renderMenuBarImage()
            }
        }
    }

    /// 菜单栏图像渲染（带息屏安全跳过机制）
    @MainActor
    private func renderMenuBarImage() {
        if isDisplaySleeping { return }
        
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

    @objc func toggleFloatingPanel() {
        if floatingPanel.isVisible {
            hideFloatingPanel()
            return
        }

        guard let button = statusItem.button, let win = button.window else { return }

        NSApp.activate(ignoringOtherApps: true)

        let barScreenRect = win.convertToScreen(button.bounds)
        let panelWidth: CGFloat = 340.0
        let panelHeight = hostingController.view.fittingSize.height

        let targetX = barScreenRect.midX - (panelWidth / 2.0)
        let targetY = barScreenRect.minY - panelHeight - 6.0

        let currentScreen = win.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let safeX = max(10.0, min(currentScreen.frame.maxX - panelWidth - 10.0, targetX))

        floatingPanel.setFrame(NSRect(x: safeX, y: targetY, width: panelWidth, height: panelHeight), display: true)
        floatingPanel.orderFront(nil)
        floatingPanel.makeKey()

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
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.hideFloatingPanel()
            }
        }
    }
}

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
