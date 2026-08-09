//
//  Headers.swift
//  WearLoop
//
//  Screen and section titles: lowercase, heavy, with a thick underline sized to
//  the text. There are no capitalised headings anywhere in the app.
//

import SwiftUI

/// Measures how wide the text actually draws, so the underline can be exactly
/// as long as the words above it rather than as long as the column.
private enum TextMeasure {
    static func longestLineWidth(
        _ text: String,
        pointSize: CGFloat,
        weight: UIFont.Weight,
        tracking: CGFloat,
        maxWidth: CGFloat
    ) -> CGFloat {
        guard maxWidth > 1, !text.isEmpty else { return 0 }
        let font = UIFont.systemFont(ofSize: pointSize, weight: weight)
        let attributed = NSAttributedString(
            string: text,
            attributes: [.font: font, .kern: tracking]
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(
            rect: CGRect(x: 0, y: 0, width: maxWidth, height: .greatestFiniteMagnitude),
            transform: nil
        )
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        guard let lines = CTFrameGetLines(frame) as? [CTLine], !lines.isEmpty else { return maxWidth }

        var widest: CGFloat = 0
        for line in lines {
            // Trailing whitespace should not stretch the rule.
            let width = CTLineGetTypographicBounds(line, nil, nil, nil)
                - CTLineGetTrailingWhitespaceWidth(line)
            widest = max(widest, CGFloat(width))
        }
        // The kerning of the final glyph is not part of the visible run.
        widest += tracking < 0 ? -tracking : 0
        return min(widest.rounded(.up), maxWidth)
    }
}

private struct AvailableWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Lowercase heavy title with a rule underneath sized to the words themselves.
private struct UnderlinedTitle: View {
    let text: String
    let font: Font
    let pointSize: CGFloat
    let tracking: CGFloat
    let underlineHeight: CGFloat
    let underlineColour: Color
    let textColour: Color
    let lineLimit: Int

    @State private var availableWidth: CGFloat = 0

    private var lowercased: String { text.lowercased() }

    private var underlineWidth: CGFloat {
        TextMeasure.longestLineWidth(
            lowercased,
            pointSize: pointSize,
            weight: .black,
            tracking: tracking,
            maxWidth: availableWidth
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(lowercased)
                    .font(font)
                    .tracking(tracking)
                    .foregroundStyle(textColour)
                    .lineLimit(lineLimit)
                    .minimumScaleFactor(0.55)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(key: AvailableWidthKey.self, value: geometry.size.width)
                        }
                    )

                Rectangle()
                    .fill(underlineColour)
                    .frame(width: underlineWidth > 0 ? underlineWidth : nil, height: underlineHeight)
            }
            Spacer(minLength: 0)
        }
        .onPreferenceChange(AvailableWidthKey.self) { width in
            if abs(width - availableWidth) > 0.5 { availableWidth = width }
        }
    }
}

/// The 44pt screen title with its 6pt amber underline.
struct ScreenHeader: View {
    let title: String
    var subtitle: String?
    /// Trailing control, e.g. the profile button on Home.
    var trailing: AnyView?

    @Environment(\.wlDarkSurface) private var isDark

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = nil
    }

    init<Trailing: View>(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = AnyView(trailing())
    }

    var body: some View {
        let colours = SurfaceColours.forDark(isDark)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                UnderlinedTitle(
                    text: title,
                    font: TypeScale.screenTitle,
                    pointSize: TypeScale.screenTitleSize,
                    tracking: TypeScale.screenTitleTracking,
                    underlineHeight: Metrics.titleUnderlineHeight,
                    underlineColour: Palette.amber,
                    textColour: colours.text,
                    lineLimit: 2
                )
                if let trailing {
                    trailing
                        .padding(.top, 6)
                }
            }
            if let subtitle {
                Text(subtitle)
                    .font(TypeScale.body)
                    .foregroundStyle(colours.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The 24pt section title with its 4pt underline.
struct SectionHeader: View {
    let title: String
    var accent: Color = Palette.amber
    var trailing: AnyView?

    @Environment(\.wlDarkSurface) private var isDark

    init(_ title: String, accent: Color = Palette.amber) {
        self.title = title
        self.accent = accent
        self.trailing = nil
    }

    init<Trailing: View>(_ title: String, accent: Color = Palette.amber, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.accent = accent
        self.trailing = AnyView(trailing())
    }

    var body: some View {
        let colours = SurfaceColours.forDark(isDark)
        HStack(alignment: .bottom, spacing: 12) {
            UnderlinedTitle(
                text: title,
                font: TypeScale.sectionTitle,
                pointSize: TypeScale.sectionTitleSize,
                tracking: TypeScale.sectionTitleTracking,
                underlineHeight: Metrics.sectionUnderlineHeight,
                underlineColour: accent,
                textColour: colours.text,
                lineLimit: 2
            )
            if let trailing { trailing }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A large monospaced figure with its label, used for counts and weights.
struct BigNumber: View {
    let value: String
    let label: String
    var colour: Color = Palette.anchor
    var isCompact: Bool = false

    @Environment(\.wlDarkSurface) private var isDark

    var body: some View {
        let colours = SurfaceColours.forDark(isDark)
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(isCompact ? TypeScale.mediumNumber : TypeScale.bigNumber)
                .foregroundStyle(colour)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(label.lowercased())
                .font(TypeScale.caption)
                .foregroundStyle(colours.mutedText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}
