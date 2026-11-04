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

    static var showsFavorites: Bool {
        ProcessInfo.processInfo.arguments.contains("-screenshotFavorites")
    }

    static var showsSettings: Bool {
        ProcessInfo.processInfo.arguments.contains("-screenshotSettings")
    }

    static var showsPracticeSettings: Bool { ProcessInfo.processInfo.arguments.contains("-screenshotPracticeSettings") }
    static var showsMeter: Bool { ProcessInfo.processInfo.arguments.contains("-screenshotMeter") }
    static var showsSounds: Bool { ProcessInfo.processInfo.arguments.contains("-screenshotSounds") }

    /// 专用截图模拟器中调用；使用真实配置和播放流程准备展示状态。
    @MainActor
    static func apply(to vm: MetronomeViewModel) {
        guard isActive else { return }

        vm.setPractice(TempoPracticeConfiguration())
        vm.setTheme(.icon)
        vm.setSound(.crystalTick)
        vm.setTimeSignature(.fourFour)
        vm.setSubdivision(.none)
        vm.setBPM(96)
        vm.setCountInEnabled(false)
        if showsMeter {
            vm.setTimeSignature(.twelveEight)
            vm.setSubdivision(.three)
        }
        if showsFavorites, vm.favorites.items.isEmpty {
            for bpm in [60, 96, 120] {
                vm.setBPM(bpm)
                vm.saveFavorite()
            }
            vm.setBPM(96)
        }
        if showsPracticeSettings || ProcessInfo.processInfo.arguments.contains("-screenshotPractice") {
            var practice = TempoPracticeConfiguration()
            practice.enabled = true
            vm.setPractice(practice)
            if !showsPracticeSettings { vm.start() }
        }

        if isPlaying {
            vm.setSubdivision(.two)
            vm.togglePlayback()
        }
    }
}

#endif
