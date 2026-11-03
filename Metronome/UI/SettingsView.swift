import SwiftUI

struct SettingsView: View {

    @ObservedObject var vm: MetronomeViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    timbreSection
                    playbackSection
                    speedSection
                    footer
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var timbreSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            caption("音色")
            VStack(spacing: 6) {
                ForEach(Timbre.allCases) { timbre in
                    Button {
                        vm.setTimbre(timbre)
                    } label: {
                        HStack {
                            Text(timbre.displayName)
                                .font(.system(size: 15))
                            Spacer()
                            if vm.timbre == timbre {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(vm.timbre == timbre ? Theme.surface : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(Theme.stroke, lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var playbackSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            caption("播放")
            VStack(spacing: 0) {
                toggleRow("开始前给一小节预备拍",
                          isOn: Binding(get: { vm.countInEnabled },
                                        set: { vm.setCountInEnabled($0) }))
                Divider().overlay(Theme.stroke)
                toggleRow("练习时屏幕常亮",
                          isOn: Binding(get: { vm.keepAwake },
                                        set: { vm.setKeepAwake($0) }))
            }
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.surface))
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
                    Text("BPM 恒指四拍子中的四分音符")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.surface))
        }
    }

    private var footer: some View {
        Text("无账号 · 不联网 · 不收集任何数据\n所有设置仅保存在本机")
            .font(.system(size: 12))
            .foregroundStyle(Theme.textTertiary)
            .lineSpacing(4)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.textTertiary)
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Theme.accent)
        }
        .frame(height: 54)
    }
}
