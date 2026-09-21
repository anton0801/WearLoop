//
//  Metal.swift
//  WearLoop
//
//  The material of the interface: layered, embossed gold plates for anything
//  that holds information, and polished medallions for circular figures.
//
//  The treatment is decorative but never decorative-only — a plate always has
//  content on it, and a medallion always shows a real count. Photographs are
//  never given any of this: cloth stays cloth.
//

import SwiftUI

// MARK: - Plates

/// A raised, embossed plate. Light lands along the top edge in gold, the lower
/// edge falls into shade, and a struck line sits just inside the rim, so the
/// card reads as several layers of metal rather than one flat rectangle.
struct PlateBackground: View {
    var cornerRadius: CGFloat = Metrics.cardRadius
    /// A plate can sit flush when it is inside another plate.
    var isRaised: Bool = true
    /// Tints the face, used by warning and success panels.
    var tint: Color?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        shape
            .fill(Palette.plateFace)
            .overlay(shape.fill(tint?.opacity(0.10) ?? .clear))
            .overlay(
                // The struck line inside the rim: the second layer of metal.
                shape
                    .inset(by: 5)
                    .strokeBorder(Palette.gold.opacity(0.20), lineWidth: 1)
            )
            .overlay(
                // The embossed edge itself: gold where the light hits, shade below.
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            Palette.gold.opacity(0.65),
                            Palette.plateHighlight,
                            Palette.plateShade
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: Metrics.plateEdge
                )
            )
            .shadow(
                color: isRaised ? Palette.anchor.opacity(0.13) : .clear,
                radius: Metrics.plateShadowRadius,
                x: 0,
                y: Metrics.plateShadowOffset
            )
    }
}

extension View {
    /// Puts the view on a raised gold plate.
    func goldPlate(
        cornerRadius: CGFloat = Metrics.cardRadius,
        isRaised: Bool = true,
        tint: Color? = nil
    ) -> some View {
        background(PlateBackground(cornerRadius: cornerRadius, isRaised: isRaised, tint: tint))
    }
}

// MARK: - Sheen

/// The light on a struck metal surface: bright along the top, falling away
/// towards the bottom. Laid over a solid fill so amber, burgundy and green all
/// read as the same material.
enum Metal {
    static let sheen = LinearGradient(
        colors: [
            Color.white.opacity(0.30),
            Color.white.opacity(0.06),
            Color.black.opacity(0.07)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - Medallions

/// A polished medallion: a gold rim catching light around its circumference,
/// a cream face, and a figure struck into the middle.
struct Medallion: View {
    let value: String
    var label: String?
    var diameter: CGFloat = 132
    /// Filled portion of the rim, 0...1. Nil leaves the rim solid.
    var progress: Double?
    /// Colour of the filled portion. Green only ever means "good".
    var progressColour: Color = Palette.amber
    var valueColour: Color = Palette.anchor

    var body: some View {
        ZStack {
            // The face. It carries the shadow on its own, so the figure struck
            // into the middle is never given a ghost of itself.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Palette.plateHighlight, Palette.surface, Palette.plateShade.opacity(0.7)],
                        center: .init(x: 0.35, y: 0.28),
                        startRadius: 2,
                        endRadius: diameter * 0.72
                    )
                )
                .shadow(color: Palette.anchor.opacity(0.16), radius: 10, x: 0, y: 5)

            // The rim, struck all the way round.
            Circle()
                .strokeBorder(Palette.medallionRim, lineWidth: Metrics.medallionRim)

            // How far along the figure is, drawn over the rim.
            if let progress {
                Circle()
                    .inset(by: Metrics.medallionRim / 2)
                    .trim(from: 0, to: min(max(progress, 0), 1))
                    .stroke(
                        progressColour,
                        style: StrokeStyle(lineWidth: Metrics.medallionRim, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }

            // A hairline inside the rim, so the metal reads as layered.
            Circle()
                .inset(by: Metrics.medallionRim + 3)
                .strokeBorder(Palette.gold.opacity(0.35), lineWidth: 1)

            VStack(spacing: 1) {
                Text(value)
                    .font(.system(size: diameter * 0.28, weight: .black).monospacedDigit())
                    .foregroundStyle(valueColour)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                if let label {
                    Text(label.lowercased())
                        .font(.system(size: max(diameter * 0.095, 10), weight: .semibold))
                        .foregroundStyle(Palette.anchor.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .padding(.horizontal, diameter * 0.16)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.map { "\(value) \($0)" } ?? value)
    }
}

/// The medallion used for "3 of 6 checks passed" style figures.
struct CountMedallion: View {
    let passed: Int
    let total: Int
    var label: String
    var diameter: CGFloat = 132

    var body: some View {
        let fraction = total > 0 ? Double(passed) / Double(total) : 0
        Medallion(
            value: "\(passed)/\(total)",
            label: label,
            diameter: diameter,
            progress: fraction,
            progressColour: passed == total && total > 0 ? Palette.success : Palette.amber
        )
        .accessibilityLabel("\(passed) of \(total) \(label)")
    }
}
