//
//  OutfitDetailsView.swift
//  WearLoop
//

import SwiftUI

struct OutfitDetailsView: View {
    @StateObject var presenter: OutfitDetailsPresenter

    var body: some View {
        Group {
            if let state = presenter.viewState {
                content(state)
            } else if presenter.isMissing {
                missing
            } else {
                ScreenScaffold { LoadingStateView(message: "Loading this outfit…") }
            }
        }
        .toast($presenter.toast)
        .confirm($presenter.confirm)
        .sheet(isPresented: $presenter.isMarkWornPresented) {
            if let state = presenter.viewState {
                MarkWornSheet(outfitName: state.outfit.name, pieceCount: state.pieces.count) { sendToWash in
                    presenter.didConfirmMarkWorn(sendToWash: sendToWash)
                }
            }
        }
        .onAppear { presenter.onAppear() }
    }

    private var missing: some View {
        ScreenScaffold {
            ScreenBlock {
                EmptyStateView(
                    title: "this outfit is gone",
                    message: "It was deleted. Wear records that used it keep its name in their own history.",
                    actionTitle: "Back to Outfits",
                    action: { presenter.didTapBack() }
                )
            }
        }
    }

    private func content(_ state: OutfitDetailsViewState) -> some View {
        ScreenScaffold {
            ScreenBlock(spacing: 12) {
                ScreenHeader(state.outfit.name, subtitle: subtitleText(state))

                OutfitFlatLay(
                    pieces: state.pieces,
                    showHalftone: state.showHalftone,
                    height: 320,
                    unavailableIDs: state.unavailableIDs,
                    onTapPiece: { presenter.didTapPiece($0) }
                )
            }

            checkSection(state)
            actionsSection(state)
            piecesSection(state)
            plannedSection(state)
            historySection(state)
            dangerSection(state)
        }
    }

    private func subtitleText(_ state: OutfitDetailsViewState) -> String {
        var parts = [state.outfit.occasion.title, state.outfit.formality.title]
        parts.append(UnitFormatter.temperatureRange(
            state.outfit.temperatureMin,
            state.outfit.temperatureMax,
            units: state.units
        ))
        return parts.joined(separator: " · ")
    }

    // MARK: Check

    private func checkSection(_ state: OutfitDetailsViewState) -> some View {
        ScreenBlock(spacing: 10) {
            SectionHeader("outfit check", accent: accentFor(state.check.status))

            HStack(spacing: 8) {
                StatusTag(
                    text: state.check.status.tagText,
                    fill: state.check.status.tagFill,
                    textColour: state.check.status.tagTextColour
                )
                Spacer(minLength: 0)
            }

            Panel {
                ForEach(Array(state.check.notes.enumerated()), id: \.offset) { _, note in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(noteColour(note))
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

            if !state.check.inWashPieceIDs.isEmpty {
                SecondaryButton(title: "Open the Laundry Loop") { presenter.didTapLaundry() }
            }
        }
    }

    private func accentFor(_ status: OutfitStatus) -> Color {
        switch status {
        case .ready: return Palette.success
        case .partlyUnavailable: return Palette.berry
        case .outOfSeason: return Palette.amber
        case .needsRepair: return Palette.danger
        }
    }

    private func noteColour(_ note: String) -> Color {
        if note.hasPrefix("All pieces") { return Palette.success }
        if note.contains("wash") || note.contains("repair") || note.contains("archived") || note.contains("stored") {
            return Palette.berry
        }
        return Palette.amber
    }

    // MARK: Actions

    private func actionsSection(_ state: OutfitDetailsViewState) -> some View {
        ScreenBlock(spacing: 10) {
            HStack(alignment: .top, spacing: 18) {
                BigNumber(value: "\(state.timesWorn)", label: "times worn", isCompact: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last worn")
                        .font(TypeScale.captionSmall)
                        .foregroundStyle(Palette.anchor.opacity(0.55))
                    Text(state.lastWornText)
                        .font(TypeScale.caption)
                        .foregroundStyle(Palette.anchor)
                }
                Spacer(minLength: 0)
            }

            PrimaryButton(
                title: state.wornTodayAlready ? "Already Worn Today" : "Mark as Worn",
                isEnabled: !state.wornTodayAlready && state.check.isAvailable
            ) {
                presenter.didTapMarkWorn()
            }

            if !state.check.isAvailable && !state.wornTodayAlready {
                Text("Some pieces are unavailable, so this outfit cannot be marked as worn yet.")
                    .font(TypeScale.captionSmall)
                    .foregroundStyle(Palette.anchor.opacity(0.6))
            }

            HStack(spacing: 10) {
                SecondaryButton(title: "Edit Outfit") { presenter.didTapEdit() }
                SecondaryButton(
                    title: state.outfit.isFavorite ? "Unfavourite" : "Favourite"
                ) {
                    presenter.didTapFavorite()
                }
            }
            HStack(spacing: 10) {
                SecondaryButton(title: "Duplicate") { presenter.didTapDuplicate() }
                SecondaryButton(title: "Plan a Day") { presenter.didTapPlanner() }
            }
        }
    }

    // MARK: Pieces

    private func piecesSection(_ state: OutfitDetailsViewState) -> some View {
        RailSection(
            title: "pieces",
            items: state.pieces.map { PieceRow(piece: $0.piece, layer: $0.layer) }
        ) { row in
            VStack(spacing: 6) {
                PieceCard(
                    piece: row.piece,
                    statusText: row.layer.title,
                    isDimmed: !row.piece.status.isAvailable,
                    height: 190,
                    width: Metrics.railCardWidth
                ) {
                    presenter.didTapPiece(row.piece.id)
                }
            }
        }
    }

    private struct PieceRow: Identifiable {
        var piece: Piece
        var layer: OutfitLayer
        var id: UUID { piece.id }
    }

    // MARK: Planned

    @ViewBuilder
    private func plannedSection(_ state: OutfitDetailsViewState) -> some View {
        if !state.plannedDates.isEmpty || !state.usedInTrips.isEmpty {
            ScreenBlock(spacing: 10) {
                SectionHeader("planned for", accent: Palette.berry)
                VStack(spacing: 8) {
                    ForEach(state.plannedDates, id: \.self) { entry in
                        InlineNotice(text: entry.capitalizedFirst, icon: "calendar")
                    }
                    ForEach(state.usedInTrips, id: \.self) { entry in
                        InlineNotice(text: entry, icon: "suitcase.fill", colour: Palette.berry)
                    }
                }
            }
        }
    }

    // MARK: History

    private func historySection(_ state: OutfitDetailsViewState) -> some View {
        ScreenBlock(spacing: 10) {
            SectionHeader("wear history")
            if state.wearHistory.isEmpty {
                InlineNotice(text: "This outfit has never been marked as worn.", icon: "clock")
            } else {
                VStack(spacing: 8) {
                    ForEach(state.wearHistory) { entry in
                        HStack(alignment: .top, spacing: 12) {
                            Rectangle()
                                .fill(entry.accent)
                                .frame(width: 4)
                                .clipShape(Capsule())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.title)
                                    .font(TypeScale.bodyBold)
                                    .foregroundStyle(Palette.anchor)
                                Text(entry.detail)
                                    .font(TypeScale.captionSmall)
                                    .foregroundStyle(Palette.anchor.opacity(0.6))
                            }
                            Spacer(minLength: 8)
                            Text(entry.dateText)
                                .font(TypeScale.captionSmall)
                                .monospacedDigit()
                                .foregroundStyle(Palette.anchor.opacity(0.5))
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.surface))
                    }
                }
            }
        }
    }

    // MARK: Danger

    private func dangerSection(_ state: OutfitDetailsViewState) -> some View {
        ScreenBlock(spacing: 10) {
            SectionHeader("remove", accent: Palette.danger)
            SecondaryButton(
                title: state.outfit.isArchived ? "Bring Back From Archive" : "Archive Outfit"
            ) {
                presenter.didTapArchive()
            }
            DangerButton(title: "Delete Outfit") { presenter.didTapDelete() }
            Text(state.deleteImpactText)
                .font(TypeScale.captionSmall)
                .foregroundStyle(Palette.anchor.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
