import Foundation

#if DEBUG

/// 仅用于生成 App Store 截图。
///
/// 模拟器没有点击注入能力，无法脚本化按下播放键，因此用启动参数直接摆出
/// 一个可信的界面状态。整段代码包在 `#if DEBUG` 里，Release 构建不参与编译，
/// 上架的二进制里不存在这些分支。
enum ScreenshotMode {

    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains("-screenshotMode")
    }

    static var isPlaying: Bool {
        ProcessInfo.processInfo.arguments.contains("-screenshotPlaying")
    }

    static var showsSettings: Bool {
        ProcessInfo.processInfo.arguments.contains("-screenshotSettings")
    }

    /// 在主界面出现时调用。只影响展示状态，不改任何持久化设置。
    @MainActor
    static func apply(to vm: MetronomeViewModel) {
        guard isActive else { return }

        // 预备拍会盖住拍号数字，截图里不想要它。
        vm.setCountInEnabled(false)

        if isPlaying {
            vm.setSubdivision(.two)
            vm.togglePlayback()
        }
    }
}

#endif
