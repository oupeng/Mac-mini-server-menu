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

    // 核心优化 1：复用单例 ImageRenderer，杜绝每秒重建渲染管线带来的内存碎片
    private var cachedRenderer: ImageRenderer<MenuBarStatusView>?
    
    // 核心优化 2：息屏与锁屏状态标记（屏幕熄灭期间完全停止绘制）
    private var isDisplaySleeping: Bool = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        viewModel = MonitorViewModel()

        // 1. 初始化状态栏项
        statusItem = NSStatusBar.system.statusItem(withLength: fixedBarWidth)
        guard let button = statusItem.button else { return }

        // 2. 预先构建并持有单一 ImageRenderer 实例
        let initialView = MenuBarStatusView(vm: viewModel)
        let renderer = ImageRenderer(content: initialView)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
        self.cachedRenderer = renderer

        renderMenuBarImage()

        // 3. 订阅数据源驱动重绘
        viewModel.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.renderMenuBarImage()
                }
            }
            .store(in: &cancellables)

        // 4. 核心优化 3：注册系统级息屏/亮屏通知，合盖与息屏时彻底暂停渲染
        setupDisplaySleepWatchers()

        button.target = self
        button.action = #selector(toggleFloatingPanel)

        // 5. 初始化详情悬浮面板
        let detailView = DetailPopoverView(vm: viewModel)
        hostingController = NSHostingController(rootView: detailView)

        floatingPanel = ModernFloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 480))
        floatingPanel.contentViewController = hostingController
    }

    /// 屏幕休眠监控：当屏幕黑屏、合盖、锁屏息屏时，不进行任何绘制
    private func setupDisplaySleepWatchers() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        
        wsCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.isDisplaySleeping = true
        }
        
        wsCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.isDisplaySleeping = false
            // 唤醒瞬间补刷最新的一帧数据
            self?.renderMenuBarImage()
        }
    }

    /// 经过极限性能调优的菜单栏图像渲染
    @MainActor
    private func renderMenuBarImage() {
        // 节能防线：屏幕未点亮时，直接跳过绘图，零 CPU / 零 GPU 消耗
        if isDisplaySleeping { return }
        
        guard let button = statusItem?.button, let renderer = cachedRenderer else { return }

        // 核心技术点：仅更新根视图模型状态，复用底层已有的 CoreGraphics 上下文
        renderer.rootView = MenuBarStatusView(vm: viewModel)

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
