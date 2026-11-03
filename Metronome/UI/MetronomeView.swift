import SwiftUI

struct MetronomeView: View {

    @ObservedObject var vm: MetronomeViewModel
    @State private var showSettings = false
    /// 键盘弹出时 GeometryReader 会缩小，这里锁住首次布局高度，
    /// 让页面在原地不动、键盘直接盖住下半部分。
    @State private var canvasHeight: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let height = canvasHeight > 0 ? canvasHeight : proxy.size.height

            ZStack {
                Theme.background
                    .ignoresSafeArea()
                    .onTapGesture { vm.commitBPMEditing() }

                VStack(spacing: 0) {
                    topBar
                    BPMControl(vm: vm)
                    beatArea
                        .frame(maxHeight: .infinity)
                    lowerControls
                    playArea
                        .padding(.top, 10)
                }
                .padding(.horizontal, 20)
                .padding(.top, 2)
                .padding(.bottom, 8)

                bannerOverlay
            }
            // 固定高度并顶部对齐：即使可用空间被键盘压小，
            // 内容也不会被压缩或居中上移，多余部分自然落到键盘下面。
            .frame(width: proxy.size.width, height: height, alignment: .top)
            .onAppear {
                if canvasHeight == 0 { canvasHeight = proxy.size.height }
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            SettingsView(vm: vm)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { vm.commitBPMEditing() }
            }
        }
    }

    // MARK: - 顶部

    private var topBar: some View {
        HStack {
            Text("钢琴节拍器")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("设置")
        }
        .frame(height: 44)
    }

    // MARK: - 拍点

    private var beatArea: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 120.0, paused: !vm.isRunning)) { _ in
            BeatTrackView(timeSignature: vm.timeSignature,
                          partsPerBeat: vm.subdivision.partsPerBeat,
                          position: vm.isRunning ? vm.engine.position() : nil)
        }
        .padding(.vertical, 6)
    }

    // MARK: - 中下部控件

    private var lowerControls: some View {
        VStack(spacing: 10) {
            SegmentedRow(items: TimeSignature.allCases,
                         title: { $0.display },
                         isSelected: { $0 == vm.timeSignature },
                         onSelect: { vm.setTimeSignature($0) })

            SegmentedRow(items: Subdivision.allCases,
                         title: { $0.label },
                         isSelected: { $0 == vm.subdivision },
                         onSelect: { vm.setSubdivision($0) })

            volumeRow

            HStack(spacing: 8) {
                ToggleChip(title: "重音", isOn: vm.accentEnabled) {
                    vm.setAccentEnabled(!vm.accentEnabled)
                }
                ToggleChip(title: "预备拍", isOn: vm.countInEnabled) {
                    vm.setCountInEnabled(!vm.countInEnabled)
                }
                Spacer()
            }
        }
    }

    private var volumeRow: some View {
        HStack(spacing: 10) {
            Image(systemName: vm.volume < 0.01 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 20)

            Slider(value: Binding(get: { vm.volume }, set: { vm.setVolume($0) }), in: 0...1)
                .tint(Theme.textPrimary)

            Text("\(Int((vm.volume * 100).rounded()))")
                .font(.system(size: 12, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 28, alignment: .trailing)
        }
        .frame(height: 34)
    }

    // MARK: - 主按钮

    private var playArea: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !vm.isRunning)) { _ in
                let progress = vm.isRunning ? (vm.engine.position()?.progress ?? 0) : 0
                ZStack {
                    Circle()
                        .stroke(Theme.stroke, lineWidth: 2)
                        .frame(width: 112, height: 112)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Theme.accent.opacity(0.55),
                                style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 112, height: 112)
                        .rotationEffect(.degrees(-90))
                }
            }
            .allowsHitTesting(false)

            Button {
                vm.togglePlayback()
            } label: {
                ZStack {
                    Circle()
                        .fill(vm.isRunning ? Theme.warning : Theme.accent)
                    if vm.isRunning {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Theme.background)
                            .frame(width: 26, height: 26)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(Theme.background)
                            .offset(x: 2)
                    }
                }
                .frame(width: 96, height: 96)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(vm.isRunning ? "停止节拍" : "开始节拍")
        }
        .frame(height: 120)
    }

    // MARK: - 提示

    @ViewBuilder
    private var bannerOverlay: some View {
        if let banner = vm.banner {
            VStack {
                Text(banner)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Theme.surface))
                    .overlay(Capsule().stroke(Theme.stroke, lineWidth: 0.5))
                    .padding(.top, 50)
                Spacer()
            }
            .transition(.opacity)
            .allowsHitTesting(false)
        }
    }
}

struct ToggleChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isOn ? Theme.accent : Theme.dotIdle)
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 13)
            .frame(height: 34)
            .background(Capsule().fill(isOn ? Theme.accent.opacity(0.14) : Color.clear))
            .overlay(Capsule().stroke(isOn ? Theme.accent.opacity(0.45) : Theme.stroke, lineWidth: 0.5))
            .foregroundStyle(isOn ? Theme.accent : Theme.textSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
