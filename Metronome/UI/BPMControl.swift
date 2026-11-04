import SwiftUI

/// 机械摆杆只读取音频播放位置，拖动配重通过 ViewModel 调速。
struct BPMControl: View {
    @ObservedObject var vm: MetronomeViewModel
    var compact = false
    var instrumentHeight: CGFloat = 340
    @FocusState private var fieldFocused: Bool
    @AppStorage("com.pianometronome.didSwipeTheme") private var didSwipeTheme = false
    @State private var instrumentDragDirection: InstrumentDragDirection?
    @State private var themeSlideForward = true

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 24) {
                HoldRepeatButton(symbol: "minus") { vm.adjustBPM(by: -1) }
                    .disabled(vm.isPracticeRunning || vm.bpmDraft != nil || vm.bpm == BPMInput.range.lowerBound)
                VStack(spacing: 0) {
                    if vm.bpmDraft != nil {
                        TextField("速度", text: Binding(get: { vm.bpmDraft ?? "" }, set: { vm.bpmDraft = $0 }))
                            .keyboardType(.numberPad)
                            .focused($fieldFocused)
                            .multilineTextAlignment(.center)
                            .onAppear { fieldFocused = true }
                            .onSubmit { vm.commitBPMEditing() }
                    } else {
                        Button("\(vm.bpm)") { vm.beginBPMEditing() }
                            .disabled(vm.isPracticeRunning)
                            .buttonStyle(PressableButtonStyle())
                            .accessibilityLabel("速度，\(vm.bpm) BPM，\(vm.isPracticeRunning ? "练习自动调速" : "轻点输入")")
                    }
                }
                .font(.system(size: 52, weight: .light, design: .serif).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 120, height: 58)
                HoldRepeatButton(symbol: "plus") { vm.adjustBPM(by: 1) }
                    .disabled(vm.isPracticeRunning || vm.bpmDraft != nil || vm.bpm == BPMInput.range.upperBound)
            }
            Text("\(vm.tempoLabel)  ·  BPM")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.accent)

            // 机身切换在 TimelineView 外，避免采样时钟刷新覆盖切换动画的 transaction。
            ZStack {
                TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !vm.isRunning)) { _ in
                    let position = vm.isRunning ? vm.engine.position() : nil
                    let angle = position?.pendulumAngle() ?? 0
                    MetronomeInstrument(appearance: vm.appearance, bpm: vm.bpm, angle: angle,
                                        allowsBPMEditing: !vm.isPracticeRunning,
                                        onDragBegan: { vm.commitBPMEditing(); return vm.bpm },
                                        onBPMChange: { vm.setBPM($0) })
                }
                .id(vm.appearance)
                .transition(.asymmetric(
                    insertion: .move(edge: themeSlideForward ? .trailing : .leading),
                    removal: .move(edge: themeSlideForward ? .leading : .trailing)))
            }
            .frame(height: instrumentHeight)
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance: 8)
                .onChanged { value in
                    if instrumentDragDirection == nil {
                        instrumentDragDirection = InstrumentDragDirection.classify(value.translation)
                    }
                }
                .onEnded { value in
                    defer { instrumentDragDirection = nil }
                    guard instrumentDragDirection == .horizontal,
                          abs(value.translation.width) >= 44 else { return }
                    switchTheme(forward: value.translation.width < 0)
                })
            .accessibilityAction(named: "下一个主题") { switchTheme(forward: true) }
            .accessibilityAction(named: "上一个主题") { switchTheme(forward: false) }
            Text(vm.isPracticeRunning ? "练习中自动调速 · 左右滑动换外观" : didSwipeTheme ? "上下拖动摆杆配重 · 上慢下快" : "左右滑动换外观 · 上下拖动配重调速")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 3)
        }
        .onChange(of: fieldFocused) { focused in
            if !focused { vm.commitBPMEditing() }
        }
    }

    private func switchTheme(forward: Bool) {
        vm.commitBPMEditing()
        let themes = MetronomeAppearance.allCases
        guard let index = themes.firstIndex(of: vm.appearance) else { return }
        themeSlideForward = forward
        withAnimation(.easeInOut(duration: 0.3)) {
            vm.setTheme(themes[(index + (forward ? 1 : themes.count - 1)) % themes.count])
        }
        didSwipeTheme = true
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

/// 确认主方向后锁定到手势结束，斜向微动不触发切换或调速。
private enum InstrumentDragDirection {
    case horizontal, vertical

    static func classify(_ translation: CGSize) -> Self? {
        let x = abs(translation.width)
        let y = abs(translation.height)
        if x >= 8, x > y * 1.5 { return .horizontal }
        if y >= 8, y > x * 1.5 { return .vertical }
        return nil
    }
}

/// 主页与设置共用同一实体绘制，缩略图保持材质和造型一致。
struct MetronomeInstrument: View {
    let appearance: MetronomeAppearance
    let bpm: Int
    var angle: Double = 0
    var allowsBPMEditing = true
    var onDragBegan: () -> Int? = { nil }
    var onBPMChange: (Int) -> Void = { _ in }
    @State private var dragBase: Int?
    @State private var weightDragDirection: InstrumentDragDirection?

    private var palette: InstrumentPalette { InstrumentPalette(appearance) }
    private var caseShape: MetronomeCase {
        MetronomeCase(topInset: palette.topInset, cornerRadius: palette.cornerRadius)
    }

    var body: some View {
        GeometryReader { proxy in
            let h = proxy.size.height
            let w = min(proxy.size.width - 40, h * 0.68)
            let detailScale = min(w / 217.6, 1)
            // 按可用宽度轻微收敛极窄视图的摆幅，保证摆杆完整留在画面内。
            let maximumAngle = asin(min(max((proxy.size.width / 2 - 12) / (h * 0.77), 0), 1)) * 180 / .pi
            let swingScale = min(1, maximumAngle / PlaybackPosition.pendulumAmplitude)
            let travel = h * 0.49
            let weightY = h * 0.22 + CGFloat(bpm - BPMInput.range.lowerBound) / CGFloat(BPMInput.range.upperBound - BPMInput.range.lowerBound) * travel
            ZStack {
                Ellipse().fill(.black.opacity(0.5))
                    .frame(width: w * 1.18, height: 22)
                    .blur(radius: 12).offset(y: h / 2 - 6)
                caseShape
                    .fill(LinearGradient(colors: palette.body, startPoint: .leading, endPoint: .trailing))
                    .overlay {
                        Canvas { context, size in
                            context.clip(to: caseShape.path(in: CGRect(origin: .zero, size: size)))
                            for line in 0..<(palette.woodGrain ? 65 : 0) {
                                let x = CGFloat(line) / 64 * size.width
                                var path = Path()
                                path.move(to: CGPoint(x: x, y: 0))
                                path.addCurve(to: CGPoint(x: x + 9, y: size.height), control1: CGPoint(x: x - 12, y: size.height * 0.35), control2: CGPoint(x: x + 17, y: size.height * 0.72))
                                context.stroke(path, with: .color(line.isMultiple(of: 3) ? .black.opacity(0.14) : .white.opacity(0.045)), lineWidth: line.isMultiple(of: 3) ? 2 : 1)
                            }
                        }
                    }
                    .overlay(caseShape.stroke(palette.trim.opacity(0.85), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.5), radius: 12, x: 6, y: 10)
                    .frame(width: w, height: h * 0.93)
                    .position(x: proxy.size.width / 2, y: h * 0.48)

                // 内嵌盘面的数值由上至下递增。
                MetronomeCase(topInset: 0.25, cornerRadius: palette.cornerRadius * 0.7)
                    .fill(LinearGradient(colors: palette.face, startPoint: .leading, endPoint: .trailing))
                    .overlay(MetronomeCase(topInset: 0.25, cornerRadius: palette.cornerRadius * 0.7).stroke(.black.opacity(0.5), lineWidth: 2))
                    .overlay(DialEngraving(palette: palette))
                    .frame(width: w * 0.84, height: h * 0.68)
                    .position(x: proxy.size.width / 2, y: h * 0.43)
                // 仅保留四个参考速度，避开配重与摆杆的静止位置。
                ForEach([20, 100, 200, 400], id: \.self) { value in
                    let y = h * 0.22 + CGFloat(value - BPMInput.range.lowerBound) / CGFloat(BPMInput.range.upperBound - BPMInput.range.lowerBound) * travel
                    Text("\(value)")
                        .font(.system(size: 13 * detailScale, weight: .bold, design: .rounded).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(palette.ink)
                        .frame(width: 28 * detailScale, alignment: .leading)
                        .position(x: proxy.size.width / 2 + 36 * detailScale, y: y)
                        .accessibilityHidden(true)
                }
                Capsule()
                    .fill(.black.opacity(palette.darkFace ? 0.4 : 0.12))
                    .frame(width: 12 * detailScale, height: h * 0.69)
                    .position(x: proxy.size.width / 2, y: h * 0.46)
                ZStack(alignment: .top) {
                    Capsule()
                        .fill(LinearGradient(colors: palette.rod, startPoint: .leading, endPoint: .trailing))
                        .frame(width: 7 * detailScale, height: h * 0.77)
                        .offset(y: h * 0.07)
                        .shadow(color: .black.opacity(0.5), radius: 2, x: 3, y: 2)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(LinearGradient(colors: palette.weight, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(palette.trim, lineWidth: 1))
                        .overlay {
                            VStack(spacing: 5 * detailScale) {
                                Capsule().fill(.black.opacity(0.28)).frame(width: 20 * detailScale, height: 1)
                                Capsule().fill(.white.opacity(0.45)).frame(width: 20 * detailScale, height: 1)
                                Capsule().fill(.black.opacity(0.28)).frame(width: 20 * detailScale, height: 1)
                            }
                        }
                        .frame(width: 42 * detailScale, height: 32 * detailScale)
                        .shadow(color: .black.opacity(0.5), radius: 3, x: 2, y: 4)
                        .frame(width: 64, height: 48)
                        .contentShape(Rectangle())
                        .offset(y: weightY - 24)
                        .gesture(DragGesture(minimumDistance: 8, coordinateSpace: .named("instrument"))
                            .onChanged { value in
                                guard allowsBPMEditing else { return }
                                if weightDragDirection == nil {
                                    weightDragDirection = InstrumentDragDirection.classify(value.translation)
                                }
                                guard weightDragDirection == .vertical, travel > 0 else { return }
                                if dragBase == nil { dragBase = onDragBegan() ?? bpm }
                                guard let base = dragBase else { return }
                                onBPMChange(BPMInput.clamp(base + Int((value.translation.height / travel * Double(BPMInput.range.upperBound - BPMInput.range.lowerBound)).rounded())))
                            }
                            .onEnded { _ in
                                dragBase = nil
                                weightDragDirection = nil
                            })
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("摆杆配重，速度")
                        .accessibilityValue("\(bpm) BPM")
                        .accessibilityHint(allowsBPMEditing ? "向上减速，向下加速" : "渐进提速练习中，速度由方案控制")
                        .accessibilityAdjustableAction { direction in
                            guard allowsBPMEditing else { return }
                            switch direction {
                            case .increment: onBPMChange(BPMInput.clamp(bpm + 1))
                            case .decrement: onBPMChange(BPMInput.clamp(bpm - 1))
                            @unknown default: break
                            }
                        }
                }
                .frame(width: proxy.size.width, height: h, alignment: .top)
                .rotationEffect(.degrees(dragBase == nil ? angle * swingScale : 0), anchor: UnitPoint(x: 0.5, y: 0.84))
                .animation(nil, value: angle)
                Circle()
                    .fill(LinearGradient(colors: [palette.metal, palette.metal.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                    .overlay(Circle().stroke(palette.trim.opacity(0.65), lineWidth: 2))
                    .overlay(Circle().fill(palette.face[0]).padding(8))
                    .frame(width: 25, height: 25)
                    .position(x: proxy.size.width / 2, y: h * 0.84)
                if !palette.woodGrain {
                    ForEach([-1.0, 1.0], id: \.self) { side in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(hex: 0x15191D))
                            .frame(width: w * 0.15, height: h * 0.045)
                            .position(x: proxy.size.width / 2 + side * w * 0.32, y: h * 0.967)
                    }
                }
                RoundedRectangle(cornerRadius: palette.woodGrain ? 3 : 9)
                    .fill(LinearGradient(colors: palette.base, startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: palette.woodGrain ? 3 : 9).stroke(palette.trim, lineWidth: 1))
                    .frame(width: w * (palette.woodGrain ? 1.05 : 0.98), height: h * 0.06)
                    .position(x: proxy.size.width / 2, y: h * 0.945)
                Text("M E T R O N O M E")
                    .font(.system(size: 7, weight: .semibold, design: .serif))
                    .foregroundStyle(appearance == .icon ? Color(hex: 0x1A2228) : palette.darkFace ? palette.ink : palette.trim)
                    .position(x: proxy.size.width / 2, y: h * 0.945)
            }
        }
        .coordinateSpace(name: "instrument")
    }
}

/// 雕刻装饰使用与黄铜面板相同的局部坐标，并裁切在面板内。
private struct DialEngraving: View {
    let palette: InstrumentPalette
    private var ink: Color { palette.ink }

    var body: some View {
        Canvas { context, actualSize in
            let outline = MetronomeCase(topInset: 0.25, cornerRadius: palette.cornerRadius * 0.7)
            context.clip(to: outline.path(in: CGRect(origin: .zero, size: actualSize)))
            let scale = min(actualSize.width / 182.784, 1)
            let size = CGSize(width: actualSize.width / scale, height: actualSize.height / scale)
            context.scaleBy(x: scale, y: scale)
            let rect = CGRect(origin: .zero, size: size)
            context.clip(to: outline.path(in: rect))
            context.stroke(outline.path(in: rect.insetBy(dx: 5, dy: 5)),
                           with: .color(ink.opacity(0.45)), lineWidth: 0.7)
            context.stroke(outline.path(in: rect.insetBy(dx: 7, dy: 7)),
                           with: .color(.white.opacity(0.24)), lineWidth: 0.5)

            // 拉丝与双层内框为金属表面增加细节。
            for row in stride(from: 3.0, to: size.height, by: 3.0) {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: row))
                line.addLine(to: CGPoint(x: size.width, y: row))
                context.stroke(line, with: .color(.white.opacity(0.055)), lineWidth: 0.5)
            }

            // 面板上边缘在机身高度的 9%，速度行与配重使用相同映射。
            for bpm in [20, 40, 60, 80, 100, 140, 180, 200, 240, 280, 320, 360, 400] {
                let y = ((0.22 + Double(bpm - BPMInput.range.lowerBound) / Double(BPMInput.range.upperBound - BPMInput.range.lowerBound) * 0.49) - 0.09) / 0.68 * size.height
                let major = [20, 100, 200, 400].contains(bpm)
                var tick = Path()
                tick.move(to: CGPoint(x: size.width / 2 - (major ? 36 : 30), y: y))
                tick.addLine(to: CGPoint(x: size.width / 2 - 22, y: y))
                context.stroke(tick, with: .color(ink.opacity(major ? 0.85 : 0.45)), lineWidth: major ? 1.2 : 0.7)
            }

            for (label, height) in [("慢速", 0.32), ("中速", 0.49), ("快速", 0.64)] {
                context.draw(Text(label).font(.system(size: 9, weight: .semibold, design: .serif)).foregroundColor(ink.opacity(0.8)),
                             at: CGPoint(x: size.width / 2 - 44, y: (height - 0.09) / 0.68 * size.height))
            }
            context.draw(Text("BPM").font(.system(size: 7, weight: .bold, design: .serif)).foregroundColor(ink.opacity(0.75)),
                         at: CGPoint(x: size.width / 2 - 25, y: size.height * 0.09))
            context.draw(Text("20–400").font(.system(size: 7, weight: .medium, design: .serif)).foregroundColor(ink.opacity(0.75)),
                         at: CGPoint(x: size.width / 2 + 25, y: size.height * 0.09))

            // 四颗沉头螺钉均按梯形边界内缩。
            for point in [CGPoint(x: size.width * 0.25 + 9, y: 12),
                          CGPoint(x: size.width * 0.75 - 9, y: 12),
                          CGPoint(x: 12, y: size.height - 12),
                          CGPoint(x: size.width - 12, y: size.height - 12)] {
                let screw = Path(ellipseIn: CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5))
                context.fill(screw, with: .color(ink.opacity(0.35)))
                context.stroke(screw, with: .color(.white.opacity(0.45)), lineWidth: 0.6)
                var slot = Path()
                slot.move(to: CGPoint(x: point.x - 1.5, y: point.y + 0.6))
                slot.addLine(to: CGPoint(x: point.x + 1.5, y: point.y - 0.6))
                context.stroke(slot, with: .color(ink.opacity(0.8)), lineWidth: 0.7)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct MetronomeCase: Shape {
    var topInset: CGFloat = 0.25
    var cornerRadius: CGFloat = 3

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, rect.width * 0.1)
        let left = rect.minX + rect.width * topInset
        let right = rect.maxX - rect.width * topInset
        return Path { path in
            path.move(to: CGPoint(x: left + r, y: rect.minY))
            path.addLine(to: CGPoint(x: right - r, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: right + r * 0.25, y: rect.minY + r), control: CGPoint(x: right, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - r * 0.25, y: rect.maxY - r))
            path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: rect.minX + r * 0.25, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: left - r * 0.25, y: rect.minY + r))
            path.addQuadCurve(to: CGPoint(x: left + r, y: rect.minY), control: CGPoint(x: left, y: rect.minY))
            path.closeSubpath()
        }
    }
}

/// 轻点单步，长按连续步进，同时提供 VoiceOver 原生按钮语义。
struct HoldRepeatButton: View {
    let symbol: String
    let action: () -> Void
    @State private var repeatTask: Task<Void, Never>?
    @State private var pressing = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 48, height: 48)
                .background(Circle().fill(pressing ? Theme.surface : Theme.panel))
                .overlay(Circle().stroke(Theme.stroke, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: 0.38, maximumDistance: 20, pressing: { down in
            if !down { end() }
        }, perform: { beginRepeating() })
        .accessibilityLabel(symbol == "plus" ? "加快一 BPM" : "减慢一 BPM")
        .onDisappear { end() }
    }

    private func beginRepeating() {
        guard !pressing else { return }
        pressing = true
        repeatTask = Task { @MainActor in
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
