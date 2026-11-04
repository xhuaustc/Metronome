import SwiftUI

/// 拍点行 + 拍序数字。完全由 `PlaybackPosition` 驱动，自身不持有任何计时。
struct BeatTrackView: View {

    let timeSignature: TimeSignature
    let partsPerBeat: Int
    let position: PlaybackPosition?
    var compact = false

    private let accent = Theme.accent
    private var beatsPerBar: Int { position?.beatsPerBar ?? timeSignature.beatsPerBar }
    private var activeBeat: Int? { position?.beat }
    private var activePart: Int { position?.part ?? 0 }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(0..<beatsPerBar, id: \.self) { index in
                            column(index)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(width: max(proxy.size.width, CGFloat(beatsPerBar) * 40))
                }
            }
            .frame(height: compact ? 58 : 70)
            numberBlock
        }
        .frame(maxWidth: .infinity)
        .animation(nil, value: activeBeat)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("拍点，\(timeSignature.display) 拍号，每小节 \(beatsPerBar) 拍")
        .accessibilityValue(accessibilityPosition)
    }

    private var accessibilityPosition: String {
        guard let position else { return "已停止" }
        let beat = "第 \(position.beat + 1) 拍"
        let part = partsPerBeat > 1 ? "，细分 \(position.part + 1)/\(partsPerBeat)" : ""
        if position.isCountIn {
            return "预备拍，\(beat)，共 \(beatsPerBar) 拍\(part)"
        }
        return "第 \(position.barNumber) 小节，\(beat)\(part)"
    }

    private func column(_ index: Int) -> some View {
        let isActive = activeBeat == index
        let isFirst = index == 0
        let isGroupStart = timeSignature.isCompound && index == timeSignature.groups.first

        return VStack(spacing: 6) {
            ZStack {
                if isFirst {
                    Circle()
                        .strokeBorder(isActive ? accent : Theme.textTertiary, lineWidth: 1.5)
                        .frame(width: 34, height: 34)
                }
                Circle()
                    .fill(isActive ? accent : Theme.dotIdle)
                    .frame(width: 26, height: 26)
                if isGroupStart {
                    Circle()
                        .strokeBorder(isActive ? Theme.background : Theme.textSecondary, lineWidth: 1)
                        .frame(width: 20, height: 20)
                }
            }
            .frame(height: 34)

            HStack(spacing: 3) {
                ForEach(1..<max(partsPerBeat, 2), id: \.self) { part in
                    Circle()
                        .fill(isActive && part == activePart ? accent : Theme.dotIdle)
                        .frame(width: 4, height: 4)
                }
            }
            .frame(height: 4)
            .opacity(partsPerBeat > 1 && isActive ? 1 : 0)

            Text("\(index + 1)")
                .font(.system(size: 11, weight: isFirst ? .medium : .regular, design: .rounded).monospacedDigit())
                .foregroundStyle(isActive ? Theme.textPrimary : Theme.textTertiary)
        }
    }

    private var numberBlock: some View {
        VStack(spacing: 2) {
            if let position, position.isCountIn {
                Text("预备")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundStyle(accent)
                Text("\(position.beat + 1) / \(beatsPerBar)")
                    .font(.system(size: 12, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.textTertiary)
            } else {
                Text("\((position?.beat ?? 0) + 1)")
                    .font(.system(size: compact ? 32 : 46, weight: .light, design: .rounded).monospacedDigit())
                    .foregroundStyle(position == nil ? Theme.textTertiary : Theme.textPrimary)
                Text("第 \(position?.barNumber ?? 1) 小节")
                    .font(.system(size: 12, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(height: compact ? 58 : 84)
    }
}

/// 分段控件。自绘而不用系统 Picker，是因为系统样式在深色谱架场景下对比度不足。
struct SegmentedRow<Item: Hashable>: View {

    let items: [Item]
    let title: (Item) -> String
    let isSelected: (Item) -> Bool
    let onSelect: (Item) -> Void

    var minimumItemWidth: CGFloat = 44

    private let accent = Theme.accent

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(items, id: \.self) { item in
                        let selected = isSelected(item)
                        Button {
                            onSelect(item)
                        } label: {
                            Text(title(item))
                                .font(.system(size: 14, weight: selected ? .medium : .regular, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(selected ? accent : Theme.surface)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .stroke(selected ? Color.clear : Theme.stroke, lineWidth: 0.5)
                                )
                                .foregroundStyle(selected ? Theme.background : Theme.textSecondary)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .frame(width: max(proxy.size.width, CGFloat(items.count) * minimumItemWidth + CGFloat(max(items.count - 1, 0)) * 6))
            }
        }
        .frame(height: 44)
    }
}
