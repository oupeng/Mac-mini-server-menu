import SwiftUI

@main
struct MiniBarApp: App {
    @StateObject private var viewModel = MonitorViewModel()

    var body: some Scene {
        MenuBarExtra {
            DetailPopoverView(vm: viewModel)
        } label: {
            MenuBarStatusView(vm: viewModel)
        }
        .menuBarExtraStyle(.window) // 采用 macOS 现代悬浮 Window 样式
    }
}
