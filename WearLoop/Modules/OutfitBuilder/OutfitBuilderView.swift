//
//  OutfitBuilderView.swift
//  WearLoop
//

import SwiftUI

struct OutfitBuilderView: View {
    @StateObject var presenter: OutfitBuilderPresenter
    /// Drives the drop animation when a piece lands on the board.
    @State private var lastAddedCount = 0

    var body: some View {
        ScreenScaffold(bottomInset: 40) {
            ScreenBlock(spacing: 10) {
                ScreenHeader(
                    presenter.viewState.title,
                    subtitle: "\(Plural.count(presenter.viewState.pieceCount, "piece")) on the board"
                )
            }

            board
            layers
            details
            saveBlock
        }
        .sheet(item: Binding(
            get: { presenter.pickerLayer.map { PickerContext(layer: $0) } },
            set: { if $0 == nil { presenter.didDismissPicker() } }
        )) { context in
            PiecePickerSheet(
                layer: context.layer,
                candidates: presenter.pickerCandidates,
                isSwapping: presenter.swappingItemID != nil,
                onPick: { presenter.didPickPiece($0) },
                onAddPiece: { presenter.didTapAddPiece() }
            )
        }
        .toast($presenter.toast)
        .onAppear { presenter.onAppear() }
    }

    private struct PickerContext: Identifiable {
        var layer: OutfitLayer
        var id: String { layer.rawValue }
    }

    // MARK: Board

    private var board: some View {
        ScreenBlock(spacing: 12) {
            OutfitFlatLay(
                pieces: presenter.viewState.boardPieces,
                showHalftone: presenter.viewState.showHalftone,
                height: 320,
                unavailableIDs: presenter.viewState.unavailableIDs
            )
            .animation(Motion.pieceDrop, value: presenter.viewState.items.count)

            if !presenter.viewState.checkNotes.isEmpty {
                Panel {
                    Text("Outfit Check")
                        .font(TypeScale.captionSmall)
                        .foregroundStyle(Palette.anchor.opacity(0.55))
                    ForEach(Array(presenter.viewState.checkNotes.enumerated()), id: \.offset) { _, note in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(note.hasPrefix("All pieces") ? Palette.success : Palette.berry)
                                .frame(width: 6, height: 6)
                                .padding(.top, 7)
                            Text(note)
                                .font(TypeScale.caption)
                                .foregroundStyle(Palette.anchor)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }

            if let error = presenter.viewState.piecesError {
                WarningPanel(message: error, tint: Palette.danger)
            }
        }
    }

    // MARK: Layers

    private var layers: some View {
        VStack(alignment: .leading, spacing: 18) {
            ScreenBlock {
                SectionHeader("layers")
            }
            ForEach(OutfitLayer.allCases) { layer in
                layerRow(layer)
            }
        }
    }

    private func layerRow(_ layer: OutfitLayer) -> some View {
        let items = presenter.items(in: layer)
        return VStack(alignment: .leading, spacing: 10) {
            ScreenBlock {
                HStack {
                    Text(layer.title)
                        .font(TypeScale.bodyBold)
                        .foregroundStyle(Palette.anchor)
                    Spacer()
                    Button {
                        presenter.didTapAddToLayer(layer)
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .buttonStyle(CompactOutlineButtonStyle())
                    .accessibilityLabel("Add piece to \(layer.title)")
                }
            }

            if items.isEmpty {
                ScreenBlock {
                    InlineNotice(text: "Nothing in this layer.", icon: "square.dashed")
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Metrics.cardGap) {
                        ForEach(items) { item in
                            if let piece = presenter.pieceFor(item) {
                                VStack(spacing: 6) {
                                    PieceCard(
                                        piece: piece,
                                        statusText: piece.status.isAvailable ? piece.category.title : piece.status.title,
                                        isDimmed: !piece.status.isAvailable,
                                        height: 170,
                                        width: 130
                                    )
                                    HStack(spacing: 6) {
                                        Button("Swap") { presenter.didTapSwap(item: item) }
                                            .buttonStyle(CompactOutlineButtonStyle())
                                        Button {
                                            withAnimation(Motion.pieceDrop) {
                                                presenter.didTapRemove(item: item)
                                            }
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(CompactOutlineButtonStyle(stroke: Palette.danger, textColour: Palette.danger))
                                        .accessibilityLabel("Remove \(piece.name) from the outfit")
                                    }
                                }
                                .transition(
                                    // A piece drops in from above with a slight tilt.
                                    .asymmetric(
                                        insertion: .offset(y: -24).combined(with: .opacity),
                                        removal: .opacity
                                    )
                                )
                            }
                        }
                    }
                    .padding(.horizontal, Metrics.screenPadding)
                }
                .scrollBounceBehavior(.always, axes: .horizontal)
            }
        }
    }

    // MARK: Details

    private var details: some View {
        ScreenBlock(spacing: 22) {
            SectionHeader("outfit details")

            FieldFrame(label: "Outfit Name", isRequired: true, errorMessage: presenter.viewState.nameError) {
                WLTextField(
                    placeholder: "Monday office",
                    text: Binding(
                        get: { presenter.viewState.name },
                        set: { presenter.setName($0) }
                    ),
                    hasError: presenter.viewState.nameError != nil
                )
            }

            FieldFrame(label: "Occasion", isRequired: true, errorMessage: presenter.viewState.occasionError) {
                ChipGroup(
                    values: Occasion.allCases,
                    title: { $0.title },
                    accent: Palette.berry,
                    isSelected: { $0 == presenter.viewState.occasion },
                    onTap: { presenter.setOccasion($0) }
                )
            }

            FieldFrame(
                label: "Season",
                helpText: presenter.viewState.isSeasonManual
                    ? "Set by hand."
                    : "Worked out from the pieces. Tap to change it yourself."
            ) {
                ChipGroup(
                    values: Season.allCases,
                    title: { $0.title },
                    accent: Palette.amber,
                    isSelected: { presenter.viewState.seasons.contains($0) },
                    onTap: { presenter.toggleSeason($0) }
                )
            }

            FieldFrame(
                label: "Temperature Range",
                helpText: presenter.viewState.isRangeManual
                    ? "Set by hand."
                    : "Worked out from the seasons of the pieces."
            ) {
                TemperatureRangeControl(
                    minValue: Binding(
                        get: { presenter.viewState.temperatureMin },
                        set: { presenter.setTemperature(min: $0, max: presenter.viewState.temperatureMax) }
                    ),
                    maxValue: Binding(
                        get: { presenter.viewState.temperatureMax },
                        set: { presenter.setTemperature(min: presenter.viewState.temperatureMin, max: $0) }
                    ),
                    units: presenter.viewState.units
                )
            }

            if presenter.viewState.isRangeManual || presenter.viewState.isSeasonManual {
                SecondaryButton(title: "Recalculate From Pieces") {
                    presenter.resetDerivedValues()
                }
            }

            FieldFrame(label: "Formality Level") {
                ChipGroup(
                    values: Formality.allCases,
                    title: { $0.title },
                    accent: Palette.anchor,
                    isSelected: { $0 == presenter.viewState.formality },
                    onTap: { presenter.setFormality($0) }
                )
            }

            FieldFrame(label: "Notes") {
                WLTextEditor(
                    placeholder: "Anything worth remembering about this outfit",
                    text: Binding(
                        get: { presenter.viewState.notes },
                        set: { presenter.viewState.notes = $0 }
                    ),
                    minHeight: 84
                )
            }

            WLToggleRow(
                title: "Favourite",
                subtitle: "Favourites are preferred when the app suggests something.",
                isOn: Binding(
                    get: { presenter.viewState.isFavorite },
                    set: { presenter.viewState.isFavorite = $0 }
                )
            )

            if presenter.viewState.isEditing {
                WLToggleRow(
                    title: "Archived",
                    subtitle: "Archived outfits stay out of suggestions and plans.",
                    isOn: Binding(
                        get: { presenter.viewState.isArchived },
                        set: { presenter.viewState.isArchived = $0 }
                    )
                )
            }
        }
    }

    // MARK: Save

    private var saveBlock: some View {
        ScreenBlock(spacing: 12) {
            if let error = presenter.viewState.saveError {
                WarningPanel(message: error, tint: Palette.danger)
            }
            PrimaryButton(
                title: "Save Outfit",
                isEnabled: presenter.viewState.canSave,
                isBusy: presenter.viewState.isSaving
            ) {
                presenter.didTapSave()
            }
            if presenter.viewState.isEditing {
                SecondaryButton(title: "Duplicate Outfit") { presenter.didTapDuplicate() }
            }
            SecondaryButton(title: "Cancel") { presenter.didTapCancel() }
        }
    }
}

// MARK: - Piece picker

struct PiecePickerSheet: View {
    let layer: OutfitLayer
    let candidates: [Piece]
    var isSwapping: Bool
    let onPick: (Piece) -> Void
    var onAddPiece: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [Piece] {
        guard !search.wlIsBlank else { return candidates }
        let needle = search.wlTrimmed.lowercased()
        return candidates.filter { $0.searchHaystack.contains(needle) }
    }

    var body: some View {
        NavigationStack {
            ScreenScaffold {
                ScreenBlock(spacing: 10) {
                    ScreenHeader(
                        isSwapping ? "swap piece" : layer.title.lowercased(),
                        subtitle: "\(Plural.count(candidates.count, "piece")) can go in this layer"
                    )
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
                            title: candidates.isEmpty ? "nothing fits this layer" : "nothing matches",
                            message: candidates.isEmpty
                                ? "This layer takes \(layer.allowedCategories.map(\.title).joined(separator: " or ").lowercased()). Add one to your wardrobe first."
                                : "No piece matches that search.",
                            actionTitle: candidates.isEmpty ? "Add a Piece" : nil,
                            action: candidates.isEmpty ? { onAddPiece?(); dismiss() } : nil
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
                                    statusText: piece.status.isAvailable
                                        ? piece.category.title
                                        : unavailableText(piece),
                                    isDimmed: !piece.status.isAvailable,
                                    height: 190
                                ) {
                                    onPick(piece)
                                    dismiss()
                                }
                            }
                        }
                        Text("Pieces that are unavailable can still be added — the outfit will simply say so until they come back.")
                            .font(TypeScale.captionSmall)
                            .foregroundStyle(Palette.anchor.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
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
    }

    private func unavailableText(_ piece: Piece) -> String {
        switch piece.status {
        case .inWash:
            if let back = piece.expectedBackDate {
                return "Back \(DateFormatterCache.relativeDayText(back))"
            }
            return "In the wash"
        default:
            return piece.status.title
        }
    }
}
