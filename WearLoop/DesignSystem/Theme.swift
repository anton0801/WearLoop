//
//  Theme.swift
//  WearLoop
//
//  Palette, type scale, metrics and motion. The one rule that overrides
//  everything else: garment photographs are never tinted, darkened or
//  recoloured. Accent colour lives in section headers, tags and underlines.
//

import SwiftUI

// MARK: - Palette

enum Palette {
    /// Page background.
    static let background = Color(hex: "#FFF2D9")
    /// Raised surfaces and secondary buttons.
    static let surface = Color(hex: "#FFFBF1")
    /// Text, segments and the plaque over photographs.
    static let anchor = Color(hex: "#221E1A")
    /// Active states and section headers.
    static let amber = Color(hex: "#EFA829")
    /// Outfits, trips and wear marks.
    static let berry = Color(hex: "#A63A6B")
    static let success = Color(hex: "#4E9A5B")
    /// Over the luggage limit.
    static let danger = Color(hex: "#C0392B")

    /// Anchor at reduced strength, for secondary text.
    static func anchorMuted(_ opacity: Double = 0.6) -> Color { anchor.opacity(opacity) }

    /// The plaque that sits over the bottom of a photograph.
    static let plaque = anchor.opacity(0.85)

    /// Text that reads on top of the anchor colour.
    static let onAnchor = Color.white
}

// MARK: - Typography

enum TypeScale {
    /// Screen title: 44pt black, lowercase, very tight tracking.
    static let screenTitleSize: CGFloat = 44
    static let screenTitle = Font.system(size: screenTitleSize, weight: .black)
    static let screenTitleTracking: CGFloat = -3

    /// Section title: 24pt black, lowercase.
    static let sectionTitleSize: CGFloat = 24
    static let sectionTitle = Font.system(size: sectionTitleSize, weight: .black)
    static let sectionTitleTracking: CGFloat = -1.2

    /// Big numbers, monospaced digits.
    static let bigNumber = Font.system(size: 60, weight: .black).monospacedDigit()
    static let mediumNumber = Font.system(size: 34, weight: .black).monospacedDigit()

    static let body = Font.system(size: 16, weight: .regular)
    static let bodyBold = Font.system(size: 16, weight: .bold)
    static let caption = Font.system(size: 13, weight: .semibold)
    static let captionSmall = Font.system(size: 11, weight: .semibold)

    /// Card plaque title.
    static let cardTitle = Font.system(size: 17, weight: .bold)
    static let cardSubtitle = Font.system(size: 12, weight: .semibold)

    /// Buttons.
    static let button = Font.system(size: 17, weight: .bold)

    /// Corner tag on a photograph.
    static let tag = Font.system(size: 11, weight: .bold)

    /// Segment label.
    static let segment = Font.system(size: 15, weight: .bold)
}

// MARK: - Metrics

enum Metrics {
    static let cardRadius: CGFloat = 18
    static let flatLayPieceRadius: CGFloat = 14
    static let buttonRadius: CGFloat = 18
    static let buttonHeight: CGFloat = 56
    static let segmentHeight: CGFloat = 44
    static let segmentRadius: CGFloat = 22

    /// Cards sit flush, separated only by this gap.
    static let cardGap: CGFloat = 10
    static let screenPadding: CGFloat = 20
    static let sectionGap: CGFloat = 28

    /// Horizontal rail geometry.
    static let railHeight: CGFloat = 220
    static let railCardWidth: CGFloat = 150

    static let titleUnderlineHeight: CGFloat = 6
    static let sectionUnderlineHeight: CGFloat = 4

    /// Overlap between garments in an outfit flat-lay.
    static let flatLayOverlap: CGFloat = 16

    static let luggageGaugeSize = CGSize(width: 130, height: 180)
    static let wearDayCircle: CGFloat = 44
}

// MARK: - Motion

enum Motion {
    /// Segment fill slides across: stiffness 300, damping 24.
    static let segment = Animation.spring(response: 0.36, dampingFraction: 0.69)
    /// A piece drops into an outfit: stiffness 320, damping 20.
    static let pieceDrop = Animation.spring(response: 0.35, dampingFraction: 0.56)
    /// Luggage gauge fill rises.
    static let gaugeFill = Animation.easeOut(duration: 0.5)
    /// Into and out of the dark trip screen.
    static let tripModeFade = Animation.easeInOut(duration: 0.4)
    /// Button press shrink.
    static let buttonPress = Animation.easeOut(duration: 0.08)
    static let standard = Animation.spring(response: 0.32, dampingFraction: 0.82)

    /// Honours the user's reduce-motion preference.
    static func respecting(_ reduced: Bool, _ animation: Animation) -> Animation? {
        reduced ? nil : animation
    }
}

// MARK: - Environment

/// Lets nested views know they are drawing on the dark trip screen.
private struct DarkSurfaceKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var wlDarkSurface: Bool {
        get { self[DarkSurfaceKey.self] }
        set { self[DarkSurfaceKey.self] = newValue }
    }
}

extension View {
    func wlDarkSurface(_ isDark: Bool) -> some View {
        environment(\.wlDarkSurface, isDark)
    }
}

/// Colour pair for text on the current surface.
struct SurfaceColours {
    var text: Color
    var mutedText: Color
    var background: Color
    var card: Color
    var stroke: Color

    static let light = SurfaceColours(
        text: Palette.anchor,
        mutedText: Palette.anchor.opacity(0.6),
        background: Palette.background,
        card: Palette.surface,
        stroke: Palette.anchor
    )

    static let dark = SurfaceColours(
        text: Color.white,
        mutedText: Color.white.opacity(0.65),
        background: Palette.anchor,
        card: Color.white.opacity(0.08),
        stroke: Color.white.opacity(0.85)
    )

    static func forDark(_ isDark: Bool) -> SurfaceColours { isDark ? .dark : .light }
}
