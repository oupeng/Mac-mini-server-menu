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

    private let fixedBarWidth: CGFloat = 275.0

    private var floatingPanel: ModernFloatingPanel!
    private var hostingController: NSHostingController<DetailPopoverView>!
    private var outsideClickMonitor: Any?

    private var isDisplaySleeping: Bool = false

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

        setupDisplaySleepWatchers()

        button.target = self
        button.action = #selector(toggleFloatingPanel)

        let detailView = DetailPopoverView(vm: viewModel)
        hostingController = NSHostingController(rootView: detailView)

        floatingPanel = ModernFloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 480))
        floatingPanel.contentViewController = hostingController
    }

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

        let currentScreen = win.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let targetX = barScreenRect.midX - (panelWidth / 2.0)
        let safeX = max(currentScreen.visibleFrame.minX + 10.0, min(currentScreen.visibleFrame.maxX - panelWidth - 10.0, targetX))
        
        // 底部防裁切保护：若笔记本小屏高度紧凑，确保面板底端不被 Dock/屏幕底边挡住
        let rawY = barScreenRect.minY - panelHeight - 6.0
        let safeY = max(currentScreen.visibleFrame.minY + 10.0, rawY)

        floatingPanel.setFrame(NSRect(x: safeX, y: safeY, width: panelWidth, height: panelHeight), display: true)
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
