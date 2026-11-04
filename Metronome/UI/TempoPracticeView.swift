import SwiftUI

struct TempoPracticeView: View {
    @ObservedObject var vm: MetronomeViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TempoPracticeConfiguration
    @State private var startText: String
    @State private var targetText: String
    @State private var incrementText: String
    @State private var barsText: String
    @FocusState private var focusedField: String?

    init(vm: MetronomeViewModel) {
        self.vm = vm
        _draft = State(initialValue: vm.settings.practice)
        _startText = State(initialValue: String(vm.settings.practice.startBPM))
        _targetText = State(initialValue: String(vm.settings.practice.targetBPM))
        _incrementText = State(initialValue: String(vm.settings.practice.increment))
        _barsText = State(initialValue: String(vm.settings.practice.barsPerStep))
    }

    private var validatedDraft: TempoPracticeConfiguration? {
        guard let start = Int(startText), let target = Int(targetText),
              let increment = Int(incrementText), let bars = Int(barsText) else { return nil }
        var result = draft
        result.startBPM = start
        result.targetBPM = target
        result.increment = increment
        result.barsPerStep = bars
        return result.isValid ? result : nil
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Text("从舒适的速度开始，按小节逐步提速。达到目标后保持播放，由你决定何时结束。")
                            .font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
                        Toggle("启用渐进提速", isOn: $draft.enabled)
                            .tint(Theme.accent)
                            .disabled(vm.isRunning)
                        VStack(spacing: 0) {
                            numberRow("起始速度", text: $startText, value: $draft.startBPM, range: BPMInput.range, suffix: "BPM")
                            Divider().overlay(Theme.stroke)
                            numberRow("目标速度", text: $targetText, value: $draft.targetBPM, range: BPMInput.range, suffix: "BPM")
                            Divider().overlay(Theme.stroke)
                            numberRow("每次增加", text: $incrementText, value: $draft.increment, range: 1...40, suffix: "BPM")
                            Divider().overlay(Theme.stroke)
                            numberRow("间隔小节", text: $barsText, value: $draft.barsPerStep, range: 1...32, suffix: "小节")
                        }
                        .padding(.horizontal, 14)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
                        .disabled(vm.isRunning)
                        if validatedDraft == nil {
                            Text("速度须在 20–400，目标不得低于起始；增量为 1–40，间隔为 1–32 小节。")
                                .font(.system(size: 12)).foregroundStyle(.orange)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(draft.startBPM) → \(draft.targetBPM) BPM")
                                .font(.system(size: 25, weight: .medium).monospacedDigit())
                                .foregroundStyle(Theme.accent)
                            Text("以 \(vm.timeSignature.unit(vm.beatCounting).symbol) 为一拍 · 每 \(draft.barsPerStep) 小节增加 \(draft.increment) BPM")
                                .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                        }
                        Text(vm.isRunning ? "请先停止播放，再修改练习方案。" : "预备拍不计入练习。每次开始都会从起始速度重练。")
                            .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                        Text("练习中可以保持当前速度、继续自动提速，或退回上一档并保持。请以弹奏准确、动作放松为前提决定是否继续。")
                            .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                        Text("练习开始后，拍号、计拍单位和细分会锁定；外观、声音与音量仍可调整。")
                            .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                    }
                    .padding(20)
                    .padding(.bottom, focusedField == nil ? 0 : 260)
                }
                .onChange(of: focusedField) { field in
                    guard let field else { return }
                    withAnimation(.easeOut(duration: 0.2)) { scroll.scrollTo(field, anchor: .top) }
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("渐进提速练习")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        focusedField = nil
                        if !vm.isRunning, let configuration = validatedDraft { vm.setPractice(configuration) }
                        dismiss()
                    }
                    .foregroundStyle(Theme.accent)
                    .disabled(!vm.isRunning && validatedDraft == nil)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起键盘") { focusedField = nil }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func numberRow(_ title: String, text: Binding<String>, value: Binding<Int>, range: ClosedRange<Int>, suffix: String) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 14)).foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
            TextField(title, text: text)
                .keyboardType(.numberPad)
                .focused($focusedField, equals: title)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 18, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.accent)
                .frame(width: 52)
                .accessibilityLabel("\(title)输入")
                .onChange(of: text.wrappedValue) { raw in
                    if let parsed = Int(raw) { value.wrappedValue = parsed }
                }
            Text(suffix).font(.system(size: 10)).foregroundStyle(Theme.textSecondary).frame(width: 26)
            Stepper(title, value: Binding(get: { value.wrappedValue }, set: { number in
                value.wrappedValue = number
                text.wrappedValue = String(number)
            }), in: range)
                .labelsHidden()
                .accessibilityLabel("\(title)步进")
                .fixedSize()
        }
        .frame(minHeight: 64)
        .id(title)
    }
}
