//
//  PackingListView.swift
//  WearLoop
//

import SwiftUI

struct PackingListView: View {
    @StateObject var presenter: PackingListPresenter

    var body: some View {
        Group {
            if let state = presenter.viewState {
                content(state)
            } else if presenter.isMissing {
                ScreenScaffold {
                    ScreenBlock {
                        EmptyStateView(
                            title: "this trip is gone",
                            message: "It was deleted while this screen was open."
                        )
                    }
                }
            } else {
                ScreenScaffold { LoadingStateView(message: "Loading the packing list…") }
            }
        }
        .sheet(isPresented: $presenter.isAddManualPresented) {
            AddManualItemSheet { name, weight in
                presenter.didAddManual(name: name, weightGrams: weight)
            }
        }
        .sheet(isPresented: $presenter.isAddPiecePresented) {
            SelectPiecesSheet(
                title: "add from wardrobe",
                subtitle: "Pieces added here are listed as added manually.",
                pieces: presenter.availablePieces,
                confirmTitle: "Add to Trip"
            ) { presenter.didAddPieces($0) }
        }
        .sheet(isPresented: $presenter.isDayPickerPresented) {
            if let state = presenter.viewState {
                DayPickerSheet(dayNumbers: state.dayNumbers) {
                    presenter.didPackAllFromDay($0)
                }
            }
        }
        .sheet(item: $presenter.whyRow) { row in
            WhyIsThisHereSheet(row: row)
        }
        .toast($presenter.toast)
        .onAppear { presenter.onAppear() }
    }

    private func content(_ state: PackingListViewState) -> some View {
        ScreenScaffold {
            ScreenBlock(spacing: 10) {
                ScreenHeader("packing list", subtitle: "\(state.tripName) · \(state.weightText) in the bag")
            }

            SegmentBar(items: presenter.segmentItems(), selection: $presenter.section)

            ScreenBlock(spacing: 10) {
                CountProgress(
                    passed: state.packedCount,
                    total: state.totalCount,
                    label: "items packed",
                    fill: state.packedCount == state.totalCount && state.totalCount > 0 ? Palette.success : Palette.amber
                )
                HStack(spacing: 8) {
                    Button("Add Item") { presenter.didTapAddManual() }
                        .buttonStyle(CompactOutlineButtonStyle())
                    Button("Add From Wardrobe") { presenter.didTapAddPiece() }
                        .buttonStyle(CompactOutlineButtonStyle())
                    if !state.dayNumbers.isEmpty {
                        Button("Pack a Day") { presenter.didTapPackFromDay() }
                            .buttonStyle(CompactOutlineButtonStyle())
                    }
                    Spacer(minLength: 0)
                }
            }

            rowsSection(state)

            ScreenBlock(spacing: 10) {
                if state.isOverLimit {
                    WarningPanel(
                        message: "The bag is over its limit at \(state.weightText). The weight check names what to leave behind.",
                        primaryTitle: "Open the Weight Check",
                        primaryAction: { presenter.didTapContinue() }
                    )
                }
                PrimaryButton(title: "Continue to the Weight Check", isEnabled: state.canContinue) {
                    presenter.didTapContinue()
                }
            }
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func rowsSection(_ state: PackingListViewState) -> some View {
        if state.rows.isEmpty {
            ScreenBlock {
                EmptyStateView(
                    title: emptyTitle,
                    message: emptyMessage(state),
                    actionTitle: emptyAction,
                    action: emptyActionHandler,
                    showHalftone: state.showHalftone
                )
            }
        } else {
            ScreenBlock(spacing: 8) {
                ForEach(state.rows) { row in
                    packingRow(row)
                }
            }
        }
    }

    private func packingRow(_ row: PackingRow) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // Tick box
            Button {
                presenter.didTogglePacked(row)
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(row.isPacked ? Palette.success : Palette.surface)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(row.isPacked ? Palette.success : Palette.anchor.opacity(0.3), lineWidth: 2)
                    if row.isPacked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .disabled(row.isNotPacking)
            .accessibilityLabel(row.isPacked ? "Packed, \(row.name)" : "Not packed, \(row.name)")
            .accessibilityAddTraits(row.isPacked ? [.isButton, .isSelected] : .isButton)

            // Thumbnail
            if let piece = row.piece {
                PieceImage(
                    photoID: piece.photoID,
                    fallbackColour: piece.primaryColour,
                    fallbackInitial: piece.name.wlInitial,
                    initialSize: 22
                )
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(TypeScale.bodyBold)
                    .foregroundStyle(Palette.anchor)
                    .strikethrough(row.isNotPacking, color: Palette.anchor.opacity(0.5))
                    .lineLimit(1)
                Text(row.reason)
                    .font(TypeScale.captionSmall)
                    .foregroundStyle(Palette.anchor.opacity(0.55))
                    .lineLimit(1)
                if let unavailable = row.unavailableText {
                    Text(unavailable)
                        .font(TypeScale.captionSmall)
                        .foregroundStyle(Palette.berry)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                Text(row.weightText)
                    .font(TypeScale.captionSmall.monospacedDigit())
                    .foregroundStyle(Palette.anchor.opacity(0.7))
                if row.isWeightEstimated {
                    Text("estimate")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.anchor.opacity(0.4))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(row.isNotPacking ? Palette.surface.opacity(0.5) : Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(row.isUnavailable ? Palette.berry.opacity(0.6) : .clear, lineWidth: 2)
        )
        .contextMenu {
            Button { presenter.didTapWhy(row) } label: {
                Label("Why Is This Here?", systemImage: "questionmark.circle")
            }
            if let pieceID = row.pieceID {
                Button { presenter.didTapPiece(pieceID) } label: {
                    Label("Open Piece", systemImage: "arrow.up.right.square")
                }
            }
            Button { presenter.didTapNotPacking(row) } label: {
                Label(row.isNotPacking ? "Put Back on the List" : "Not Packing", systemImage: "xmark.circle")
            }
            if row.source != .fromOutfits {
                Button(role: .destructive) { presenter.didTapRemove(row) } label: {
                    Label("Remove From Trip", systemImage: "trash")
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Empty text

    private var emptyTitle: String {
        switch presenter.section {
        case .fromOutfits: return "nothing from outfits"
        case .manual: return "nothing added by hand"
        case .essentials: return "no essentials"
        case .notPacking: return "nothing set aside"
        }
    }

    private func emptyMessage(_ state: PackingListViewState) -> String {
        switch presenter.section {
        case .fromOutfits:
            return "Assign outfits to the trip days and everything they need appears here automatically."
        case .manual:
            return "Add anything the outfits do not cover: a swimsuit, a spare jumper, a book."
        case .essentials:
            return state.hasEssentialsList
                ? "Your essentials have not been added to this trip yet."
                : "Your essentials list is empty. Set it up once and it travels with every trip."
        case .notPacking:
            return "Nothing has been set aside. Items you decide against stay here rather than disappearing."
        }
    }

    private var emptyAction: String? {
        switch presenter.section {
        case .manual: return "Add an Item"
        case .essentials: return "Open the Essentials List"
        default: return nil
        }
    }

    private func emptyActionHandler() {
        switch presenter.section {
        case .manual: presenter.didTapAddManual()
        case .essentials: presenter.didTapEssentialsList()
        default: break
        }
    }
}

// MARK: - Add manual item

struct AddManualItemSheet: View {
    let onAdd: (String, Double?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var weight: Double?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScreenScaffold {
                ScreenBlock(spacing: 20) {
                    ScreenHeader("add an item", subtitle: "Anything that is not a wardrobe piece.")

                    FieldFrame(label: "Name", isRequired: true, errorMessage: error) {
                        WLTextField(placeholder: "Swimming goggles", text: $name, hasError: error != nil)
                    }

                    FieldFrame(label: "Weight", helpText: "Optional, but it keeps the bag estimate honest.") {
                        WLNumberField(placeholder: "Not entered", value: $weight, suffix: "g")
                    }

                    PrimaryButton(title: "Add to Trip") {
                        guard !name.wlIsBlank else {
                            error = "Enter a name to continue."
                            return
                        }
                        onAdd(name, weight)
                    }
                    SecondaryButton(title: "Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Day picker

struct DayPickerSheet: View {
    let dayNumbers: [Int]
    let onPick: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScreenScaffold {
                ScreenBlock(spacing: 14) {
                    ScreenHeader("pack a day", subtitle: "Ticks off everything a single day needs.")
                    ForEach(dayNumbers, id: \.self) { day in
                        NavigationRow(title: "Day \(day)", icon: "calendar") {
                            onPick(day)
                        }
                    }
                    SecondaryButton(title: "Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Why is this here

struct WhyIsThisHereSheet: View {
    let row: PackingRow

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScreenScaffold {
                ScreenBlock(spacing: 16) {
                    ScreenHeader("why is this here?", subtitle: row.name)

                    Panel {
                        Text(row.reason)
                            .font(TypeScale.body)
                            .foregroundStyle(Palette.anchor)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Panel {
                        FactRow(label: "Source", value: row.source.title)
                        Divider().overlay(Palette.anchor.opacity(0.1))
                        FactRow(label: "Weight", value: row.weightText)
                        if row.isWeightEstimated {
                            Divider().overlay(Palette.anchor.opacity(0.1))
                            FactRow(
                                label: "Estimate",
                                value: row.pieceID == nil
                                    ? "No weight entered for this item"
                                    : "Category average used"
                            )
                        }
                        if let unavailable = row.unavailableText {
                            Divider().overlay(Palette.anchor.opacity(0.1))
                            FactRow(label: "Availability", value: unavailable, valueColour: Palette.berry)
                        }
                    }

                    SecondaryButton(title: "Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
