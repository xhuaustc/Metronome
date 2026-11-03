# 钢琴练习节拍器 · iOS

打开即用、节拍稳定、看得清听得懂的单功能节拍器。无账号、不联网、不收集数据。

需求与交互规范见 [PRD.md](PRD.md)。

---

## 快速开始

```bash
open PianoMetronome.xcodeproj      # Xcode 直接运行
```

或命令行构建到模拟器：

```bash
xcodebuild -project PianoMetronome.xcodeproj \
           -scheme PianoMetronome \
           -sdk iphonesimulator \
           -destination 'generic/platform=iOS Simulator' \
           build CODE_SIGNING_ALLOWED=NO
```

仅验证核心节拍数学（不依赖 Xcode 工程，秒级完成）：

```bash
swift test
```

若在受限环境里报 `sandbox-exec: sandbox_apply: Operation not permitted`，SwiftPM 的内部沙箱被外层拦截，改用：

```bash
swift test --disable-sandbox
```

真机运行需在 Xcode 里选择自己的开发者团队（`Signing & Capabilities`），Bundle ID 当前为 `com.mpan.pianometronome`。

---

## 目录结构

```
Metronome/
├── Core/                     纯 Swift，无 UI / 无音频依赖，可被 swift test 直接验证
│   ├── TimeSignature.swift     拍号语义、分组、三级重音
│   ├── Subdivision.swift       细分档位、声点、播放位置快照
│   ├── SchedulePlanner.swift   ★ 调度器：把参数翻译成绝对采样帧
│   ├── BPMInput.swift          输入解析与夹紧
│   ├── MetronomeSettings.swift 持久化模型
│   └── Timbre.swift            音色声学参数
├── Audio/
│   ├── SoundBank.swift         预渲染全部音色变体（合成，无音频素材文件）
│   └── MetronomeEngine.swift   ★ AVAudioEngine + 前瞻调度 + 中断处理
├── UI/
│   ├── MetronomeView.swift     主界面
│   ├── BPMControl.swift        BPM 输入 / 拖动 / 长按加减
│   ├── BeatTrackView.swift     拍点与拍序
│   ├── SettingsView.swift      低频设置
│   ├── MetronomeViewModel.swift
│   └── Theme.swift
├── App/PianoMetronomeApp.swift
└── Resources/Assets.xcassets

Support/Info.plist             （放在代码目录外，避免被同步文件夹当资源复制）
Tests/                         SchedulePlannerTests + BPMInputTests
```

---

## 两条不能破坏的规则

**1. 时间只有一个来源：采样帧。**

`SchedulePlanner` 用 `anchorFrame + n × framesPerBeat` 一次乘法得出每一拍，不做累加，所以不存在浮点累积漂移。调度层每 100ms 把未来 1.0s 的拍点排进播放器；界面用 `CADisplayLink`/`TimelineView` 读播放头只读投影，永远不会反向驱动音频。

已验证：120 BPM 连跑 30 分钟共 3600 拍，最大偏差 < 1e-6 帧。

**2. 已排入的拍绝不重算。**

改 BPM 和音色在下一拍生效；改拍号、细分、重音在下一小节生效。因为已调度的 buffer 不动，"补响"和"叠音"在结构上不可能发生。

---

## 当前状态

| 项 | 状态 |
|---|---|
| 20 个单元测试 | 通过 |
| iOS 模拟器构建 | 通过，无警告 |
| 模拟器运行 | 通过 |
| 真机 / 实机音频验证 | 未做（需在真机上验证中断与延迟） |
| AppIcon | 占位，未设计 |
| UI 自动化测试 | 未做 |

未经真机验证的部分，主要是来电中断、拔耳机路由切换、后台播放这三项——模拟器无法真实模拟。

---

## 实现与 PRD 的偏差

- **路由切换**：PRD 要求淡出 120ms 后重建音频图继续播放。当前实现为"系统无缝接管，仅在引擎真的停止时复位到第一拍"。更保守，不会爆音，但极端情况下会断拍。
- **6/8 的 BPM 基准**：已确认按拍单位（♪）计，`♩.` 等价速度在设置面板显示。基准切换留到 V1.1。
