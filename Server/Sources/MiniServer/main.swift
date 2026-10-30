import Foundation
import AppKit

// MARK: - 全局极简日志管理器
class ServerLogger {
    static let shared = ServerLogger()
    var logs: [String] = []
    var logUpdateHandler: (() -> Void)?

    func log(_ message: String, isError: Bool = false) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timeString = formatter.string(from: Date())
        
        let prefix = isError ? "❌" : "ℹ️"
        let fullMessage = "[\(timeString)] \(prefix) \(message)"
        
        DispatchQueue.main.async {
            self.logs.append(fullMessage)
            if self.logs.count > 100 { self.logs.removeFirst() } 
            self.logUpdateHandler?()
        }
    }
}

// MARK: - AppKit 原生菜单栏与生命周期
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var webSocketService: WebSocketService?
    
    var statusMenuItem: NSMenuItem!
    var toggleMenuItem: NSMenuItem!
    
    var logWindow: NSWindow?
    var logTextView: NSTextView?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. 创建状态栏图标
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = createMiniServerIcon() // 使用极简手绘矢量服务器图标
        }

        // 2. 构建菜单
        let menu = NSMenu()
        
        statusMenuItem = NSMenuItem(title: "状态: 已停止", action: nil, keyEquivalent: "")
        menu.addItem(statusMenuItem)
        menu.addItem(NSMenuItem.separator())
        
        toggleMenuItem = NSMenuItem(title: "▶ 开启服务", action: #selector(toggleService), keyEquivalent: "s")
        menu.addItem(toggleMenuItem)
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "查看运行与错误日志...", action: #selector(showLogWindow), keyEquivalent: "l"))
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "彻底退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem.menu = menu
        
        ServerLogger.shared.logUpdateHandler = { [weak self] in
            self?.refreshLogText()
        }
        
        toggleService()
    }
    
    // 纯代码绘制精致的 16x16 服务器图标，完美适配 Catalina 黑白模式
    private func createMiniServerIcon() -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor.black.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.5
        // 画出服务器上下两个机架
        path.appendRoundedRect(NSRect(x: 2, y: 3, width: 12, height: 4), xRadius: 1, yRadius: 1)
        path.appendRoundedRect(NSRect(x: 2, y: 9, width: 12, height: 4), xRadius: 1, yRadius: 1)
        path.stroke()
        img.unlockFocus()
        img.isTemplate = true // 设为模板，系统自动根据深浅色模式反转
        return img
    }
    
    @objc func toggleService() {
        if webSocketService != nil {
            webSocketService?.stop()
            webSocketService = nil
            statusMenuItem.title = "状态: 💤 已停止 (零消耗)"
            toggleMenuItem.title = "▶ 开启监控服务"
            ServerLogger.shared.log("服务已被手动停止")
            if let button = statusItem.button { button.contentTintColor = .secondaryLabelColor }
        } else {
            do {
                webSocketService = try WebSocketService(port: 29876)
                webSocketService?.start()
                statusMenuItem.title = "状态: 🟢 运行中 (端口 29876)"
                toggleMenuItem.title = "■ 暂停监控服务"
                if let button = statusItem.button { button.contentTintColor = .systemGreen }
            } catch {
                ServerLogger.shared.log("端口 29876 绑定失败: \(error.localizedDescription)", isError: true)
                statusMenuItem.title = "状态: ❌ 启动失败"
                if let button = statusItem.button { button.contentTintColor = .systemRed }
            }
        }
    }
    
    @objc func showLogWindow() {
        if logWindow == nil {
            let winSize = NSSize(width: 500, height: 300)
            let win = NSWindow(contentRect: NSRect(origin: .zero, size: winSize),
                               styleMask: [.titled, .closable, .resizable],
                               backing: .buffered, defer: false)
            win.title = "MiniBar Server 日志"
            win.center()
            win.isReleasedWhenClosed = false
            
            let scrollView = NSScrollView()
            scrollView.hasVerticalScroller = true
            scrollView.autoresizingMask = [.width, .height]
            
            let textView = NSTextView()
            textView.isEditable = false
            textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            textView.autoresizingMask = [.width]
            
            scrollView.documentView = textView
            win.contentView = scrollView
            
            self.logWindow = win
            self.logTextView = textView
        }
        
        refreshLogText()
        logWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func refreshLogText() {
        guard let textView = logTextView else { return }
        let text = ServerLogger.shared.logs.joined(separator: "\n")
        textView.string = text
        textView.scrollToEndOfDocument(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
