import SwiftUI

/// 扩展拍号与计拍选项集中在面板中，主页保持固定且紧凑。
struct MeterPickerView: View {
    @ObservedObject var vm: MetronomeViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    meterSection("常用与单拍子", signatures: [.twoFour, .threeFour, .fourFour, .threeEight, .twoTwo, .threeTwo])
                    meterSection("复拍子", signatures: [.sixEight, .nineEight, .twelveEight, .sixFour])
                    meterSection("不规则拍子", signatures: [.fiveFour, .sevenFour, .fiveEight, .sevenEight])
                    if vm.timeSignature.isCompound {
                        VStack(alignment: .leading, spacing: 10) {
                            caption("计拍单位")
                            SegmentedRow(items: BeatCounting.allCases,
                                         title: { "\($0.title) \(vm.timeSignature.unit($0).symbol)" },
                                         isSelected: { $0 == vm.beatCounting },
                                         onSelect: { vm.setBeatCounting($0) })
                            Text("按大拍感受律动，按小拍逐音慢练。切换时换算 BPM，尽量保持小节时长；速度范围为 20–400。")
                                .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                            if vm.beatCounting == .grouped {
                                Button("启用每大拍三等分") { vm.setSubdivision(.three) }
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Theme.accent)
                                    .frame(minHeight: 44)
                            }
                        }
                    }
                    if vm.timeSignature.isIrregular {
                        VStack(alignment: .leading, spacing: 10) {
                            caption("重音分组")
                            SegmentedRow(items: Array(vm.timeSignature.groupingOptions.indices),
                                         title: { vm.timeSignature.groupingOptions[$0].map(String.init).joined(separator: "+") },
                                         isSelected: { $0 == vm.grouping },
                                         onSelect: { vm.setGrouping($0) })
                        }
                    }
                    Text("\(vm.tempoLabel) · 每小节 \(vm.beatsPerBar) 拍\n播放中，拍号、计拍单位和重音分组在后续小节一起生效。")
                        .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                        .lineSpacing(5)
                }
                .padding(20)
                .disabled(vm.isPracticeRunning)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("拍号与计拍")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }.foregroundStyle(Theme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func meterSection(_ title: String, signatures: [TimeSignature]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            caption(title)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                ForEach(signatures) { signature in
                    let selected = vm.timeSignature == signature
                    Button { vm.setTimeSignature(signature) } label: {
                        Text(signature.display)
                            .font(.system(size: 17, weight: .medium).monospacedDigit())
                            .foregroundStyle(selected ? Theme.background : Theme.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Theme.accent : Theme.surface))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(signature.display) 拍号")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private func caption(_ title: String) -> some View {
        Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textSecondary)
    }
}
