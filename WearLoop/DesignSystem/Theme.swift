//
//  Theme.swift
//  WearLoop
//
//  Palette, type scale, metrics and motion.
//
//  The look is metallic gold: cream ground, graphite type, gold and amber for
//  everything that carries value or energy, burgundy for anything negative and
//  green reserved strictly for positive states. Surfaces read as layered,
//  embossed gold plates; circular figures read as polished medallions.
//
//  The one rule that overrides all of it: garment photographs are never tinted,
//  darkened or recoloured. Colour lives in the metal around them, never on the
//  cloth.
//

import SwiftUI

// MARK: - Palette

enum Palette {

    // MARK: The six colours of the palette

    /// Cream ground the whole app sits on.
    static let background = Color(hex: "#FFF2D0")
    /// Gold: underlines, rims, embossing and anything that should read as
    /// valuable. Bright, so it always carries graphite text.
    static let gold = Color(hex: "#FFD21F")
    /// Amber: active states and the primary button. The energy of the palette.
    static let amber = Color(hex: "#FF9418")
    /// Graphite: type, segments and the plaque over photographs.
    static let anchor = Color(hex: "#171717")
    /// Deep burgundy: everything negative — over the limit, needing repair,
    /// destructive actions — and the accent for trips and wear marks.
    static let burgundy = Color(hex: "#8F1717")
    /// Green is only ever allowed to mean "this is good".
    static let success = Color(hex: "#45A94D")

    // MARK: Derived

    /// Raised plate face. Lifted out of the cream so a plate reads as sitting
    /// above the ground rather than being cut out of it.
    static let surface = Color(hex: "#FFF9E4")
    /// The lighter edge of a plate, where the light catches it.
    static let plateHighlight = Color(hex: "#FFFDF4")
    /// The lower edge of a plate, in shadow.
    static let plateShade = Color(hex: "#F2DFB2")

    /// Negative states. The same burgundy, named for what it means.
    static let danger = burgundy

    /// Anchor at reduced strength, for secondary text.
    static func anchorMuted(_ opacity: Double = 0.6) -> Color { anchor.opacity(opacity) }

    /// The plaque that sits over the bottom of a photograph.
    static let plaque = anchor.opacity(0.85)

    /// Text that reads on top of graphite, burgundy or green.
    static let onAnchor = Color.white
    /// Text that reads on top of gold or amber.
    static let onGold = anchor

    // MARK: Metal

    /// Face of an embossed plate, lit from above.
    static let plateFace = LinearGradient(
        colors: [plateHighlight, surface, plateShade.opacity(0.55)],
        startPoint: .top,
        endPoint: .bottom
    )

    /// A struck gold surface: bright at the top, deeper towards the bottom.
    static let goldLeaf = LinearGradient(
        colors: [
            Color(hex: "#FFE47A"),
            gold,
            Color(hex: "#E9A800")
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Amber with the same struck-metal treatment, for the primary button.
    static let amberLeaf = LinearGradient(
        colors: [
            Color(hex: "#FFB454"),
            amber,
            Color(hex: "#E07400")
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// The rim of a medallion, catching light around its circumference.
    static let medallionRim = AngularGradient(
        colors: [
            Color(hex: "#E9A800"),
            Color(hex: "#FFE47A"),
            gold,
            Color(hex: "#C98F00"),
            Color(hex: "#FFE47A"),
            Color(hex: "#E9A800")
        ],
        center: .center
    )
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
    /// Depth of the drop shadow under an active button.
    static let buttonShadowRadius: CGFloat = 0
    static let buttonShadowOffset: CGFloat = 4
    /// Depth under a raised plate.
    static let plateShadowRadius: CGFloat = 10
    static let plateShadowOffset: CGFloat = 4
    /// Thickness of the embossed edge on a plate.
    static let plateEdge: CGFloat = 1.5
    /// Rim thickness of a circular medallion.
    static let medallionRim: CGFloat = 6

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
