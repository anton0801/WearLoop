//
//  WeightCheckView.swift
//  WearLoop
//

import SwiftUI

struct WeightCheckView: View {
    @StateObject var presenter: WeightCheckPresenter

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
                ScreenScaffold { LoadingStateView(message: "Weighing the bag…") }
            }
        }
        .sheet(isPresented: $presenter.isRefinePresented) {
            if let state = presenter.viewState {
                RefineWeightsSheet(
                    rows: state.refineRows,
                    units: state.units,
                    onSet: { grams, row in presenter.didSetWeight(grams, row: row) },
                    onOpenCategoryWeights: { presenter.didTapCategoryWeights() }
                )
            }
        }
        .toast($presenter.toast)
        .onAppear { presenter.onAppear() }
    }

    private func content(_ state: WeightCheckViewState) -> some View {
        ScreenScaffold {
            ScreenBlock(spacing: 10) {
                ScreenHeader("weight check", subtitle: state.tripName)
            }

            gauge(state)
            estimateSection(state)
            suggestionsSection(state)
            heaviestSection(state)

            ScreenBlock(spacing: 10) {
                PrimaryButton(title: "Continue to Readiness") { presenter.didTapContinue() }
                SecondaryButton(title: "Back to the Packing List") { presenter.didTapPackingList() }
            }
        }
    }

    // MARK: Gauge

    private func gauge(_ state: WeightCheckViewState) -> some View {
        ScreenBlock(spacing: 14) {
            HStack(alignment: .center, spacing: 20) {
                LuggageGauge(
                    fillFraction: state.estimate.fillFraction,
                    isOverLimit: state.estimate.isOverLimit,
                    valueText: state.weightText,
                    limitText: state.limitText,
                    overText: state.overText,
                    showHalftone: state.showHalftone
                )

                VStack(alignment: .leading, spacing: 12) {
                    BigNumber(
                        value: "\(state.estimate.lines.count)",
                        label: "items in the bag",
                        isCompact: true
                    )
                    if let value = state.estimatedValueText {
                        BigNumber(value: value, label: "estimated value", colour: Palette.berry, isCompact: true)
                    }
                }
                Spacer(minLength: 0)
            }

            Text(state.summary)
                .font(TypeScale.bodyBold)
                .foregroundStyle(state.estimate.isOverLimit ? Palette.danger : Palette.anchor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Estimate quality

    @ViewBuilder
    private func estimateSection(_ state: WeightCheckViewState) -> some View {
        if let note = state.estimateNote {
            ScreenBlock(spacing: 10) {
                WarningPanel(
                    message: note,
                    primaryTitle: "Refine Weights",
                    primaryAction: { presenter.didTapRefine() },
                    secondaryTitle: "Category Averages",
                    secondaryAction: { presenter.didTapCategoryWeights() },
                    tint: Palette.amber
                )
            }
        } else if !state.estimate.lines.isEmpty {
            ScreenBlock {
                InlineNotice(
                    text: "Every item has a real weight, so this estimate is as accurate as it gets.",
                    icon: "checkmark.circle.fill",
                    colour: Palette.success
                )
            }
        }
    }

    // MARK: Suggestions

    @ViewBuilder
    private func suggestionsSection(_ state: WeightCheckViewState) -> some View {
        if !state.suggestions.isEmpty {
            ScreenBlock(spacing: 10) {
                SectionHeader(
                    state.estimate.isOverLimit ? "what to leave behind" : "where the weight is",
                    accent: state.estimate.isOverLimit ? Palette.danger : Palette.amber
                )
                ForEach(state.suggestions) { suggestion in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(suggestion.name)
                            .font(TypeScale.bodyBold)
                            .foregroundStyle(Palette.anchor)
                        Text(suggestion.text)
                            .font(TypeScale.caption)
                            .foregroundStyle(Palette.anchor.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                        if suggestion.pieceID != nil {
                            Button("Move to Not Packing") { presenter.didTapRemove(suggestion) }
                                .buttonStyle(CompactOutlineButtonStyle())
                                .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.surface)
                    )
                }
            }
        }
    }

    // MARK: Heaviest

    @ViewBuilder
    private func heaviestSection(_ state: WeightCheckViewState) -> some View {
        if state.heaviest.isEmpty {
            ScreenBlock {
                EmptyStateView(
                    title: "nothing in the bag",
                    message: "Add pieces to the packing list and the weight appears here.",
                    actionTitle: "Open the Packing List",
                    action: { presenter.didTapPackingList() },
                    showHalftone: state.showHalftone
                )
            }
        } else {
            ScreenBlock(spacing: 10) {
                SectionHeader("heaviest pieces")
                ForEach(state.heaviest) { line in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.name)
                                .font(TypeScale.bodyBold)
                                .foregroundStyle(Palette.anchor)
                                .lineLimit(1)
                            Text(
                                line.dayNumbers.isEmpty
                                    ? line.source.title
                                    : "Needed for \(Plural.days(line.dayNumbers))"
                            )
                            .font(TypeScale.captionSmall)
                            .foregroundStyle(Palette.anchor.opacity(0.55))
                            .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(UnitFormatter.weight(grams: line.grams, units: state.units))
                                .font(TypeScale.bodyBold.monospacedDigit())
                                .foregroundStyle(Palette.anchor)
                            if line.isEstimate {
                                Text("estimate")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Palette.anchor.opacity(0.4))
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.surface))
                    .contextMenu {
                        if line.pieceID != nil {
                            Button { presenter.didTapRemoveLine(line) } label: {
                                Label("Move to Not Packing", systemImage: "xmark.circle")
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                SecondaryButton(title: "Refine Weights") { presenter.didTapRefine() }
            }
        }
    }
}

// MARK: - Refine weights

struct RefineWeightsSheet: View {
    let rows: [WeightRefineRow]
    let units: MeasurementUnits
    let onSet: (Double?, WeightRefineRow) -> Void
    var onOpenCategoryWeights: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [UUID: Double?] = [:]

    var body: some View {
        NavigationStack {
            ScreenScaffold {
                ScreenBlock(spacing: 16) {
                    ScreenHeader(
                        "refine weights",
                        subtitle: "These items use an average. A real weight makes the bag estimate honest."
                    )

                    if rows.isEmpty {
                        EmptyStateView(
                            title: "nothing to refine",
                            message: "Every item in this bag already has a real weight."
                        )
                    } else {
                        ForEach(rows) { row in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(row.name)
                                            .font(TypeScale.bodyBold)
                                            .foregroundStyle(Palette.anchor)
                                        Text("\(row.categoryTitle) · currently \(UnitFormatter.weight(grams: row.currentGrams, units: units))")
                                            .font(TypeScale.captionSmall)
                                            .foregroundStyle(Palette.anchor.opacity(0.55))
                                    }
                                    Spacer(minLength: 0)
                                }
                                WLNumberField(
                                    placeholder: "\(Int(row.currentGrams)) (average)",
                                    value: Binding(
                                        get: { drafts[row.id] ?? nil },
                                        set: { newValue in
                                            drafts[row.id] = newValue
                                            onSet(newValue, row)
                                        }
                                    ),
                                    suffix: "g"
                                )
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.surface)
                            )
                        }

                        if let onOpenCategoryWeights {
                            SecondaryButton(title: "Edit Category Averages") {
                                dismiss()
                                onOpenCategoryWeights()
                            }
                        }
                    }

                    PrimaryButton(title: "Done") { dismiss() }
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
}
