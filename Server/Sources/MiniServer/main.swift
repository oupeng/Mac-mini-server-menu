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
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
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
        
        // 初始状态默认为运行中
        updateStatusItemUI(running: true)
        startServiceInternal()
    }
    
    // 核心绘制：Mac mini 正面极简轮廓 + 真实电源指示灯
    private func createMacMiniStatusIcon(running: Bool) -> NSImage {
        let size = NSSize(width: 22, height: 16)
        let img = NSImage(size: size)
        img.lockFocus()
        
        // 1. 绘制 Mac mini 铝合金正面机身圆角框 (比例对齐 2012 款前脸)
        let bodyRect = NSRect(x: 2.0, y: 4.5, width: 18.0, height: 7.0)
        let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: 1.8, yRadius: 1.8)
        bodyPath.lineWidth = 1.3
        NSColor.black.setStroke()
        bodyPath.stroke()
        
        // 2. 绘制左侧红外接收器黑斑 (IR Sensor)
        let irRect = NSRect(x: 4.8, y: 7.0, width: 2.0, height: 2.0)
        let irPath = NSBezierPath(ovalIn: irRect)
        NSColor.black.withAlphaComponent(0.4).setFill()
        irPath.fill()
        
        // 3. 绘制右侧电源指示灯 (Power LED)
        let ledRect = NSRect(x: 16.0, y: 7.0, width: 1.8, height: 1.8)
        let ledPath = NSBezierPath(ovalIn: ledRect)
        
        if running {
            // 运行状态：点亮指示灯 (微型实体圆点 + 柔光光晕)
            NSColor.black.setFill()
            ledPath.fill()
            
            // 外圈微弱光晕
            let glowRect = NSRect(x: 15.1, y: 6.1, width: 3.6, height: 3.6)
            let glowPath = NSBezierPath(ovalIn: glowRect)
            NSColor.black.withAlphaComponent(0.25).setFill()
            glowPath.fill()
        } else {
            // 未启动状态：指示灯熄灭 (与机身平齐，仅留微弱凹痕或不画)
            NSColor.black.withAlphaComponent(0.2).setStroke()
            ledPath.lineWidth = 0.5
            ledPath.stroke()
        }
        
        img.unlockFocus()
        img.isTemplate = true // 关键：跟随系统外观自动变为黑/白，彻底清除刺眼绿色！
        return img
    }
    
    private func updateStatusItemUI(running: Bool) {
        if let button = statusItem.button {
            button.contentTintColor = nil // 清空任何色彩污染，完美融入系统栏
            button.image = createMacMiniStatusIcon(running: running)
        }
    }
    
    @objc func toggleService() {
        if webSocketService != nil {
            webSocketService?.stop()
            webSocketService = nil
            statusMenuItem.title = "状态: 💤 已停止 (指示灯已熄灭)"
            toggleMenuItem.title = "▶ 开启监控服务"
            updateStatusItemUI(running: false)
            ServerLogger.shared.log("服务已被手动暂停")
        } else {
            startServiceInternal()
        }
    }
    
    private func startServiceInternal() {
        do {
            webSocketService = try WebSocketService(port: 29876)
            webSocketService?.start()
            statusMenuItem.title = "状态: 🟢 运行中 (端口 29876)"
            toggleMenuItem.title = "■ 暂停监控服务"
            updateStatusItemUI(running: true)
        } catch {
            ServerLogger.shared.log("端口 29876 绑定失败: \(error.localizedDescription)", isError: true)
            statusMenuItem.title = "状态: ❌ 启动失败"
            updateStatusItemUI(running: false)
        }
    }
    
    @objc func showLogWindow() {
        if logWindow == nil {
            let winSize = NSSize(width: 520, height: 320)
            let win = NSWindow(contentRect: NSRect(origin: .zero, size: winSize),
                               styleMask: [.titled, .closable, .resizable],
                               backing: .buffered, defer: false)
            win.title = "MiniBar Server 运行与错误日志"
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
