//
//  PieceDetailsView.swift
//  WearLoop
//

import SwiftUI

struct PieceDetailsView: View {
    @StateObject var presenter: PieceDetailsPresenter

    var body: some View {
        Group {
            if let state = presenter.viewState {
                content(state)
            } else if presenter.isMissing {
                missing
            } else {
                ScreenScaffold { LoadingStateView(message: "Loading this piece…") }
            }
        }
        .toast($presenter.toast)
        .confirm($presenter.confirm)
        .sheet(isPresented: $presenter.isMarkWornPresented) {
            if let state = presenter.viewState {
                MarkWornSheet(outfitName: state.piece.name, pieceCount: 1) { sendToWash in
                    presenter.didConfirmMarkWorn(sendToWash: sendToWash)
                }
            }
        }
        .sheet(isPresented: $presenter.isRepairSheetPresented) {
            ReportRepairSheet { issue, plan in
                presenter.didSubmitRepair(issue: issue, plannedAction: plan)
            }
        }
        .onAppear { presenter.onAppear() }
    }

    private var missing: some View {
        ScreenScaffold {
            ScreenBlock {
                EmptyStateView(
                    title: "this piece is gone",
                    message: "It was deleted. Any wear records it appeared in keep their own copy of the name and photo.",
                    actionTitle: "Back to Wardrobe",
                    action: { presenter.didTapBack() }
                )
            }
        }
    }

    // MARK: Content

    private func content(_ state: PieceDetailsViewState) -> some View {
        ScreenScaffold {
            hero(state)
            facts(state)
            actions(state)
            outfitsSection(state)
            calendarSection(state)
            wearHistorySection(state)
            laundryHistorySection(state)
            notesSection(state)
            dangerZone(state)
        }
    }

    // MARK: Hero

    private func hero(_ state: PieceDetailsViewState) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .topTrailing) {
                PieceImage(
                    photoID: state.piece.photoID,
                    fallbackColour: state.piece.primaryColour,
                    fallbackInitial: state.piece.name.wlInitial,
                    initialSize: 140
                )
                .frame(height: 320)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))

                StatusTag(
                    text: state.piece.status.tagText,
                    fill: state.piece.status.tagColour,
                    textColour: state.piece.status.tagTextColour
                )
                .padding(.trailing, 12)
            }
            .padding(.horizontal, Metrics.screenPadding)

            ScreenBlock(spacing: 8) {
                ScreenHeader(state.piece.name, subtitle: state.statusDetail)

                WrappingHStack {
                    ForEach(state.piece.colours) { colour in
                        ChipView(title: colour.title, isSelected: false, swatch: colour.colour) {}
                            .allowsHitTesting(false)
                    }
                    ChipView(title: state.piece.category.title, isSelected: false) {}
                        .allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: Facts

    private func facts(_ state: PieceDetailsViewState) -> some View {
        ScreenBlock(spacing: 12) {
            HStack(alignment: .top, spacing: 18) {
                BigNumber(value: "\(state.timesWorn)", label: "times worn", isCompact: true)
                if let cost = state.costPerWearText {
                    BigNumber(value: cost, label: "cost per wear", colour: Palette.berry, isCompact: true)
                }
                Spacer(minLength: 0)
            }

            Panel {
                FactRow(label: "Last Worn", value: state.lastWornText)
                Divider().overlay(Palette.anchor.opacity(0.1))
                FactRow(label: "Current Status", value: state.piece.status.title)
                Divider().overlay(Palette.anchor.opacity(0.1))
                FactRow(label: "Condition", value: state.piece.condition.title)
                Divider().overlay(Palette.anchor.opacity(0.1))
                FactRow(label: "Seasons", value: state.piece.seasons.map(\.title).joined(separator: ", "))
                Divider().overlay(Palette.anchor.opacity(0.1))
                FactRow(label: "Occasions", value: state.piece.occasions.map(\.title).joined(separator: ", "))
                if !state.piece.material.wlIsBlank {
                    Divider().overlay(Palette.anchor.opacity(0.1))
                    FactRow(label: "Material", value: state.piece.material)
                }
                if !state.piece.size.wlIsBlank {
                    Divider().overlay(Palette.anchor.opacity(0.1))
                    FactRow(label: "Size", value: state.piece.size)
                }
                if !state.piece.storagePlace.wlIsBlank {
                    Divider().overlay(Palette.anchor.opacity(0.1))
                    FactRow(label: "Storage Place", value: state.piece.storagePlace)
                }
                Divider().overlay(Palette.anchor.opacity(0.1))
                FactRow(label: "Weight", value: state.weightText)
                if let price = state.priceText {
                    Divider().overlay(Palette.anchor.opacity(0.1))
                    FactRow(label: "Purchase Price", value: price)
                }
                if let date = state.piece.purchaseDate {
                    Divider().overlay(Palette.anchor.opacity(0.1))
                    FactRow(label: "Purchase Date", value: DateFormatterCache.dayMonthYear.string(from: date))
                }
            }

            if !state.piece.tags.isEmpty {
                WrappingHStack {
                    ForEach(state.piece.tags, id: \.self) { tag in
                        ChipView(title: tag, isSelected: false) {}
                            .allowsHitTesting(false)
                    }
                }
            }

            if !state.upcomingTripNames.isEmpty {
                InlineNotice(
                    text: "Packed for \(state.upcomingTripNames.joined(separator: ", ")).",
                    icon: "suitcase.fill",
                    colour: Palette.berry
                )
            }
        }
    }

    // MARK: Actions

    private func actions(_ state: PieceDetailsViewState) -> some View {
        ScreenBlock(spacing: 10) {
            SectionHeader("actions")

            if let repair = state.openRepair {
                WarningPanel(
                    message: "Reported \(DateFormatterCache.dayMonth.string(from: repair.reportedOn)): \(repair.issue)",
                    primaryTitle: "Open Repairs",
                    primaryAction: { presenter.didTapRepairs() },
                    tint: Palette.danger
                )
            }

            switch state.piece.status {
            case .inRotation:
                PrimaryButton(title: "Mark as Worn") { presenter.didTapMarkWorn() }
                HStack(spacing: 10) {
                    SecondaryButton(title: "Send to Wash") { presenter.didTapSendToWash() }
                    SecondaryButton(title: "Store Away") { presenter.didTapStoreAway() }
                }
                SecondaryButton(title: "Mark Needs Repair") { presenter.didTapReportRepair() }

            case .inWash:
                PrimaryButton(title: "Return From Wash") { presenter.didTapReturnFromWash() }
                SecondaryButton(title: "Open the Laundry Loop") { presenter.didTapLaundry() }

            case .needsRepair:
                PrimaryButton(title: "Open Repairs and Care") { presenter.didTapRepairs() }
                SecondaryButton(title: "Return to Rotation") { presenter.didTapReturnToRotation() }

            case .storedAway:
                PrimaryButton(title: "Return to Rotation") { presenter.didTapReturnToRotation() }
                SecondaryButton(title: "Mark Needs Repair") { presenter.didTapReportRepair() }

            case .archived:
                InlineNotice(
                    text: "Archived pieces stay out of outfits, plans and packing lists, but keep their history.",
                    icon: "archivebox"
                )
                PrimaryButton(title: "Return to Rotation") { presenter.didTapReturnToRotation() }
            }

            SecondaryButton(title: "Edit Piece") { presenter.didTapEdit() }
        }
    }

    // MARK: Outfits

    @ViewBuilder
    private func outfitsSection(_ state: PieceDetailsViewState) -> some View {
        if state.outfits.isEmpty {
            ScreenBlock(spacing: 10) {
                SectionHeader("used in outfits")
                InlineNotice(
                    text: "This piece is not in any outfit yet. Outfits are what the app plans and packs with.",
                    icon: "square.stack.3d.up"
                )
                SecondaryButton(title: "Build an Outfit With It") { presenter.didTapBuildOutfit() }
            }
        } else {
            RailSection(
                title: "used in outfits",
                accent: Palette.berry,
                actionTitle: "Build New",
                action: { presenter.didTapBuildOutfit() },
                items: state.outfits
            ) { outfit in
                OutfitCard(
                    outfit: outfit,
                    pieces: state.outfitPieces[outfit.id] ?? [],
                    subtitle: outfit.occasion.title
                ) {
                    presenter.didTapOutfit(outfit.id)
                }
            }
        }
    }

    // MARK: Calendar

    private func calendarSection(_ state: PieceDetailsViewState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ScreenBlock {
                SectionHeader("wear calendar")
                Text("Amber is a confirmed wearing. A berry outline is planned but not yet worn.")
                    .font(TypeScale.captionSmall)
                    .foregroundStyle(Palette.anchor.opacity(0.55))
            }
            WearCalendarStrip(days: state.calendarDays)
        }
    }

    // MARK: Histories

    @ViewBuilder
    private func wearHistorySection(_ state: PieceDetailsViewState) -> some View {
        ScreenBlock(spacing: 10) {
            SectionHeader("wear history")
            if state.wearHistory.isEmpty {
                InlineNotice(text: "No wearings recorded yet. Nothing is ever counted automatically.", icon: "clock")
            } else {
                VStack(spacing: 8) {
                    ForEach(state.wearHistory) { entry in
                        historyRow(entry)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func laundryHistorySection(_ state: PieceDetailsViewState) -> some View {
        if !state.laundryHistory.isEmpty {
            ScreenBlock(spacing: 10) {
                SectionHeader("laundry history", accent: Palette.berry)
                VStack(spacing: 8) {
                    ForEach(state.laundryHistory) { entry in
                        historyRow(entry)
                    }
                }
            }
        }
    }

    private func historyRow(_ entry: HistoryEntry) -> some View {
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
        .accessibilityElement(children: .combine)
    }

    // MARK: Notes

    @ViewBuilder
    private func notesSection(_ state: PieceDetailsViewState) -> some View {
        if !state.piece.careNotes.wlIsBlank || !state.piece.privateNote.wlIsBlank {
            ScreenBlock(spacing: 10) {
                SectionHeader("notes")
                if !state.piece.careNotes.wlIsBlank {
                    Panel {
                        Text("Care Notes")
                            .font(TypeScale.captionSmall)
                            .foregroundStyle(Palette.anchor.opacity(0.55))
                        Text(state.piece.careNotes)
                            .font(TypeScale.body)
                            .foregroundStyle(Palette.anchor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !state.piece.privateNote.wlIsBlank {
                    Panel {
                        Text("Private Note")
                            .font(TypeScale.captionSmall)
                            .foregroundStyle(Palette.anchor.opacity(0.55))
                        Text(state.piece.privateNote)
                            .font(TypeScale.body)
                            .foregroundStyle(Palette.anchor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: Danger zone

    private func dangerZone(_ state: PieceDetailsViewState) -> some View {
        ScreenBlock(spacing: 10) {
            SectionHeader("remove", accent: Palette.danger)
            if state.piece.status != .archived {
                SecondaryButton(title: "Archive Piece") { presenter.didTapArchive() }
            }
            DangerButton(title: "Delete Piece") { presenter.didTapDelete() }
            Text(state.deleteImpactText)
                .font(TypeScale.captionSmall)
                .foregroundStyle(Palette.anchor.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Repair sheet

struct ReportRepairSheet: View {
    let onSubmit: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var issue = ""
    @State private var plannedAction = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScreenScaffold {
                ScreenBlock(spacing: 20) {
                    ScreenHeader(
                        "report an issue",
                        subtitle: "The piece leaves rotation until the repair is marked as done."
                    )

                    FieldFrame(label: "Issue", isRequired: true, errorMessage: error) {
                        WLTextField(
                            placeholder: "Loose button, torn hem…",
                            text: $issue,
                            hasError: error != nil
                        )
                    }

                    FieldFrame(label: "Planned Action") {
                        WLTextField(placeholder: "Take to the tailor", text: $plannedAction)
                    }

                    PrimaryButton(title: "Add to Repair List") {
                        guard !issue.wlIsBlank else {
                            error = "Describe the issue to continue."
                            return
                        }
                        onSubmit(issue, plannedAction)
                    }
                    SecondaryButton(title: "Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}
