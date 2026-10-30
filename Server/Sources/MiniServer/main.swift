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
            if self.logs.count > 100 { self.logs.removeFirst() } // 最多保留100条防止内存溢出
            self.logUpdateHandler?()
            print(fullMessage) // 调试保留
        }
    }
}

// MARK: - AppKit 原生菜单栏与生命周期
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var webSocketService: WebSocketService?
    
    // 菜单项引用
    var statusMenuItem: NSMenuItem!
    var toggleMenuItem: NSMenuItem!
    
    // 错误日志窗口
    var logWindow: NSWindow?
    var logTextView: NSTextView?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. 创建状态栏图标
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(named: NSImage.networkName) // 使用系统原生网络小图标
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
        
        // 3. 绑定日志更新 UI
        ServerLogger.shared.logUpdateHandler = { [weak self] in
            self?.refreshLogText()
        }
        
        // 4. 默认启动服务
        toggleService()
    }
    
    @objc func toggleService() {
        if webSocketService != nil {
            // 当前在运行，执行停止
            webSocketService?.stop()
            webSocketService = nil
            statusMenuItem.title = "状态: 💤 已停止 (零消耗)"
            toggleMenuItem.title = "▶ 开启监控服务"
            ServerLogger.shared.log("服务已被手动停止")
            if let button = statusItem.button { button.contentTintColor = .secondaryLabelColor }
        } else {
            // 当前已停止，执行开启
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

// 纯原生入口
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // 声明为纯菜单栏常驻应用
app.run()
