//
//  PieceCard.swift
//  WearLoop
//
//  A card is a photograph, not a white box with a photo inside it. The image
//  fills the card edge to edge and is never tinted or darkened. When there is no
//  photograph the card becomes a solid block in the garment's own colour with a
//  large initial.
//

import SwiftUI

// MARK: - Photo

/// Loads a stored photograph. The image is drawn exactly as it was taken.
struct PieceImage: View {
    let photoID: String?
    let fallbackColour: PieceColour
    let fallbackInitial: String
    /// Point size of the initial on the generated cover.
    var initialSize: CGFloat = 72

    @EnvironmentObject private var store: WardrobeStore
    @State private var image: UIImage?
    @State private var didAttemptLoad = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if photoID != nil && !didAttemptLoad {
                // Brief placeholder while the file is read from disk.
                Rectangle()
                    .fill(Palette.surface)
                    .overlay(ProgressView().tint(Palette.anchor.opacity(0.4)))
            } else {
                generatedCover
            }
        }
        .clipped()
        .task(id: photoID) { load() }
    }

    /// Solid block in the garment's colour with its initial at 30%.
    private var generatedCover: some View {
        Rectangle()
            .fill(fallbackColour.colour)
            .overlay(
                Text(fallbackInitial)
                    .font(.system(size: initialSize, weight: .black))
                    .foregroundStyle(
                        (fallbackColour.prefersLightText ? Color.white : Palette.anchor).opacity(0.3)
                    )
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
            )
    }

    private func load() {
        guard let photoID else {
            image = nil
            didAttemptLoad = true
            return
        }
        didAttemptLoad = false
        let loaded = store.photo(photoID)
        image = loaded
        didAttemptLoad = true
    }
}

// MARK: - Status tag

/// The tag pinned to the top-right of a photograph: a rectangle with a bevelled
/// bottom edge, solid fill, uppercase white text.
struct StatusTagShape: Shape {
    /// How far the bottom edge slopes.
    var bevel: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + bevel, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - bevel))
        path.closeSubpath()
        return path
    }
}

struct StatusTag: View {
    let text: String
    let fill: Color
    var textColour: Color = .white

    var body: some View {
        Text(text.uppercased())
            .font(TypeScale.tag)
            .tracking(0.4)
            .foregroundStyle(textColour)
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .padding(.bottom, 6)
            .background(StatusTagShape().fill(fill))
            .accessibilityLabel(text)
    }
}

extension PieceStatus {
    /// Tag colour: amber in rotation, berry in the wash, red for repair.
    var tagColour: Color {
        switch self {
        case .inRotation: return Palette.amber
        case .inWash: return Palette.berry
        case .needsRepair: return Palette.danger
        case .storedAway: return Palette.anchor
        case .archived: return Palette.anchor.opacity(0.75)
        }
    }

    var tagTextColour: Color {
        self == .inRotation ? Palette.anchor : .white
    }
}

// MARK: - Piece card

struct PieceCard: View {
    let piece: Piece
    /// Line under the name inside the plaque.
    var statusText: String?
    var showTag: Bool = true
    /// Corner mark for selection, used by pickers.
    var isSelected: Bool = false
    /// Dims the card when the piece cannot be used.
    var isDimmed: Bool = false
    var height: CGFloat = Metrics.railHeight
    var width: CGFloat?
    var onTap: (() -> Void)?

    var body: some View {
        let content = ZStack(alignment: .topTrailing) {
            // The photograph fills the whole card.
            PieceImage(
                photoID: piece.photoID,
                fallbackColour: piece.primaryColour,
                fallbackInitial: piece.name.wlInitial,
                initialSize: height > 150 ? 72 : 48
            )

            if showTag {
                StatusTag(
                    text: piece.status.tagText,
                    fill: piece.status.tagColour,
                    textColour: piece.status.tagTextColour
                )
                .padding(.trailing, 10)
            }

            // The plaque sits at the bottom, rounded only on its lower corners.
            VStack {
                Spacer(minLength: 0)
                plaque
            }

            if isSelected {
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(Palette.berry, lineWidth: 4)
                VStack {
                    Spacer(minLength: 0)
                    HStack {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(Palette.onAnchor)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Palette.berry))
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .padding(.bottom, 44)
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .opacity(isDimmed ? 0.5 : 1)

        Group {
            if let onTap {
                Button(action: onTap) { content }
                    .buttonStyle(CardPressStyle())
            } else {
                content
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(onTap != nil ? .isButton : [])
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var plaque: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(piece.name)
                .font(TypeScale.cardTitle)
                .foregroundStyle(Palette.onAnchor)
                .lineLimit(1)
            if let statusText {
                Text(statusText)
                    .font(TypeScale.cardSubtitle)
                    .foregroundStyle(Palette.onAnchor.opacity(0.75))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            // Rounded on the bottom only, to sit flush with the photo above.
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: Metrics.cardRadius,
                bottomTrailingRadius: Metrics.cardRadius,
                topTrailingRadius: 0,
                style: .continuous
            )
            .fill(Palette.plaque)
        )
    }

    private var accessibilityText: String {
        var parts = [piece.name, piece.category.title, piece.status.title]
        if let statusText { parts.append(statusText) }
        return parts.joined(separator: ", ")
    }
}

/// Cards shrink slightly when tapped, like the buttons do.
struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.buttonPress, value: configuration.isPressed)
    }
}

// MARK: - Outfit card

/// An outfit shown as the overlapping stack of its pieces.
struct OutfitCard: View {
    let outfit: Outfit
    let pieces: [Piece]
    var status: OutfitStatus?
    var subtitle: String?
    var height: CGFloat = Metrics.railHeight
    var width: CGFloat? = Metrics.railCardWidth
    var isSelected: Bool = false
    var isDimmed: Bool = false
    var onTap: (() -> Void)?

    var body: some View {
        let content = ZStack(alignment: .topTrailing) {
            Rectangle().fill(Palette.surface)

            // A small flat-lay preview of the pieces.
            OutfitThumbnailStack(pieces: pieces, height: height)

            if let status, status != .ready {
                StatusTag(text: status.tagText, fill: status.tagFill, textColour: status.tagTextColour)
                    .padding(.trailing, 10)
            }

            VStack {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 1) {
                    Text(outfit.name)
                        .font(TypeScale.cardTitle)
                        .foregroundStyle(Palette.onAnchor)
                        .lineLimit(1)
                    Text(subtitle ?? "\(outfit.occasion.title) · \(Plural.count(outfit.items.count, "piece"))")
                        .font(TypeScale.cardSubtitle)
                        .foregroundStyle(Palette.onAnchor.opacity(0.75))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: Metrics.cardRadius,
                        bottomTrailingRadius: Metrics.cardRadius,
                        topTrailingRadius: 0,
                        style: .continuous
                    )
                    .fill(Palette.plaque)
                )
            }

            if isSelected {
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(Palette.berry, lineWidth: 4)
            }
            if outfit.isFavorite {
                VStack {
                    HStack {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(Palette.berry)
                            .padding(6)
                            .background(Circle().fill(Palette.surface))
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                }
                .padding(8)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .opacity(isDimmed ? 0.55 : 1)

        Group {
            if let onTap {
                Button(action: onTap) { content }.buttonStyle(CardPressStyle())
            } else {
                content
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(outfit.name), \(outfit.occasion.title), \(Plural.count(outfit.items.count, "piece"))\(status.map { ", \($0.title)" } ?? "")")
        .accessibilityAddTraits(onTap != nil ? .isButton : [])
    }
}

extension OutfitStatus {
    var tagText: String {
        switch self {
        case .ready: return "READY"
        case .partlyUnavailable: return "PARTLY OUT"
        case .outOfSeason: return "OFF SEASON"
        case .needsRepair: return "NEEDS REPAIR"
        }
    }

    var tagFill: Color {
        switch self {
        case .ready: return Palette.success
        case .partlyUnavailable: return Palette.berry
        case .outOfSeason: return Palette.anchor
        case .needsRepair: return Palette.danger
        }
    }

    var tagTextColour: Color { .white }
}

/// The overlapping pile of garment photos used inside an outfit card.
struct OutfitThumbnailStack: View {
    let pieces: [Piece]
    var height: CGFloat

    var body: some View {
        let ordered = pieces.sorted { $0.category.naturalLayer.flatLayOrder < $1.category.naturalLayer.flatLayOrder }
        let shown = Array(ordered.prefix(4))

        GeometryReader { geometry in
            if shown.isEmpty {
                HalftoneBackground(spacing: 20, minDiameter: 3, maxDiameter: 9)
            } else {
                ZStack {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, piece in
                        let tileSize = min(geometry.size.width, height) * 0.62
                        PieceImage(
                            photoID: piece.photoID,
                            fallbackColour: piece.primaryColour,
                            fallbackInitial: piece.name.wlInitial,
                            initialSize: tileSize * 0.5
                        )
                        .frame(width: tileSize, height: tileSize)
                        .clipShape(RoundedRectangle(cornerRadius: Metrics.flatLayPieceRadius, style: .continuous))
                        .offset(
                            x: CGFloat(index) * 14 - CGFloat(shown.count - 1) * 7,
                            y: CGFloat(index) * -10 + CGFloat(shown.count - 1) * 5 - 12
                        )
                        .rotationEffect(.degrees(Double(index) * 2 - 3))
                        .zIndex(Double(index))
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
            }
        }
    }
}
