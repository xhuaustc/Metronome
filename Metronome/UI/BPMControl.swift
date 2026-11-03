import SwiftUI

/// BPM 主控件：单击输入、横向拖动调节、两侧加减（支持长按连续）。
///
/// 输入态的提交有且只有一条真实路径：调用 `vm.commitBPMEditing()`。
/// 数字键盘没有回车键，所以工具栏「完成」、点击空白、以及切走焦点都必须走它，
/// 否则会出现「输了数字但不生效、之后加减也不刷新」的状态。
struct BPMControl: View {

    @ObservedObject var vm: MetronomeViewModel

    @State private var dragBase: Int?
    @FocusState private var fieldFocused: Bool

    private var isEditing: Bool { vm.bpmDraft != nil }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            HoldRepeatButton(symbol: "minus") { vm.adjustBPM(by: -1) }
                .opacity(isEditing ? 0 : 1)
                .allowsHitTesting(!isEditing)

            Spacer(minLength: 4)

            VStack(spacing: 0) {
                valueView
                    .frame(height: 104)
                Text(vm.tempoLabel)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
            }
            .frame(width: 200)

            Spacer(minLength: 4)

            HoldRepeatButton(symbol: "plus") { vm.adjustBPM(by: 1) }
                .opacity(isEditing ? 0 : 1)
                .allowsHitTesting(!isEditing)
        }
    }

    @ViewBuilder
    private var valueView: some View {
        if isEditing {
            TextField("", text: Binding(
                get: { vm.bpmDraft ?? "" },
                set: { vm.bpmDraft = $0 }
            ))
            .keyboardType(.numberPad)
            .focused($fieldFocused)
            .multilineTextAlignment(.center)
            .font(.system(size: 84, weight: .regular, design: .rounded).monospacedDigit())
            .foregroundStyle(Theme.textPrimary)
            .tint(Theme.accent)
            .onAppear {
                // 进入输入态立刻弹键盘，不需要用户再点一次。
                fieldFocused = true
            }
            .onSubmit { vm.commitBPMEditing() }
        } else {
            Text("\(vm.bpm)")
                .font(.system(size: 92, weight: .regular, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { vm.beginBPMEditing() }
                .gesture(dragGesture)
                .accessibilityLabel("速度 \(vm.bpm)")
                .accessibilityHint("单击输入，左右拖动调节")
        }
    }

    /// 前 40pt 一比一，之后减速为二比一，便于在 30–240 的长量程上做精细定位。
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if dragBase == nil { dragBase = vm.bpm }
                guard let base = dragBase else { return }
                let width = value.translation.width
                let sign: Double = width >= 0 ? 1 : -1
                let magnitude = abs(width)
                let delta = sign * (magnitude <= 40 ? magnitude : 40 + (magnitude - 40) / 2)
                vm.setBPM(base + Int(delta.rounded()))
            }
            .onEnded { _ in dragBase = nil }
    }
}

/// 按下立即执行一次，停住 0.38s 后进入约 18 次/秒的连续步进。
struct HoldRepeatButton: View {

    let symbol: String
    let action: () -> Void

    @State private var repeatTask: Task<Void, Never>?
    @State private var pressing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(pressing ? Theme.surface : Color.clear)
                .overlay(Circle().stroke(Theme.stroke, lineWidth: 0.5))
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(width: 58, height: 58)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in begin() }
                .onEnded { _ in end() }
        )
    }

    private func begin() {
        guard !pressing else { return }
        pressing = true
        action()
        repeatTask = Task {
            try? await Task.sleep(nanoseconds: 380_000_000)
            while !Task.isCancelled {
                action()
                try? await Task.sleep(nanoseconds: 55_000_000)
            }
        }
    }

    private func end() {
        pressing = false
        repeatTask?.cancel()
        repeatTask = nil
    }
}
