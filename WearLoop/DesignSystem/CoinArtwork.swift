import SwiftUI

/// Decorative assets only. They never encode state or replace a control.
enum CoinArtwork: String, CaseIterable {
    case home, wardrobe, camera, outfits, trips, planner, laundry
    case repairs, events, templates, insights, packing, weight, settings

    var assetName: String { "coin-emblem-\(rawValue)" }

    static func onboardingAsset(for page: Int) -> String {
        let names = ["wardrobe", "pieces", "outfits", "travel"]
        return "coin-onboarding-\(names[min(max(page, 0), names.count - 1)])"
    }
}

struct CoinEmblem: View {
    let artwork: CoinArtwork
    var size: CGFloat = 64

    var body: some View {
        Image(artwork.assetName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .background(Color(hex: "#280B12"))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                    .strokeBorder(Palette.medallionRim, lineWidth: 1.5)
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

/// Uses the parent's proposed size and cannot widen a scroll view or intercept taps.
struct CoinOnboardingBackdrop: View {
    let page: Int

    var body: some View {
        GeometryReader { geometry in
            Image(CoinArtwork.onboardingAsset(for: page))
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                .clipped()
                .overlay {
                    LinearGradient(
                        colors: [.black.opacity(0.15), .clear, Color(hex: "#18070B").opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
