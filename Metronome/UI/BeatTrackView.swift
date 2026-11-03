import SwiftUI

/// 拍点行 + 拍序数字。完全由 `PlaybackPosition` 驱动，自身不持有任何计时。
struct BeatTrackView: View {

    let timeSignature: TimeSignature
    let partsPerBeat: Int
    let position: PlaybackPosition?

    private var beatsPerBar: Int { timeSignature.beatsPerBar }
    private var activeBeat: Int? { position?.beat }
    private var activePart: Int { position?.part ?? 0 }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                ForEach(0..<beatsPerBar, id: \.self) { index in
                    column(index)
                        .frame(maxWidth: .infinity)
                }
            }
            numberBlock
        }
        // 必须显式撑满宽度，否则 HStack 会收缩到内容宽度，拍点全部挤在左侧。
        .frame(maxWidth: .infinity)
        .animation(nil, value: activeBeat)
    }

    private func column(_ index: Int) -> some View {
        let isActive = activeBeat == index
        let isFirst = index == 0
        let isGroupStart = timeSignature.isCompound && index == timeSignature.groups.first

        var base: CGFloat = 17
        if isFirst { base *= 1.18 }
        if isGroupStart { base *= 1.08 }
        let size = isActive ? base * 1.32 : base

        return VStack(spacing: 6) {
            ZStack {
                if isActive {
                    Circle()
                        .stroke(Theme.accent.opacity(0.3), lineWidth: 1.5)
                        .frame(width: size + 12, height: size + 12)
                }
                if isFirst && !isActive {
                    Circle()
                        .stroke(Theme.textTertiary, lineWidth: 1)
                        .frame(width: size + 10, height: size + 10)
                }
                Circle()
                    .fill(isActive ? Theme.accent : Theme.dotIdle)
                    .frame(width: size, height: size)
            }
            .frame(height: 42)

            HStack(spacing: 3) {
                ForEach(1..<max(partsPerBeat, 2), id: \.self) { part in
                    Circle()
                        .fill(isActive && part == activePart ? Theme.accent : Theme.dotIdle)
                        .frame(width: 4, height: 4)
                }
            }
            .frame(height: 4)
            .opacity(partsPerBeat > 1 && isActive ? 1 : 0)

            Text("\(index + 1)")
                .font(.system(size: 11, weight: isFirst ? .medium : .regular, design: .rounded).monospacedDigit())
                .foregroundStyle(isActive ? Theme.textPrimary : Theme.textTertiary)
        }
        .accessibilityHidden(true)
    }

    private var numberBlock: some View {
        VStack(spacing: 2) {
            if let position, position.isCountIn {
                Text("预备")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.accent)
                Text("\(position.beat + 1) / \(beatsPerBar)")
                    .font(.system(size: 12, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.textTertiary)
            } else {
                Text("\((position?.beat ?? 0) + 1)")
                    .font(.system(size: 46, weight: .light, design: .rounded).monospacedDigit())
                    .foregroundStyle(position == nil ? Theme.textTertiary : Theme.textPrimary)
                Text("第 \(position?.barNumber ?? 1) 小节")
                    .font(.system(size: 12, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(height: 84)
    }
}

/// 分段控件。自绘而不用系统 Picker，是因为系统样式在深色谱架场景下对比度不足。
struct SegmentedRow<Item: Hashable>: View {

    let items: [Item]
    let title: (Item) -> String
    let isSelected: (Item) -> Bool
    let onSelect: (Item) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.self) { item in
                let selected = isSelected(item)
                Button {
                    onSelect(item)
                } label: {
                    Text(title(item))
                        .font(.system(size: 14, weight: selected ? .medium : .regular, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(selected ? Theme.accent : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(selected ? Color.clear : Theme.stroke, lineWidth: 0.5)
                        )
                        .foregroundStyle(selected ? Theme.background : Theme.textSecondary)
                        // 未选中时背景是 Color.clear，不显式声明热区的话
                        // 圆角边缘那一点会点不动。这里统一按整块矩形响应。
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
