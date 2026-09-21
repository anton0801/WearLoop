//
//  SegmentBar.swift
//  WearLoop
//
//  Navigation lives here. There is no tab bar: both the app's sections and the
//  filters inside a section are switched with this scrolling row of segments,
//  which keeps the bottom of every screen free for content.
//

import SwiftUI

/// One option in a segment row.
struct SegmentItem<Value: Hashable>: Identifiable {
    var id: Value { value }
    var value: Value
    var title: String
    /// Optional count shown after the label, e.g. "In the Wash 3".
    var badge: Int?

    init(value: Value, title: String, badge: Int? = nil) {
        self.value = value
        self.title = title
        self.badge = badge
    }
}

struct SegmentBar<Value: Hashable>: View {
    let items: [SegmentItem<Value>]
    @Binding var selection: Value
    /// Colour of the active segment fill.
    var activeFill: Color = Palette.anchor
    var activeText: Color = Palette.onAnchor

    @Environment(\.wlDarkSurface) private var isDark
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Namespace private var namespace

    var body: some View {
        let colours = SurfaceColours.forDark(isDark)
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items) { item in
                        segment(item, colours: colours)
                            .id(item.value)
                    }
                }
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.vertical, 2)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: selection) { _, newValue in
                withAnimation(systemReduceMotion ? nil : Motion.segment) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func segment(_ item: SegmentItem<Value>, colours: SurfaceColours) -> some View {
        let isActive = item.value == selection
        return Button {
            guard !isActive else { return }
            withAnimation(systemReduceMotion ? nil : Motion.segment) {
                selection = item.value
            }
        } label: {
            HStack(spacing: 6) {
                Text(item.title)
                    .font(TypeScale.segment)
                    .lineLimit(1)
                if let badge = item.badge, badge > 0 {
                    Text("\(badge)")
                        .font(TypeScale.captionSmall)
                        .monospacedDigit()
                        .foregroundStyle(isActive ? activeFill : Palette.onAnchor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(isActive ? activeText : colours.text.opacity(0.75))
                        )
                }
            }
            .foregroundStyle(isActive ? activeText : colours.text)
            .padding(.horizontal, 18)
            .frame(height: Metrics.segmentHeight)
            .background(
                ZStack {
                    // The inactive pill.
                    Capsule(style: .continuous)
                        .fill(isDark ? colours.card : Palette.surface)
                    // The active fill slides between segments.
                    if isActive {
                        Capsule(style: .continuous)
                            .fill(activeFill)
                            .matchedGeometryEffect(id: "segment-fill", in: namespace)
                    }
                }
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.badge.map { "\(item.title), \($0)" } ?? item.title)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Convenience for enum-backed segments

extension SegmentBar {
    /// Builds a row from titled cases.
    init(
        values: [Value],
        selection: Binding<Value>,
        title: @escaping (Value) -> String,
        badge: @escaping (Value) -> Int? = { _ in nil },
        activeFill: Color = Palette.anchor,
        activeText: Color = Palette.onAnchor
    ) {
        self.items = values.map { SegmentItem(value: $0, title: title($0), badge: badge($0)) }
        self._selection = selection
        self.activeFill = activeFill
        self.activeText = activeText
    }
}

// MARK: - Stage indicator

/// The Setup → Day Plan → … → Recap indicator on the trip workspace. Stages the
/// user cannot reach yet are visibly out of reach rather than hidden.
struct StageIndicator: View {
    let stages: [TripStage]
    let current: TripStage
    /// Stages that are reachable right now.
    let reachable: Set<TripStage>
    var onSelect: (TripStage) -> Void

    @Environment(\.wlDarkSurface) private var isDark

    var body: some View {
        let colours = SurfaceColours.forDark(isDark)
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(stages.enumerated()), id: \.element) { index, stage in
                        HStack(spacing: 6) {
                            stageChip(stage, colours: colours)
                                .id(stage)
                            if index < stages.count - 1 {
                                Rectangle()
                                    .fill(colours.text.opacity(0.25))
                                    .frame(width: 10, height: 2)
                            }
                        }
                    }
                }
                .padding(.horizontal, Metrics.screenPadding)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onAppear { proxy.scrollTo(current, anchor: .center) }
            .onChange(of: current) { _, newValue in
                withAnimation(Motion.segment) { proxy.scrollTo(newValue, anchor: .center) }
            }
        }
    }

    private func stageChip(_ stage: TripStage, colours: SurfaceColours) -> some View {
        let isCurrent = stage == current
        let isDone = stage.order < current.order
        let canOpen = reachable.contains(stage)

        return Button {
            onSelect(stage)
        } label: {
            HStack(spacing: 5) {
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .black))
                }
                Text(stage.title)
                    .font(TypeScale.captionSmall)
                    .lineLimit(1)
            }
            .foregroundStyle(
                isCurrent ? Palette.onAnchor : (canOpen ? colours.text : colours.text.opacity(0.4))
            )
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(
                Capsule(style: .continuous)
                    .fill(isCurrent ? Palette.burgundy : (isDone ? Palette.amber.opacity(0.35) : (isDark ? colours.card : Palette.surface)))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(canOpen && !isCurrent ? colours.text.opacity(0.4) : .clear, lineWidth: 1.5)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(stage.title)\(isCurrent ? ", current stage" : "")\(isDone ? ", done" : "")")
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
    }
}
