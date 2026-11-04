import SwiftUI

struct MetronomeView: View {
    @ObservedObject var vm: MetronomeViewModel
    @State private var showSettings = false
    @State private var showMeterPicker = false
    @State private var showPractice = false
    @State private var showFavorites = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width <= 375 || proxy.size.height < 700
            ZStack(alignment: .top) {
                Theme.background.ignoresSafeArea().onTapGesture { handleBackgroundTap() }
                RadialGradient(colors: [Color(hex: 0x23465E).opacity(0.35), .clear], center: .init(x: 0.5, y: 0.35), startRadius: 20, endRadius: 340)
                    .ignoresSafeArea().allowsHitTesting(false)

                VStack(spacing: 0) {
                    topBar
                    // GeometryReader 已扣除底部操作区；机身使用剩余高度，避免小屏溢出。
                    BPMControl(vm: vm, compact: compact, instrumentHeight: min(max(proxy.size.height - 210, 0), 440))
                    Spacer(minLength: 12)
                    beatArea(compact: compact)
                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 22)
                .padding(.top, 2)
                .padding(.bottom, 8)
                .frame(maxWidth: 500)
                .frame(maxWidth: .infinity)
                .frame(height: proxy.size.height)
                .contentShape(Rectangle())
                .onTapGesture { handleBackgroundTap() }
                bannerOverlay
            }
            .onAppear {
                #if DEBUG
                if ScreenshotMode.isActive {
                    ScreenshotMode.apply(to: vm)
                    showSettings = ScreenshotMode.showsSettings
                    showFavorites = ScreenshotMode.showsFavorites
                    showPractice = ScreenshotMode.showsPracticeSettings
                    showMeterPicker = ScreenshotMode.showsMeter
                }
                #endif
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                rhythmControls.disabled(vm.isPracticeRunning)
                if !vm.isPracticeRunning { favoritesArea }
                practiceArea
                playArea
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 8)
            .frame(maxWidth: 540)
            .frame(maxWidth: .infinity)
            .background {
                ControlPanelBackground()
                    .onTapGesture { handleBackgroundTap() }
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            SettingsView(vm: vm)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showMeterPicker) {
            MeterPickerView(vm: vm)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPractice) {
            TempoPracticeView(vm: vm)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { vm.commitBPMEditing() }
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active { vm.saveSettingsNow() }
        }
    }

    private func handleBackgroundTap() {
        vm.commitBPMEditing()
        guard showFavorites else { return }
        withAnimation(.easeInOut(duration: 0.2)) { showFavorites = false }
    }

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("节拍器")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text(vm.appearance.title)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button {
                vm.commitBPMEditing()
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Theme.panel))
                    .overlay(Circle().stroke(Theme.stroke, lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("设置")
        }
        .frame(height: 52)
    }

    private func beatArea(compact: Bool) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !vm.isRunning)) { _ in
            let position = vm.isRunning ? vm.engine.position() : nil
            let beats = position?.beatsPerBar ?? vm.beatsPerBar
            HStack(spacing: 10) {
                HStack(spacing: beats > 6 ? 5 : 10) {
                    ForEach(0..<beats, id: \.self) { index in
                        let active = position?.beat == index
                        Circle()
                            .fill(active ? Theme.accent : Theme.dotIdle)
                            .frame(width: index == 0 ? 10 : 7, height: index == 0 ? 10 : 7)
                            .overlay(Circle().stroke(index == 0 ? Theme.accent.opacity(0.5) : .clear, lineWidth: 1).padding(-3))
                    }
                }
                Rectangle().fill(Theme.stroke).frame(width: 1, height: 14)
                Text(position.map { $0.isCountIn ? "预备 \($0.beat + 1)/\(beats)" : "第 \($0.barNumber) 小节 · 第 \($0.beat + 1) 拍" } ?? "准备好，开始练习")
                    .font(.system(size: 11).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 28)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("拍号 \((position?.timeSignature ?? vm.timeSignature).display)，每小节 \(beats) 拍")
        }
    }

    private var rhythmControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text("拍号")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 32, alignment: .leading)
                SegmentedRow(items: TimeSignature.common,
                             title: { $0.display },
                             isSelected: { $0 == vm.timeSignature },
                             onSelect: { vm.commitBPMEditing(); vm.setTimeSignature($0) })
                Button {
                    vm.commitBPMEditing()
                    showMeterPicker = true
                } label: {
                    Text(TimeSignature.common.contains(vm.timeSignature) ? "更多" : vm.timeSignature.display)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.surface))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("更多拍号与计拍设置，当前 \(vm.timeSignature.display)")
            }
            HStack(spacing: 10) {
                Text("细分")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 32, alignment: .leading)
                SegmentedRow(items: Subdivision.allCases,
                             title: { $0 == .none ? "无" : "\($0.partsPerBeat) 等分" },
                             isSelected: { $0 == vm.subdivision },
                             onSelect: { vm.commitBPMEditing(); vm.setSubdivision($0) })
            }
        }
    }

    private var favoritesArea: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    vm.commitBPMEditing()
                    withAnimation(.easeInOut(duration: 0.2)) { showFavorites.toggle() }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "star")
                        Text("常用节拍 · \(vm.favorites.items.count)/5")
                        Image(systemName: showFavorites ? "chevron.down" : "chevron.up")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showFavorites ? "收起常用节拍收藏夹" : "展开常用节拍收藏夹")
                .accessibilityValue("\(vm.favorites.items.count) 组收藏")
                Spacer(minLength: 0)
                Button {
                    vm.saveFavorite()
                    if vm.favorites.items.count == RhythmFavorites.capacity && !vm.currentIsFavorite {
                        withAnimation(.easeInOut(duration: 0.2)) { showFavorites = true }
                    }
                } label: {
                    Label(vm.currentIsFavorite ? "已收藏" : "收藏当前", systemImage: vm.currentIsFavorite ? "checkmark" : "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(vm.currentIsFavorite && vm.bpmDraft == nil)
            }
            if showFavorites {
                Text("轻点切换 · 长按收藏可用当前设置覆盖或移除")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    ForEach(0..<RhythmFavorites.capacity, id: \.self) { index in
                        if index < vm.favorites.items.count {
                            let favorite = vm.favorites.items[index]
                            let selected = favorite.matches(vm.settings)
                            Button {
                                vm.applyFavorite(favorite)
                                withAnimation(.easeInOut(duration: 0.2)) { showFavorites = false }
                            } label: {
                                VStack(spacing: 3) {
                                    Text("\(favorite.bpm)")
                                        .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                                    Text("\(favorite.timeSignature.display) · \(favorite.timeSignature.unit(favorite.beatCounting).symbol)")
                                        .font(.system(size: 10))
                                    Text(favorite.subdivision == .none ? "无细分" : "\(favorite.subdivision.partsPerBeat) 等分")
                                        .font(.system(size: 9))
                                }
                                .foregroundStyle(selected ? Theme.background : Theme.textPrimary)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(RoundedRectangle(cornerRadius: 9).fill(selected ? Theme.accent : Theme.surface))
                            }
                            .buttonStyle(PressableButtonStyle())
                            .accessibilityLabel("收藏 \(index + 1)，\(favorite.bpm) BPM，\(favorite.timeSignature.display)，\(favorite.timeSignature.unit(favorite.beatCounting).symbol)计拍，\(favorite.subdivision.label)，分组\(favorite.timeSignature.groups(grouping: favorite.grouping).map(String.init).joined(separator: "+"))，重音\(favorite.accentEnabled ? "开" : "关")")
                            .accessibilityAddTraits(selected ? .isSelected : [])
                            .accessibilityHint("轻点切换，长按可用当前设置覆盖或移除收藏")
                            .contextMenu {
                                Button { vm.updateFavorite(favorite) } label: {
                                    Label("用当前设置覆盖", systemImage: "arrow.triangle.2.circlepath")
                                }
                                Button(role: .destructive) { vm.removeFavorite(favorite) } label: {
                                    Label("移除收藏", systemImage: "star.slash")
                                }
                            }
                            .accessibilityAction(named: "用当前设置覆盖") { vm.updateFavorite(favorite) }
                            .accessibilityAction(named: "移除收藏") { vm.removeFavorite(favorite) }
                        } else {
                            Button { vm.saveFavorite() } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.textTertiary)
                                    .frame(maxWidth: .infinity, minHeight: 52)
                                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.stroke, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("收藏当前节拍到第 \(vm.favorites.items.count + 1) 个位置")
                            .disabled(vm.currentIsFavorite && vm.bpmDraft == nil)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    private var practiceArea: some View {
        HStack(spacing: 8) {
            Button {
                vm.commitBPMEditing()
                showPractice = true
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Label(vm.settings.practice.enabled ? "渐进提速 · \(vm.settings.practice.startBPM) → \(vm.settings.practice.targetBPM)" : "渐进提速练习", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 12, weight: .medium))
                    Text(vm.settings.practice.enabled ? vm.practiceStatus : "未启用 · 点标题配置")
                        .font(.system(size: 10).monospacedDigit())
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                .foregroundStyle(vm.settings.practice.enabled ? Theme.accent : Theme.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("渐进提速练习设置")
            .accessibilityValue(vm.settings.practice.enabled ? vm.practiceStatus : "未启用")
            if vm.isPracticeRunning {
                Button { vm.requestPracticeAction(.stepBack) } label: {
                    VStack(spacing: 2) {
                        Image(systemName: vm.pendingPracticeAction == .stepBack ? "clock" : "backward.end")
                        Text(vm.pendingPracticeAction == .stepBack ? "待退档" : "退一档").font(.system(size: 9))
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("退回一档并保持")
                .accessibilityIdentifier("practice-step-back")
                .disabled(vm.pendingPracticeAction != nil || vm.practiceProgress == nil)
                Button {
                    vm.requestPracticeAction(vm.practiceProgress?.isHolding == true ? .resume : .hold)
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: vm.pendingPracticeAction != nil ? "clock" : vm.practiceProgress?.isHolding == true ? "play.circle.fill" : "pause.circle")
                        Text(vm.pendingPracticeAction == .hold ? "待保持" : vm.pendingPracticeAction == .resume ? "待继续" : vm.practiceProgress?.isHolding == true ? "继续" : "保持")
                            .font(.system(size: 9))
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .background {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.accent.opacity(vm.pendingPracticeAction != nil || vm.practiceProgress?.isHolding == true ? 0.15 : 0))
                }
                .accessibilityLabel(vm.practiceProgress?.isHolding == true ? "继续自动提速" : "保持当前速度")
                .accessibilityValue(vm.pendingPracticeAction != nil ? "等待小节生效" : vm.practiceProgress?.isHolding == true ? "当前保持速度" : "自动提速中")
                .accessibilityIdentifier("practice-hold-resume")
                .disabled(vm.pendingPracticeAction != nil || vm.practiceProgress == nil)
            } else {
                Toggle("渐进提速", isOn: Binding(
                    get: { vm.settings.practice.enabled },
                    set: { vm.setPracticeEnabled($0) }
                ))
                .labelsHidden()
                .tint(Theme.accent)
                .frame(width: 64, height: 44)
                .disabled(vm.isRunning)
                .accessibilityIdentifier("practice-enabled")
                .accessibilityHint(vm.isRunning ? "停止播放后可切换" : "保留练习方案，点击标题可配置")
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.accent)
    }

    private var playArea: some View {
        Button { vm.commitBPMEditing(); showFavorites = false; vm.togglePlayback() } label: {
            HStack(spacing: 10) {
                Image(systemName: vm.isRunning ? "stop.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text(vm.isRunning ? "停止" : vm.settings.practice.enabled ? "开始练习" : "开始")
                    .font(.system(size: 16, weight: .semibold))
                    .tracking(2)
            }
            .foregroundStyle(vm.isRunning ? Theme.accent : Theme.background)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(vm.isRunning ? Theme.panel : Theme.accent)
            }
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.accent.opacity(0.65), lineWidth: 1))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(vm.isRunning ? "停止节拍" : "开始节拍")
    }

    @ViewBuilder private var bannerOverlay: some View {
        if let banner = vm.banner {
            Text(banner)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(Theme.surface))
                .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
                .padding(.top, 55)
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 操作区与机身分层，频繁使用的控件始终在拇指可达区域。
private struct ControlPanelBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Theme.panel)
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.stroke.opacity(0.65), lineWidth: 0.5))
            .ignoresSafeArea(edges: .bottom)
    }
}
