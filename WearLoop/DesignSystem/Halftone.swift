//
//  Halftone.swift
//  WearLoop
//
//  The raster dot motif: circles from 4 to 12pt in amber at 20%, shrinking
//  towards the edge of the block. It sits behind empty states, behind the
//  luggage gauge and in the trip screen header — never over a photograph.
//

import SwiftUI

struct HalftoneBackground: View {
    var colour: Color = Palette.gold
    var opacity: Double = 0.2
    /// Distance between dot centres.
    var spacing: CGFloat = 26
    var minDiameter: CGFloat = 4
    var maxDiameter: CGFloat = 12
    /// Where the largest dots sit, in unit coordinates.
    var focus: UnitPoint = .center

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            guard size.width > 1, size.height > 1 else { return }

            let focusPoint = CGPoint(x: size.width * focus.x, y: size.height * focus.y)
            // Longest distance from the focus to a corner, so the falloff is
            // even whatever the shape of the block.
            let corners = [
                CGPoint(x: 0, y: 0),
                CGPoint(x: size.width, y: 0),
                CGPoint(x: 0, y: size.height),
                CGPoint(x: size.width, y: size.height)
            ]
            let maxDistance = corners
                .map { hypot($0.x - focusPoint.x, $0.y - focusPoint.y) }
                .max() ?? 1
            guard maxDistance > 0 else { return }

            let paint = GraphicsContext.Shading.color(colour.opacity(opacity))

            var y = spacing / 2
            var row = 0
            while y < size.height + spacing {
                // Offset every other row so the grid reads as a raster screen.
                let xOffset: CGFloat = row.isMultiple(of: 2) ? 0 : spacing / 2
                var x = spacing / 2 + xOffset
                while x < size.width + spacing {
                    let distance = hypot(x - focusPoint.x, y - focusPoint.y)
                    let falloff = 1 - min(distance / maxDistance, 1)
                    let diameter = minDiameter + (maxDiameter - minDiameter) * falloff
                    if diameter > 0.6 {
                        let rect = CGRect(
                            x: x - diameter / 2,
                            y: y - diameter / 2,
                            width: diameter,
                            height: diameter
                        )
                        context.fill(Circle().path(in: rect), with: paint)
                    }
                    x += spacing
                }
                y += spacing
                row += 1
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Convenience

extension View {
    /// Lays the halftone motif over a filled surface shape. It is an overlay
    /// rather than a background because the surface underneath is opaque — put
    /// behind it, the dots would never be seen. Apply this to the background
    /// shape of a block, never to the content itself.
    func halftoneBacking(
        enabled: Bool = true,
        colour: Color = Palette.gold,
        opacity: Double = 0.2,
        focus: UnitPoint = .center,
        spacing: CGFloat = 26
    ) -> some View {
        overlay(
            Group {
                if enabled {
                    HalftoneBackground(
                        colour: colour,
                        opacity: opacity,
                        spacing: spacing,
                        focus: focus
                    )
                }
            }
        )
    }
}
