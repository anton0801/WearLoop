//
//  Signature.swift
//  WearLoop
//
//  The three elements that belong to this app alone: the outfit flat-lay, the
//  luggage gauge and the wear calendar.
//

import SwiftUI

// MARK: - Outfit flat-lay

/// Garments laid out in overlapping layers on a light board, as if on a table.
/// The topmost layer casts a light shadow — the only shadow in the whole app —
/// so the pile reads as having depth.
struct OutfitFlatLay: View {
    let pieces: [(piece: Piece, layer: OutfitLayer)]
    var showHalftone: Bool = true
    var height: CGFloat = 300
    /// Pieces that cannot be used right now get a berry outline.
    var unavailableIDs: Set<UUID> = []
    var onTapPiece: ((UUID) -> Void)?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .fill(Palette.surface)
                .halftoneBacking(enabled: showHalftone, opacity: 0.16, focus: .center, spacing: 30)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))

            if pieces.isEmpty {
                VStack(spacing: 6) {
                    Text("nothing on the board yet")
                        .font(TypeScale.sectionTitle)
                        .tracking(TypeScale.sectionTitleTracking)
                        .foregroundStyle(Palette.anchor.opacity(0.35))
                    Text("Add a piece to a layer below.")
                        .font(TypeScale.caption)
                        .foregroundStyle(Palette.anchor.opacity(0.4))
                }
                .multilineTextAlignment(.center)
                .padding(24)
            } else {
                layout
            }
        }
        .frame(height: height)
    }

    private var layout: some View {
        let ordered = pieces.sorted { $0.layer.flatLayOrder < $1.layer.flatLayOrder }

        return GeometryReader { geometry in
            // The pile has to fit the board in both directions, so the tile size
            // comes from whichever dimension is tighter.
            let inset: CGFloat = 20
            let boardWidth = max(geometry.size.width - inset * 2, 40)
            let boardHeight = max(geometry.size.height - inset * 2, 40)
            let columns = columnCount(for: ordered.count)
            let rows = Int(ceil(Double(ordered.count) / Double(columns)))
            let overlap = Metrics.flatLayOverlap

            let widthLimited = (boardWidth + CGFloat(columns - 1) * overlap) / CGFloat(columns)
            let heightLimited = (boardHeight + CGFloat(rows - 1) * overlap) / CGFloat(rows)
            let tile = max(min(widthLimited, heightLimited, 170), 44)

            ZStack {
                ForEach(Array(ordered.enumerated()), id: \.element.piece.id) { index, entry in
                    tileView(
                        entry: entry,
                        size: tile,
                        isTop: index == ordered.count - 1,
                        index: index,
                        total: ordered.count,
                        columns: columns,
                        rows: rows
                    )
                    .zIndex(Double(index))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    /// Wider piles for a few items, squarer grids for many.
    private func columnCount(for count: Int) -> Int {
        switch count {
        case 0, 1: return 1
        case 2, 3: return count
        case 4: return 2
        case 5, 6: return 3
        default: return 4
        }
    }

    private func tileView(
        entry: (piece: Piece, layer: OutfitLayer),
        size: CGFloat,
        isTop: Bool,
        index: Int,
        total: Int,
        columns: Int,
        rows: Int
    ) -> some View {
        // Pieces step across and down, overlapping their neighbours by 16pt.
        let step = size - Metrics.flatLayOverlap
        let column = index % max(columns, 1)
        let row = index / max(columns, 1)
        // A short final row is centred so the pile stays balanced.
        let isLastRow = row == rows - 1
        let itemsInRow = isLastRow ? (total - row * columns) : columns

        let xOffset = CGFloat(column) * step - CGFloat(max(itemsInRow - 1, 0)) * step / 2
        let yOffset = CGFloat(row) * step - CGFloat(rows - 1) * step / 2

        let image = PieceImage(
            photoID: entry.piece.photoID,
            fallbackColour: entry.piece.primaryColour,
            fallbackInitial: entry.piece.name.wlInitial,
            initialSize: size * 0.5
        )
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.flatLayPieceRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.flatLayPieceRadius, style: .continuous)
                .strokeBorder(
                    unavailableIDs.contains(entry.piece.id) ? Palette.berry : .clear,
                    lineWidth: 3
                )
        )
        // The only shadow in the app, and only on the top of the pile.
        .shadow(color: isTop ? Palette.anchor.opacity(0.22) : .clear, radius: 10, x: 0, y: 5)
        .rotationEffect(.degrees(Double(index % 3) - 1))
        .offset(x: xOffset, y: yOffset)

        return Group {
            if let onTapPiece {
                Button { onTapPiece(entry.piece.id) } label: { image }
                    .buttonStyle(CardPressStyle())
            } else {
                image
            }
        }
        .accessibilityLabel("\(entry.piece.name), \(entry.layer.title)")
    }
}

// MARK: - Luggage gauge

/// A tall bar that fills from the bottom with the weight of the bag. Over the
/// limit it turns red and a tag with the excess stands above it.
struct LuggageGauge: View {
    let fillFraction: Double
    let isOverLimit: Bool
    /// Text inside the gauge, e.g. "9.4 kg".
    let valueText: String
    let limitText: String?
    /// Text of the tag shown above when over the limit.
    var overText: String?
    var showHalftone: Bool = true
    var animate: Bool = true

    @State private var animatedFraction: Double = 0

    var body: some View {
        VStack(spacing: 10) {
            if isOverLimit, let overText {
                Text(overText)
                    .font(TypeScale.captionSmall)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Palette.danger)
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            ZStack(alignment: .bottom) {
                // The motif sits on the empty part of the gauge; the rising fill
                // then covers it as the bag gets heavier.
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Palette.surface)
                    .halftoneBacking(enabled: showHalftone, opacity: 0.28, focus: .top, spacing: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                // The fill rises from the bottom of the bar.
                GeometryReader { geometry in
                    let clamped = min(max(animatedFraction, 0), 1)
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Rectangle()
                            .fill(isOverLimit ? Palette.danger : Palette.amber)
                            .frame(height: geometry.size.height * clamped)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .padding(3)

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Text(valueText)
                        .font(.system(size: 20, weight: .black).monospacedDigit())
                        .foregroundStyle(Palette.anchor)
                    if let limitText {
                        Text("of \(limitText)")
                            .font(TypeScale.captionSmall)
                            .foregroundStyle(Palette.anchor.opacity(0.7))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .multilineTextAlignment(.center)
            }
            .frame(width: Metrics.luggageGaugeSize.width, height: Metrics.luggageGaugeSize.height)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Palette.anchor, lineWidth: 3)
            )
        }
        .onAppear {
            if animate {
                withAnimation(Motion.gaugeFill) { animatedFraction = fillFraction }
            } else {
                animatedFraction = fillFraction
            }
        }
        .onChange(of: fillFraction) { _, newValue in
            withAnimation(animate ? Motion.gaugeFill : nil) { animatedFraction = newValue }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            limitText.map { "Estimated \(valueText) of a \($0) limit" } ?? "Estimated \(valueText)"
        )
        .accessibilityValue(isOverLimit ? (overText ?? "Over the limit") : "Within the limit")
    }
}

// MARK: - Wear calendar

/// A day in the wear calendar strip.
struct WearCalendarDay: Identifiable, Hashable {
    var id: Date { date }
    var date: Date
    /// Confirmed worn — filled amber.
    var isWorn: Bool
    /// Planned but not yet worn — berry outline.
    var isPlanned: Bool
    var isToday: Bool
}

/// A horizontal strip of days: worn days are filled amber, planned days carry a
/// 3pt berry outline.
struct WearCalendarStrip: View {
    let days: [WearCalendarDay]
    var onTapDay: ((Date) -> Void)?
    var selectedDate: Date?

    @Environment(\.wlDarkSurface) private var isDark

    var body: some View {
        let colours = SurfaceColours.forDark(isDark)
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(days) { day in
                        dayView(day, colours: colours)
                            .id(day.date)
                    }
                }
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.vertical, 4)
            }
            .task {
                // The scroll target only exists once the row has been laid out,
                // so this settles into place over two passes.
                guard let today = days.first(where: \.isToday) else { return }
                proxy.scrollTo(today.date, anchor: .center)
                try? await Task.sleep(nanoseconds: 300_000_000)
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(today.date, anchor: .center)
                }
            }
        }
    }

    private func dayView(_ day: WearCalendarDay, colours: SurfaceColours) -> some View {
        let isSelected = selectedDate.map { Calendar.wl.isSameDay($0, day.date) } ?? false

        return Button {
            onTapDay?(day.date)
        } label: {
            VStack(spacing: 5) {
                Text(DateFormatterCache.weekdayShort.string(from: day.date).lowercased())
                    .font(TypeScale.captionSmall)
                    .foregroundStyle(colours.mutedText)

                ZStack {
                    Circle()
                        .fill(day.isWorn ? Palette.amber : (isDark ? colours.card : Palette.surface))
                    if day.isPlanned && !day.isWorn {
                        Circle().strokeBorder(Palette.berry, lineWidth: 3)
                    }
                    if isSelected {
                        Circle().strokeBorder(colours.text, lineWidth: 2)
                    }
                    Text(DateFormatterCache.dayNumber.string(from: day.date))
                        .font(.system(size: 16, weight: .black).monospacedDigit())
                        .foregroundStyle(day.isWorn ? Palette.anchor : colours.text)
                }
                .frame(width: Metrics.wearDayCircle, height: Metrics.wearDayCircle)

                // Today gets a small mark rather than a different shape.
                Circle()
                    .fill(day.isToday ? Palette.berry : .clear)
                    .frame(width: 5, height: 5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onTapDay == nil)
        .accessibilityLabel(accessibilityLabel(day))
        .accessibilityAddTraits(onTapDay == nil ? [] : .isButton)
    }

    private func accessibilityLabel(_ day: WearCalendarDay) -> String {
        var parts = [DateFormatterCache.dayMonth.string(from: day.date)]
        if day.isToday { parts.append("today") }
        if day.isWorn { parts.append("worn") }
        else if day.isPlanned { parts.append("planned") }
        else { parts.append("nothing planned") }
        return parts.joined(separator: ", ")
    }
}
