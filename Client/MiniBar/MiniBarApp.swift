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

    // 2 倍图表宽度后的固定物理宽度（永久锁死绝不抖动）
    private let fixedBarWidth: CGFloat = 250.0

    // 专用于精准定位的绝对屏幕锚点窗口（彻底解决 ControlCenter 虚拟化导致的 X=0 左移 Bug）
    private var anchorWindow: NSWindow?

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

    /// 核心修复：基于真实物理鼠标点击点锚定弹窗，终结任何系统级错位！
    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        
        if popover.isShown {
            popover.performClose(nil)
            return
        }

        // 1. 激活 App 前台权限
        NSApp.activate(ignoringOtherApps: true)

        // 2. 获取用户点击时的全局绝对物理屏幕坐标 (Global Screen Point)
        let mouseLoc = NSEvent.mouseLocation
        
        // 获取当前屏幕的菜单栏底部高度
        let currentScreen = NSScreen.screens.first(where: { NSPointInRect(mouseLoc, $0.frame) }) ?? NSScreen.main ?? NSScreen.screens[0]
        let menuBarBottomY = currentScreen.frame.maxY - 24.0

        // 3. 构建精准物理锚点 (以用户点击的 X 坐标为中心，紧贴菜单栏底边缘)
        let anchorRect = NSRect(x: mouseLoc.x - 1, y: menuBarBottomY, width: 2, height: 2)

        if anchorWindow == nil {
            let win = NSWindow(contentRect: anchorRect, styleMask: .borderless, backing: .buffered, defer: false)
            win.isOpaque = false
            win.backgroundColor = .clear
            win.level = .statusBar
            win.ignoresMouseEvents = true
            anchorWindow = win
        } else {
            anchorWindow?.setFrame(anchorRect, display: false)
        }

        guard let anchorWin = anchorWindow, let anchorView = anchorWin.contentView else { return }
        anchorWin.orderFront(nil)

        // 4. 将 Popover 精确锚定在真实的物理点击位置，小三角必定正对点击处！
        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
        
        // 5. 成为焦点窗口，点击外部自动收起
        popover.contentViewController?.view.window?.makeKey()
    }
}
