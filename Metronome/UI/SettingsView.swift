import SwiftUI

struct SettingsView: View {

    @ObservedObject var vm: MetronomeViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showPractice = false

    private let accent = Theme.accent

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    practiceSection
                    themeSection
                    soundSection.id("sound-options")
                    volumeSection
                    playbackSection
                    speedSection
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .onAppear {
                #if DEBUG
                if ScreenshotMode.isActive && ScreenshotMode.showsSounds {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        scroll.scrollTo("sound-options", anchor: .top)
                    }
                }
                #endif
            }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(accent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showPractice) { TempoPracticeView(vm: vm) }
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            caption("节拍器外观")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(MetronomeAppearance.allCases) { appearance in
                    let selected = vm.appearance == appearance
                    Button { vm.setTheme(appearance) } label: {
                        VStack(spacing: 7) {
                            MetronomeInstrument(appearance: appearance, bpm: 96, angle: -12)
                                .frame(width: 280, height: 360)
                                .scaleEffect(0.34)
                                .frame(width: 100, height: 126)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                            HStack(spacing: 5) {
                                Text(appearance.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(1).minimumScaleFactor(0.8)
                                if selected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 13))
                                        .foregroundStyle(accent)
                                }
                            }
                            .foregroundStyle(Theme.textPrimary)
                            Text(appearance.subtitle)
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 8)
                        .background(RoundedRectangle(cornerRadius: 16).fill(selected ? accent.opacity(0.09) : Theme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? accent : Theme.stroke, lineWidth: selected ? 1.5 : 1))
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityLabel(appearance.title + "，" + appearance.subtitle)
                    .accessibilityValue(selected ? "已选择" : "未选择")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private var practiceSection: some View {
        Button { showPractice = true } label: {
            HStack {
                Label("渐进提速练习", systemImage: "chart.line.uptrend.xyaxis")
                Spacer()
                Text(vm.settings.practice.enabled ? "\(vm.settings.practice.startBPM) → \(vm.settings.practice.targetBPM)" : "未启用")
                    .font(.system(size: 12).monospacedDigit())
                Image(systemName: "chevron.right").font(.system(size: 11))
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Theme.accent)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
        }
        .buttonStyle(.plain)
    }

    private var soundSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            caption("节拍声音 · 独立于外观")
            ForEach(Timbre.allCases, id: \.self) { sound in
                HStack(spacing: 8) {
                    Button { vm.setSound(sound) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: vm.sound == sound ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(vm.sound == sound ? Theme.accent : Theme.textTertiary)
                            Text(sound.displayName).font(.system(size: 14))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("选择\(sound.displayName)")
                    .accessibilityValue(vm.sound == sound ? "已选择" : "未选择")
                    .accessibilityAddTraits(vm.sound == sound ? .isSelected : [])
                    Button { vm.previewSound(sound) } label: {
                        Image(systemName: "speaker.wave.2")
                            .foregroundStyle(Theme.accent)
                            .frame(width: 44, height: 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.isRunning)
                    .accessibilityLabel("试听\(sound.displayName)")
                }
                .padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
            }
            Text(vm.isRunning ? "播放中切换声音会随后续节拍生效；停止后可单独试听。" : "点选声音后，可用右侧按钮试听。切换外观不会改变声音。")
                .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
        }
    }

    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            caption("音量")
            HStack(spacing: 12) {
                Image(systemName: vm.volume < 0.01 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                Slider(value: Binding(get: { vm.volume }, set: { vm.setVolume($0) }), in: 0...1)
                    .tint(accent)
                    .accessibilityLabel("音量")
                    .accessibilityValue("\(Int((vm.volume * 100).rounded()))%")
                Text("\(Int((vm.volume * 100).rounded()))%")
                    .font(.system(size: 13, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 42, alignment: .trailing)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 58)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
        }
    }

    private var playbackSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            caption("播放")
            VStack(spacing: 0) {
                toggleRow("重音", isOn: Binding(get: { vm.accentEnabled },
                                               set: { vm.setAccentEnabled($0) }))
                    .disabled(vm.isPracticeRunning)
                Divider().overlay(Theme.stroke)
                toggleRow("开始前给一小节预备拍", isOn: Binding(get: { vm.countInEnabled },
                                                               set: { vm.setCountInEnabled($0) }))
                Divider().overlay(Theme.stroke)
                toggleRow("练习时屏幕常亮", isOn: Binding(get: { vm.keepAwake },
                                                        set: { vm.setKeepAwake($0) }))
            }
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
        }
    }

    private var speedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            caption("当前速度")
            VStack(alignment: .leading, spacing: 4) {
                Text(vm.tempoLabel)
                    .font(.system(size: 17, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                if let hint = vm.dottedHint {
                    Text("对照谱面标记：\(hint)")
                        .font(.system(size: 13, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Text("以 \(vm.timeSignature.unit(vm.beatCounting).symbol) 为一拍 · 20–400 BPM")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
        }
    }

    private var footer: some View {
        Text("无账号 · 不联网 · 不收集任何数据\n所有设置仅保存在本机")
            .font(.system(size: 12))
            .foregroundStyle(Theme.textTertiary)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tint(accent)
        .frame(minHeight: 54)
    }
}
