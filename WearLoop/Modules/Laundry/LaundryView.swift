//
//  LaundryView.swift
//  WearLoop
//

import SwiftUI

struct LaundryView: View {
    @StateObject var presenter: LaundryPresenter

    var body: some View {
        ScreenScaffold {
            ScreenBlock(spacing: 10) {
                ScreenHeader("laundry loop", subtitle: presenter.viewState.summaryText)
            }

            SegmentBar(items: presenter.segmentItems(), selection: $presenter.section)

            switch presenter.section {
            case .toWash: basketSection
            default: loadsSection
            }

            ScreenBlock {
                InlineNotice(text: presenter.viewState.cycleText, icon: "clock.arrow.circlepath")
            }
        }
        .sheet(isPresented: $presenter.isStartLoadPresented) {
            StartLoadSheet(
                basket: presenter.viewState.basket,
                careWarning: presenter.careWarningForBasket()
            ) { name, ids, temperature, notes in
                presenter.didStartLoad(name: name, pieceIDs: ids, temperature: temperature, notes: notes)
            }
        }
        .sheet(isPresented: $presenter.isAddToBasketPresented) {
            SelectPiecesSheet(
                title: "send to wash",
                subtitle: "Pieces leave rotation and their outfits say so at once.",
                pieces: presenter.viewState.availableToWash,
                confirmTitle: "Send to Wash"
            ) { ids in
                presenter.didSelectPiecesToWash(ids)
            }
        }
        .toast($presenter.toast)
        .confirm($presenter.confirm)
        .onAppear { presenter.onAppear() }
    }

    // MARK: To wash

    @ViewBuilder
    private var basketSection: some View {
        if presenter.viewState.basket.isEmpty {
            ScreenBlock {
                EmptyStateView(
                    title: "nothing waiting",
                    message: "Send a piece to the wash from its own screen, or pick several here.",
                    actionTitle: presenter.viewState.availableToWash.isEmpty ? nil : "Choose Pieces to Wash",
                    action: presenter.viewState.availableToWash.isEmpty ? nil : { presenter.didTapAddToBasket() },
                    secondaryActionTitle: "Open Wardrobe",
                    secondaryAction: { presenter.didTapWardrobe() },
                    showHalftone: presenter.viewState.showHalftone
                )
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                RailSection(
                    title: "to wash",
                    accent: Palette.berry,
                    actionTitle: "Add",
                    action: { presenter.didTapAddToBasket() },
                    items: presenter.viewState.basket
                ) { piece in
                    PieceCard(
                        piece: piece,
                        statusText: piece.material.wlIsBlank ? piece.category.title : piece.material,
                        width: Metrics.railCardWidth
                    ) {
                        presenter.didTapPiece(piece.id)
                    }
                }

                ScreenBlock(spacing: 10) {
                    if let warning = presenter.careWarningForBasket() {
                        WarningPanel(message: warning, tint: Palette.berry)
                    }
                    PrimaryButton(title: "Start a Load") { presenter.didTapStartLoad() }
                    SecondaryButton(title: "Put Everything Back") { presenter.didTapEmptyBasket() }
                }
            }
        }
    }

    // MARK: Loads

    @ViewBuilder
    private var loadsSection: some View {
        if presenter.viewState.loads.isEmpty {
            ScreenBlock {
                EmptyStateView(
                    title: emptyTitle,
                    message: emptyMessage,
                    actionTitle: presenter.section == .washingNow && !presenter.viewState.basket.isEmpty ? "Start a Load" : nil,
                    action: presenter.section == .washingNow && !presenter.viewState.basket.isEmpty
                        ? { presenter.didTapStartLoad() } : nil,
                    showHalftone: presenter.viewState.showHalftone
                )
            }
        } else {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(presenter.viewState.loads) { item in
                    loadCard(item)
                }
                if presenter.section == .readyToReturn && presenter.viewState.readyPieceIDs.count > 1 {
                    ScreenBlock {
                        PrimaryButton(
                            title: "Return All \(Plural.count(presenter.viewState.readyPieceIDs.count, "Piece"))"
                        ) {
                            presenter.didTapReturnAll()
                        }
                    }
                }
            }
        }
    }

    private func loadCard(_ item: LaundryLoadItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ScreenBlock(spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(TypeScale.bodyBold)
                            .foregroundStyle(Palette.anchor)
                        Text(item.detail)
                            .font(TypeScale.captionSmall)
                            .foregroundStyle(Palette.anchor.opacity(0.6))
                    }
                    Spacer(minLength: 8)
                    if let expected = item.expectedText {
                        Text(expected)
                            .font(TypeScale.captionSmall)
                            .foregroundStyle(item.isOverdue ? Palette.danger : Palette.anchor.opacity(0.6))
                            .multilineTextAlignment(.trailing)
                    }
                }
                if let warning = item.careWarning {
                    WarningPanel(message: warning, tint: Palette.berry)
                }
                if !item.notes.wlIsBlank {
                    InlineNotice(text: item.notes, icon: "text.alignleft")
                }
            }

            CardRail(items: item.pieces, height: 180) { piece in
                PieceCard(
                    piece: piece,
                    statusText: piece.category.title,
                    showTag: false,
                    height: 180,
                    width: 130
                ) {
                    presenter.didTapPiece(piece.id)
                }
            }

            ScreenBlock(spacing: 8) {
                PrimaryButton(title: advanceTitle(item.stage)) {
                    presenter.didTapAdvance(item)
                }
                if item.stage == .readyToReturn {
                    Text("Returning puts every piece back in rotation and closes its laundry record.")
                        .font(TypeScale.captionSmall)
                        .foregroundStyle(Palette.anchor.opacity(0.55))
                }
            }
        }
    }

    private func advanceTitle(_ stage: LaundryStage) -> String {
        switch stage {
        case .toWash: return "Start Washing"
        case .washingNow: return "Mark as Dry"
        case .drying: return "Ready to Return"
        case .readyToReturn: return "Return to Wardrobe"
        }
    }

    private var emptyTitle: String {
        switch presenter.section {
        case .washingNow: return "nothing washing"
        case .drying: return "nothing drying"
        case .readyToReturn: return "nothing to return"
        case .toWash: return "nothing waiting"
        }
    }

    private var emptyMessage: String {
        switch presenter.section {
        case .washingNow:
            return presenter.viewState.basket.isEmpty
                ? "Send pieces to the wash first, then start a load."
                : "You have \(Plural.count(presenter.viewState.basket.count, "piece")) waiting. Start a load to get going."
        case .drying:
            return "Nothing is drying. A load moves here once you mark it as washed."
        case .readyToReturn:
            return "Nothing is dry and waiting. Loads arrive here when you mark them as dry."
        case .toWash:
            return "Nothing is waiting to be washed."
        }
    }
}

// MARK: - Start load sheet

struct StartLoadSheet: View {
    let basket: [Piece]
    var careWarning: String?
    let onStart: (String, [UUID], Int, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selected: Set<UUID> = []
    @State private var temperature = 30
    @State private var notes = ""
    @State private var error: String?
    @State private var didAcceptWarning = false

    /// Recomputed for the chosen subset, not the whole basket.
    private var selectedPieces: [Piece] { basket.filter { selected.contains($0.id) } }

    private var subsetWarning: String? {
        guard selectedPieces.count > 1 else { return nil }
        let notes = selectedPieces
            .map { $0.careNotes.wlTrimmed.lowercased() }
            .filter { !$0.isEmpty }
            .wlUnique
        guard notes.count > 1 else { return nil }
        return "\(Plural.count(notes.count, "piece")) in this load have different care notes."
    }

    var body: some View {
        NavigationStack {
            ScreenScaffold {
                ScreenBlock(spacing: 20) {
                    ScreenHeader("start a load", subtitle: "Choose what goes in together.")

                    FieldFrame(label: "Load Name") {
                        WLTextField(placeholder: "Dark colours", text: $name)
                    }

                    FieldFrame(
                        label: "Pieces",
                        isRequired: true,
                        errorMessage: error
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Button(selected.count == basket.count ? "Deselect All" : "Select All") {
                                    selected = selected.count == basket.count ? [] : Set(basket.map(\.id))
                                }
                                .buttonStyle(CompactOutlineButtonStyle())
                                Text("\(selected.count) of \(basket.count)")
                                    .font(TypeScale.captionSmall)
                                    .foregroundStyle(Palette.anchor.opacity(0.55))
                                Spacer(minLength: 0)
                            }

                            LazyVGrid(
                                columns: [GridItem(.flexible(), spacing: Metrics.cardGap),
                                          GridItem(.flexible(), spacing: Metrics.cardGap)],
                                spacing: Metrics.cardGap
                            ) {
                                ForEach(basket) { piece in
                                    PieceCard(
                                        piece: piece,
                                        statusText: piece.material.wlIsBlank ? piece.category.title : piece.material,
                                        showTag: false,
                                        isSelected: selected.contains(piece.id),
                                        height: 170
                                    ) {
                                        if selected.contains(piece.id) {
                                            selected.remove(piece.id)
                                        } else {
                                            selected.insert(piece.id)
                                            error = nil
                                        }
                                    }
                                }
                            }
                        }
                    }

                    FieldFrame(label: "Temperature") {
                        WLStepper(
                            label: "Wash at",
                            value: $temperature,
                            range: 0...95,
                            step: 5,
                            valueText: "\(temperature) °C"
                        )
                    }

                    FieldFrame(label: "Notes") {
                        WLTextEditor(placeholder: "Anything about this load", text: $notes, minHeight: 70)
                    }

                    if let warning = subsetWarning, !didAcceptWarning {
                        WarningPanel(
                            message: warning,
                            primaryTitle: "Split the Load",
                            primaryAction: {
                                // Keep only the pieces sharing the first care note.
                                let firstNote = selectedPieces
                                    .map { $0.careNotes.wlTrimmed.lowercased() }
                                    .first { !$0.isEmpty } ?? ""
                                selected = Set(
                                    selectedPieces
                                        .filter { $0.careNotes.wlTrimmed.lowercased() == firstNote }
                                        .map(\.id)
                                )
                            },
                            secondaryTitle: "Continue Anyway",
                            secondaryAction: { didAcceptWarning = true },
                            tint: Palette.berry
                        )
                    }

                    PrimaryButton(title: "Start a Load") {
                        guard !selected.isEmpty else {
                            error = "Choose at least one piece for this load."
                            return
                        }
                        onStart(name, Array(selected), temperature, notes)
                    }
                    SecondaryButton(title: "Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            selected = Set(basket.map(\.id))
            if name.isEmpty {
                name = "Load \(DateFormatterCache.dayMonth.string(from: Date()))"
            }
        }
    }
}

// MARK: - Piece multi-select

/// Reusable multi-select over a list of pieces.
struct SelectPiecesSheet: View {
    let title: String
    var subtitle: String?
    let pieces: [Piece]
    var confirmTitle: String = "Confirm"
    var preselected: Set<UUID> = []
    let onConfirm: ([UUID]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<UUID> = []
    @State private var search = ""

    private var filtered: [Piece] {
        guard !search.wlIsBlank else { return pieces }
        let needle = search.wlTrimmed.lowercased()
        return pieces.filter { $0.searchHaystack.contains(needle) }
    }

    var body: some View {
        NavigationStack {
            ScreenScaffold {
                ScreenBlock(spacing: 10) {
                    ScreenHeader(title, subtitle: subtitle)
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Palette.anchor.opacity(0.45))
                        TextField("Search", text: $search)
                            .font(TypeScale.body)
                            .foregroundStyle(Palette.anchor)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.surface))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Palette.anchor.opacity(0.2), lineWidth: 2)
                    )
                }

                if filtered.isEmpty {
                    ScreenBlock {
                        EmptyStateView(
                            title: pieces.isEmpty ? "nothing available" : "nothing matches",
                            message: pieces.isEmpty
                                ? "There are no pieces in rotation to choose from."
                                : "No piece matches that search."
                        )
                    }
                } else {
                    ScreenBlock(spacing: 12) {
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: Metrics.cardGap),
                                      GridItem(.flexible(), spacing: Metrics.cardGap)],
                            spacing: Metrics.cardGap
                        ) {
                            ForEach(filtered) { piece in
                                PieceCard(
                                    piece: piece,
                                    statusText: piece.category.title,
                                    showTag: false,
                                    isSelected: selected.contains(piece.id),
                                    height: 180
                                ) {
                                    if selected.contains(piece.id) {
                                        selected.remove(piece.id)
                                    } else {
                                        selected.insert(piece.id)
                                    }
                                }
                            }
                        }

                        PrimaryButton(
                            title: selected.isEmpty ? confirmTitle : "\(confirmTitle) (\(selected.count))",
                            isEnabled: !selected.isEmpty
                        ) {
                            onConfirm(Array(selected))
                        }
                        SecondaryButton(title: "Cancel") { dismiss() }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Palette.anchor)
                }
            }
        }
        .onAppear { selected = preselected }
    }
}
