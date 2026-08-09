//
//  Layout.swift
//  WearLoop
//
//  Screens are built from horizontal rails with a bouncy edge, not from long
//  vertical lists. Vertical lists appear only in the packing list, the spend
//  list and the laundry log.
//

import SwiftUI

// MARK: - Screen scaffold

/// The page frame: background, scroll, and consistent padding.
struct ScreenScaffold<Content: View>: View {
    var isDark: Bool = false
    var showsScrollIndicator: Bool = false
    /// Extra bottom space so a floating action never covers the last row.
    var bottomInset: CGFloat = 32
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            (isDark ? Palette.anchor : Palette.background)
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: showsScrollIndicator) {
                VStack(alignment: .leading, spacing: Metrics.sectionGap) {
                    content()
                }
                .padding(.bottom, bottomInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .wlDarkSurface(isDark)
    }
}

/// Horizontal padding matching the rest of the screen, for blocks that are not
/// themselves rails.
struct ScreenBlock<Content: View>: View {
    var spacing: CGFloat = 12
    var alignment: HorizontalAlignment = .leading
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: alignment, spacing: spacing) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
        .padding(.horizontal, Metrics.screenPadding)
    }
}

// MARK: - Rails

/// A horizontal rail of cards with an elastic edge.
struct CardRail<Item: Identifiable, Content: View>: View {
    let items: [Item]
    var height: CGFloat = Metrics.railHeight
    var spacing: CGFloat = Metrics.cardGap
    @ViewBuilder var content: (Item) -> Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) {
                ForEach(items) { item in
                    content(item)
                }
            }
            .padding(.horizontal, Metrics.screenPadding)
        }
        .frame(height: height)
        // Elastic edge: the rail always bounces horizontally.
        .scrollBounceBehavior(.always, axes: .horizontal)
    }
}

/// A rail with a section header above it and an optional trailing action.
struct RailSection<Item: Identifiable, Content: View>: View {
    let title: String
    var accent: Color = Palette.amber
    var actionTitle: String?
    var action: (() -> Void)?
    let items: [Item]
    var height: CGFloat = Metrics.railHeight
    /// Shown in place of the rail when there is nothing to display.
    var emptyText: String?
    @ViewBuilder var content: (Item) -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScreenBlock {
                SectionHeader(title, accent: accent) {
                    if let actionTitle, let action {
                        Button(action: action) {
                            Text(actionTitle)
                        }
                        .buttonStyle(CompactOutlineButtonStyle())
                    }
                }
            }
            if items.isEmpty {
                if let emptyText {
                    ScreenBlock {
                        InlineNotice(text: emptyText)
                    }
                }
            } else {
                CardRail(items: items, height: height) { item in
                    content(item)
                }
            }
        }
    }
}

// MARK: - Cards and panels

/// A plain surface panel used for information blocks.
struct Panel<Content: View>: View {
    var padding: CGFloat = 16
    var fill: Color?
    var stroke: Color?
    @ViewBuilder var content: () -> Content

    @Environment(\.wlDarkSurface) private var isDark

    var body: some View {
        let colours = SurfaceColours.forDark(isDark)
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(padding)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .fill(fill ?? (isDark ? colours.card : Palette.surface))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(stroke ?? .clear, lineWidth: 2)
        )
    }
}

/// A short line of explanation, used where a rail would otherwise be empty.
struct InlineNotice: View {
    let text: String
    var icon: String?
    var colour: Color?

    @Environment(\.wlDarkSurface) private var isDark

    var body: some View {
        let colours = SurfaceColours.forDark(isDark)
        HStack(alignment: .top, spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(colour ?? colours.mutedText)
            }
            Text(text)
                .font(TypeScale.caption)
                .foregroundStyle(colour ?? colours.mutedText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isDark ? colours.card : Palette.surface)
        )
    }
}

/// A row that reads as a fact: label on the left, value on the right.
struct FactRow: View {
    let label: String
    let value: String
    var valueColour: Color?
    var isMonospaced: Bool = false

    @Environment(\.wlDarkSurface) private var isDark

    var body: some View {
        let colours = SurfaceColours.forDark(isDark)
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(TypeScale.caption)
                .foregroundStyle(colours.mutedText)
            Spacer(minLength: 8)
            Text(value)
                .font(isMonospaced ? TypeScale.caption.monospacedDigit() : TypeScale.bodyBold)
                .foregroundStyle(valueColour ?? colours.text)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

/// A tappable row that opens somewhere else.
struct NavigationRow: View {
    let title: String
    var subtitle: String?
    var value: String?
    var icon: String?
    var accent: Color?
    var showsChevron: Bool = true
    let action: () -> Void

    @Environment(\.wlDarkSurface) private var isDark

    var body: some View {
        let colours = SurfaceColours.forDark(isDark)
        Button(action: action) {
            HStack(spacing: 12) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(accent ?? colours.text)
                        .frame(width: 26)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(TypeScale.bodyBold)
                        .foregroundStyle(colours.text)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle)
                            .font(TypeScale.captionSmall)
                            .foregroundStyle(colours.mutedText)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if let value {
                    Text(value)
                        .font(TypeScale.caption)
                        .foregroundStyle(colours.mutedText)
                }
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(colours.mutedText)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isDark ? colours.card : Palette.surface)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(CardPressStyle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Empty, loading and error states

/// The empty state: a heavy lowercase headline over the halftone motif, with a
/// real action underneath.
struct EmptyStateView: View {
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
    var secondaryActionTitle: String?
    var secondaryAction: (() -> Void)?
    var showHalftone: Bool = true

    @Environment(\.wlDarkSurface) private var isDark

    var body: some View {
        let colours = SurfaceColours.forDark(isDark)
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title)
                Text(message)
                    .font(TypeScale.body)
                    .foregroundStyle(colours.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if actionTitle != nil || secondaryActionTitle != nil {
                VStack(spacing: 10) {
                    if let actionTitle, let action {
                        PrimaryButton(title: actionTitle, action: action)
                    }
                    if let secondaryActionTitle, let secondaryAction {
                        SecondaryButton(
                            title: secondaryActionTitle,
                            textColour: colours.text,
                            strokeColour: colours.stroke,
                            fillColour: isDark ? colours.card : Palette.surface,
                            action: secondaryAction
                        )
                    }
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .fill(isDark ? colours.card : Palette.surface)
                .halftoneBacking(enabled: showHalftone, opacity: isDark ? 0.12 : 0.2, focus: .topTrailing, spacing: 30)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        )
    }
}

/// Shown while the document is being read from disk.
struct LoadingStateView: View {
    var message: String = "Loading your wardrobe…"

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(Palette.anchor)
            Text(message)
                .font(TypeScale.caption)
                .foregroundStyle(Palette.anchor.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .accessibilityLabel(message)
    }
}

/// Shown when something genuinely failed, with a way to try again.
struct ErrorStateView: View {
    let title: String
    let message: String
    var retryTitle: String = "Try Again"
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title, accent: Palette.danger)
            Text(message)
                .font(TypeScale.body)
                .foregroundStyle(Palette.anchor.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            if let onRetry {
                PrimaryButton(title: retryTitle, action: onRetry)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Palette.danger, lineWidth: 2)
        )
    }
}

/// A warning the user must read but may override, e.g. a weather mismatch.
struct WarningPanel: View {
    let message: String
    var primaryTitle: String?
    var primaryAction: (() -> Void)?
    var secondaryTitle: String?
    var secondaryAction: (() -> Void)?
    var tint: Color = Palette.danger

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tint)
                Text(message)
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.anchor)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            if primaryTitle != nil || secondaryTitle != nil {
                HStack(spacing: 8) {
                    if let primaryTitle, let primaryAction {
                        Button(primaryTitle, action: primaryAction)
                            .buttonStyle(CompactButtonStyle(fill: tint, textColour: .white))
                    }
                    if let secondaryTitle, let secondaryAction {
                        Button(secondaryTitle, action: secondaryAction)
                            .buttonStyle(CompactOutlineButtonStyle())
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tint.opacity(0.45), lineWidth: 2)
        )
    }
}

// MARK: - Bars

/// A bar used by the insight rows.
struct ValueBar: View {
    let fraction: Double
    var fill: Color = Palette.amber
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(Palette.anchor.opacity(0.1))
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(fill)
                    .frame(width: max(geometry.size.width * min(max(fraction, 0), 1), fraction > 0 ? 6 : 0))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// A progress bar reading "3 of 6" rather than a decorative percentage.
struct CountProgress: View {
    let passed: Int
    let total: Int
    var label: String
    var fill: Color = Palette.success

    @Environment(\.wlDarkSurface) private var isDark

    var body: some View {
        let colours = SurfaceColours.forDark(isDark)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(passed)")
                    .font(TypeScale.mediumNumber)
                    .foregroundStyle(colours.text)
                Text("of \(total) \(label)")
                    .font(TypeScale.caption)
                    .foregroundStyle(colours.mutedText)
            }
            ValueBar(fraction: total > 0 ? Double(passed) / Double(total) : 0, fill: fill)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(passed) of \(total) \(label)")
    }
}
