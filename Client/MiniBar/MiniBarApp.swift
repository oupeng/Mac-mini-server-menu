@objc func togglePopover() {
        guard let button = statusItem.button else {
            print("[MiniBar 诊断] ❌ 失败: statusItem.button 为空！")
            return
        }

        print("===================== [MiniBar 诊断开始] =====================")
        // 1. 检查鼠标绝对物理位置
        let mouseLoc = NSEvent.mouseLocation
        print("[诊断 1] 鼠标屏幕绝对坐标: X = \(mouseLoc.x), Y = \(mouseLoc.y)")

        // 2. 检查当前主屏幕尺寸与边界
        if let screen = NSScreen.main {
            print("[诊断 2] 主屏幕 Frame: \(screen.frame), 菜单栏高度推算: \(screen.frame.maxY)")
        }

        // 3. 检查 statusItem.button 的内部 bounds
        print("[诊断 3] button.bounds: \(button.bounds)")

        // 4. 检查 button 所在系统窗口的真实位置与层级
        if let win = button.window {
            print("[诊断 4] button.window Frame: \(win.frame)")
            print("[诊断 5] button 转换到屏幕的绝对 Rect: \(win.convertToScreen(button.bounds))")
        } else {
            print("[诊断 4/5] ⚠️ button.window 不存在！")
        }

        if popover.isShown {
            print("[诊断 6] Popover 当前为打开状态，执行关闭")
            popover.performClose(nil)
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        
        // 执行弹出
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        
        // 5. 检查弹出后，Popover 窗口最终被系统放置在了哪里
        if let popoverWindow = popover.contentViewController?.view.window {
            print("[诊断 7] 💥 Popover 最终生成的窗口真实 Frame: \(popoverWindow.frame)")
        }
        print("===================== [MiniBar 诊断结束] =====================\n")

        popover.contentViewController?.view.window?.makeKey()
    }
