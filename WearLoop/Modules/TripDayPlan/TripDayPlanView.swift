//
//  TripDayPlanView.swift
//  WearLoop
//

import SwiftUI

struct TripDayPlanView: View {
    @StateObject var presenter: TripDayPlanPresenter

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
                ScreenScaffold { LoadingStateView(message: "Loading the day plan…") }
            }
        }
        .sheet(item: Binding(
            get: { presenter.pickerDayIndex.map { DayPickerContext(index: $0) } },
            set: { if $0 == nil { presenter.pickerDayIndex = nil } }
        )) { context in
            OutfitPickerSheet(
                title: "day \(context.index + 1)",
                subtitle: "Outfits already packed for another day come first — reuse is what shrinks the bag.",
                candidates: presenter.candidates(for: context.index),
                onPick: { presenter.didPickOutfit($0, dayIndex: context.index) },
                onBuild: { presenter.didTapBuildOutfit() }
            )
        }
        .toast($presenter.toast)
        .onAppear { presenter.onAppear() }
    }

    private struct DayPickerContext: Identifiable {
        var index: Int
        var id: Int { index }
    }

    private func content(_ state: TripDayPlanViewState) -> some View {
        ScreenScaffold {
            ScreenBlock(spacing: 10) {
                ScreenHeader("day plan", subtitle: state.tripName)
            }

            coverageSection(state)

            if !state.hasOutfits {
                ScreenBlock {
                    EmptyStateView(
                        title: "no outfits to assign",
                        message: "Days are planned with outfits. Build one and it becomes available for every day here.",
                        actionTitle: "Build an Outfit",
                        action: { presenter.didTapBuildOutfit() },
                        showHalftone: state.showHalftone
                    )
                }
            }

            ForEach(state.rows) { row in
                dayCard(row, state: state)
            }

            ScreenBlock(spacing: 10) {
                if let reason = state.blockReason {
                    WarningPanel(message: reason, tint: Palette.burgundy)
                }
                PrimaryButton(title: "Continue to Packing", isEnabled: state.canContinue) {
                    presenter.didTapContinue()
                }
            }
        }
    }

    // MARK: Coverage

    private func coverageSection(_ state: TripDayPlanViewState) -> some View {
        ScreenBlock(spacing: 12) {
            SectionHeader("coverage", accent: Palette.burgundy)

            HStack(spacing: 18) {
                BigNumber(value: "\(state.coverage.daysCovered)", label: "days covered", isCompact: true)
                BigNumber(
                    value: "\(state.coverage.daysUndecided)",
                    label: "undecided",
                    colour: Palette.burgundy,
                    isCompact: true
                )
                BigNumber(
                    value: UnitFormatter.percent(state.coverage.reuseRate),
                    label: "reuse rate",
                    colour: Palette.amber,
                    isCompact: true
                )
                Spacer(minLength: 0)
            }

            Panel {
                FactRow(label: "Days Covered", value: "\(state.coverage.daysCovered) of \(state.coverage.daysTotal)")
                Divider().overlay(Palette.anchor.opacity(0.1))
                FactRow(label: "Days Undecided", value: "\(state.coverage.daysUndecided)")
                Divider().overlay(Palette.anchor.opacity(0.1))
                FactRow(label: "Pieces Used Once", value: "\(state.coverage.piecesUsedOnce) of \(state.coverage.totalPiecesUsed)")
            }

            if !state.notes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(state.notes.enumerated()), id: \.offset) { _, note in
                        InlineNotice(text: note, icon: "arrow.triangle.2.circlepath")
                    }
                }
            }
        }
    }

    // MARK: Day card

    private func dayCard(_ row: TripDayPlanRow, state: TripDayPlanViewState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ScreenBlock(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Day \(row.dayNumber)")
                        .font(TypeScale.sectionTitle)
                        .tracking(TypeScale.sectionTitleTracking)
                        .foregroundStyle(Palette.anchor)
                    Text(row.dateText)
                        .font(TypeScale.captionSmall)
                        .foregroundStyle(Palette.anchor.opacity(0.55))
                    Spacer(minLength: 0)
                    if row.isUndecided {
                        StatusTag(text: "UNDECIDED", fill: Palette.anchor, textColour: .white)
                    } else if let status = row.status, status != .ready {
                        StatusTag(text: status.tagText, fill: status.tagFill, textColour: status.tagTextColour)
                    }
                }
                Text(row.occasionText)
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.anchor.opacity(0.65))
            }

            if let outfitName = row.outfitName {
                ScreenBlock(spacing: 8) {
                    Button {
                        if let id = row.outfitID { presenter.didTapOutfit(id) }
                    } label: {
                        OutfitFlatLay(
                            pieces: row.pieces.map { ($0, $0.category.naturalLayer) },
                            showHalftone: state.showHalftone,
                            height: 200
                        )
                    }
                    .buttonStyle(CardPressStyle())
                    .accessibilityLabel("\(outfitName) on day \(row.dayNumber). Opens the outfit.")

                    Text(outfitName)
                        .font(TypeScale.bodyBold)
                        .foregroundStyle(Palette.anchor)

                    if let reuse = row.reuseText {
                        InlineNotice(text: reuse, icon: "arrow.triangle.2.circlepath", colour: Palette.success)
                    }
                    if let warning = row.warningText {
                        WarningPanel(message: warning, tint: Palette.burgundy)
                    }

                    HStack(spacing: 10) {
                        SecondaryButton(title: "Change") { presenter.didTapAssign(dayIndex: row.index) }
                        SecondaryButton(title: "Clear") { presenter.didTapClear(dayIndex: row.index) }
                    }
                }
            } else {
                ScreenBlock(spacing: 8) {
                    InlineNotice(
                        text: row.isUndecided
                            ? "Marked as undecided. You can pack for this day later."
                            : "No outfit yet. Assign one or mark the day as undecided to move on.",
                        icon: row.isUndecided ? "questionmark.circle" : "exclamationmark.circle",
                        colour: row.isUndecided ? Palette.anchor.opacity(0.6) : Palette.burgundy
                    )
                    HStack(spacing: 10) {
                        PrimaryButton(title: "Assign Outfit", isEnabled: state.hasOutfits) {
                            presenter.didTapAssign(dayIndex: row.index)
                        }
                    }
                    SecondaryButton(
                        title: row.isUndecided ? "Not Undecided" : "Mark as Undecided"
                    ) {
                        presenter.didToggleUndecided(dayIndex: row.index, current: row.isUndecided)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}
