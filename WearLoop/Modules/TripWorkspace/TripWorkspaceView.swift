//
//  TripWorkspaceView.swift
//  WearLoop
//

import SwiftUI

struct TripWorkspaceView: View {
    @StateObject var presenter: TripWorkspacePresenter

    var body: some View {
        Group {
            if let state = presenter.viewState {
                content(state)
            } else if presenter.isMissing {
                ScreenScaffold {
                    ScreenBlock {
                        EmptyStateView(
                            title: "this trip is gone",
                            message: "It was deleted. Wear records made during it are kept.",
                            actionTitle: "Back",
                            action: { presenter.didTapEdit() }
                        )
                    }
                }
            } else {
                ScreenScaffold { LoadingStateView(message: "Loading this trip…") }
            }
        }
        .toast($presenter.toast)
        .confirm($presenter.confirm)
        .onAppear { presenter.onAppear() }
    }

    private func content(_ state: TripWorkspaceViewState) -> some View {
        ScreenScaffold {
            header(state)
            StageIndicator(
                stages: TripStage.allCases,
                current: state.trip.stage,
                reachable: state.reachableStages,
                onSelect: { presenter.didSelectStage($0) }
            )
            summary(state)
            warnings(state)
            checklist(state)
            actions(state)
        }
    }

    // MARK: Header

    private func header(_ state: TripWorkspaceViewState) -> some View {
        ScreenBlock(spacing: 10) {
            ScreenHeader(
                state.trip.name.wlIsBlank ? "untitled trip" : state.trip.name,
                subtitle: state.trip.destination.isEmpty
                    ? state.trip.dateRangeText
                    : "\(state.trip.destination) · \(state.trip.dateRangeText)"
            ) {
                Button {
                    presenter.didTapEdit()
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(IconButtonStyle())
                .accessibilityLabel("Edit trip")
            }
        }
        .padding(.bottom, 4)
        .background(
            HalftoneBackground(opacity: state.showHalftone ? 0.18 : 0, spacing: 30, focus: .topTrailing)
                .allowsHitTesting(false)
        )
    }

    // MARK: Summary

    private func summary(_ state: TripWorkspaceViewState) -> some View {
        ScreenBlock(spacing: 14) {
            SectionHeader("trip progress", accent: Palette.berry)

            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    BigNumber(
                        value: "\(state.coverage.daysCovered)/\(state.coverage.daysTotal)",
                        label: "days planned",
                        isCompact: true
                    )
                    BigNumber(
                        value: "\(state.trip.packedCount)/\(state.trip.activePacking.count)",
                        label: "pieces packed",
                        isCompact: true
                    )
                }
                Spacer(minLength: 0)
                LuggageGauge(
                    fillFraction: state.estimate.fillFraction,
                    isOverLimit: state.isOverLimit,
                    valueText: state.weightText,
                    limitText: state.limitText,
                    overText: state.overText,
                    showHalftone: state.showHalftone
                )
            }

            CountProgress(
                passed: state.readiness.passedCount,
                total: state.readiness.totalCount,
                label: "checks passed",
                fill: state.readiness.isReady ? Palette.success : Palette.amber
            )
        }
    }

    // MARK: Warnings

    @ViewBuilder
    private func warnings(_ state: TripWorkspaceViewState) -> some View {
        if state.daysNeedingPlanText != nil || !state.outsideConditionOutfits.isEmpty {
            ScreenBlock(spacing: 10) {
                if let text = state.daysNeedingPlanText {
                    WarningPanel(
                        message: text,
                        primaryTitle: "Open the Day Plan",
                        primaryAction: { presenter.didTapDayPlan() },
                        tint: Palette.berry
                    )
                }
                if !state.outsideConditionOutfits.isEmpty {
                    WarningPanel(
                        message: "\(state.outsideConditionOutfits.joined(separator: ", ")) no longer suits this trip's conditions. Nothing was removed — change it if you like.",
                        primaryTitle: "Open the Day Plan",
                        primaryAction: { presenter.didTapDayPlan() },
                        tint: Palette.amber
                    )
                }
            }
        }
    }

    // MARK: Checklist

    private func checklist(_ state: TripWorkspaceViewState) -> some View {
        ScreenBlock(spacing: 10) {
            SectionHeader("stages")

            NavigationRow(
                title: "Day Plan",
                subtitle: "\(state.coverage.daysCovered) covered · \(state.coverage.daysUndecided) undecided · \(state.coverage.daysWithoutPlan) open",
                icon: "calendar",
                accent: Palette.berry
            ) {
                presenter.didTapDayPlan()
            }

            NavigationRow(
                title: "Packing List",
                subtitle: rowSubtitle(for: .packingList, state: state)
                    ?? "\(Plural.count(state.trip.activePacking.count, "item")) · \(state.trip.packedCount) packed",
                icon: "checklist",
                accent: Palette.amber
            ) {
                presenter.didTapPacking()
            }

            NavigationRow(
                title: "Weight Check",
                subtitle: rowSubtitle(for: .weightCheck, state: state)
                    ?? LuggageEngine.summarySentence(estimate: state.estimate, units: state.units),
                icon: "scalemass",
                accent: state.isOverLimit ? Palette.danger : Palette.amber
            ) {
                presenter.didTapWeight()
            }

            NavigationRow(
                title: "Trip Readiness",
                subtitle: "\(state.readiness.passedCount) of \(state.readiness.totalCount) checks passed",
                icon: "checkmark.seal",
                accent: state.readiness.isReady ? Palette.success : Palette.anchor
            ) {
                presenter.didTapReadiness()
            }

            if state.trip.recap != nil {
                NavigationRow(
                    title: "Recap",
                    subtitle: "What you packed against what you wore",
                    icon: "chart.bar",
                    accent: Palette.success
                ) {
                    presenter.didTapRecap()
                }
            }
        }
    }

    private func rowSubtitle(for stage: TripStage, state: TripWorkspaceViewState) -> String? {
        state.blockReasons[stage]
    }

    // MARK: Actions

    private func actions(_ state: TripWorkspaceViewState) -> some View {
        ScreenBlock(spacing: 10) {
            SectionHeader("next")

            if state.trip.stage == .inProgress {
                PrimaryButton(title: "Open Trip Mode") { presenter.didTapStart() }
            } else if state.trip.recap != nil {
                PrimaryButton(title: "Open the Recap") { presenter.didTapRecap() }
            } else if state.readiness.isReady {
                if state.trip.stage == .ready {
                    PrimaryButton(title: "Start the Trip") { presenter.didTapStart() }
                } else {
                    PrimaryButton(title: "Mark Trip as Ready") { presenter.didTapMarkReady() }
                }
            } else {
                PrimaryButton(title: "Fix Remaining Issues") { presenter.didTapReadiness() }
                Text("\(Plural.count(state.readiness.outstanding.count, "check")) still need attention before this trip is ready.")
                    .font(TypeScale.captionSmall)
                    .foregroundStyle(Palette.anchor.opacity(0.6))
            }

            SecondaryButton(title: "Edit Trip") { presenter.didTapEdit() }
        }
    }
}
