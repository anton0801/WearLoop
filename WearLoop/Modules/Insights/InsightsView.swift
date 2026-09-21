//
//  InsightsView.swift
//  WearLoop
//

import SwiftUI

struct InsightsView: View {
    @StateObject var presenter: InsightsPresenter

    var body: some View {
        ScreenScaffold {
            ScreenBlock(spacing: 10) {
                ScreenHeader("insights", subtitle: presenter.viewState.summaryText, artwork: .insights)
            }

            if !presenter.viewState.hasPieces {
                ScreenBlock {
                    EmptyStateView(
                        title: "nothing to measure",
                        message: "Add pieces and start marking days as worn. Every figure here comes from your own records.",
                        actionTitle: "Add First Piece",
                        action: { presenter.didTapAddPiece() },
                        showHalftone: presenter.viewState.showHalftone
                    )
                }
            } else {
                if !presenter.viewState.isUnlocked {
                    lockedBanner
                    ScreenBlock(spacing: 10) {
                        SectionHeader("available now")
                    }
                    metricsGrid(presenter.viewState.headlineMetrics)
                } else {
                    metricsGrid(presenter.viewState.metrics)
                }
            }
        }
        .onAppear { presenter.onAppear() }
    }

    // MARK: Locked

    private var lockedBanner: some View {
        ScreenBlock {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader("more wear records needed", accent: Palette.burgundy)
                Text(presenter.viewState.lockMessage)
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.anchor.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                CountProgress(
                    passed: presenter.viewState.wearDayCount,
                    total: presenter.viewState.requiredDays,
                    label: "days recorded",
                    fill: Palette.amber
                )
                PrimaryButton(title: "Plan and Record a Day") { presenter.didTapPlanner() }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                PlateBackground(cornerRadius: Metrics.cardRadius)
                    .halftoneBacking(
                        enabled: presenter.viewState.showHalftone,
                        colour: Palette.gold,
                        opacity: 0.22,
                        focus: .topTrailing,
                        spacing: 30
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            )
        }
    }

    // MARK: Metrics

    private func metricsGrid(_ metrics: [InsightMetric]) -> some View {
        ScreenBlock(spacing: 12) {
            ForEach(metrics) { metric in
                metricCard(metric)
            }
        }
    }

    private func metricCard(_ metric: InsightMetric) -> some View {
        Button {
            presenter.didTapMetric(metric.kind)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Text(metric.kind.title)
                        .font(TypeScale.caption)
                        .foregroundStyle(Palette.anchor.opacity(0.6))
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(Palette.anchor.opacity(0.3))
                }

                Text(metric.headline)
                    .font(TypeScale.bigNumber)
                    .foregroundStyle(Palette.anchor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)

                Text(metric.isLocked ? (metric.lockedMessage ?? "") : metric.subtitle)
                    .font(TypeScale.caption)
                    .foregroundStyle(metric.isLocked ? Palette.anchor.opacity(0.5) : Palette.anchor.opacity(0.75))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if !metric.isLocked, let top = metric.rows.first, let fraction = top.fraction {
                    ValueBar(fraction: fraction, fill: barColour(metric.kind))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(PlateBackground(cornerRadius: Metrics.cardRadius))
            .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
        .buttonStyle(CardPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metric.kind.title), \(metric.headline). \(metric.isLocked ? (metric.lockedMessage ?? "") : metric.subtitle)")
    }

    private func barColour(_ kind: InsightKind) -> Color {
        switch kind {
        case .neverWorn, .boughtNeverUsed, .repairBacklog: return Palette.burgundy
        case .packingAccuracy, .wardrobeInRotation: return Palette.success
        default: return Palette.amber
        }
    }
}

// MARK: - Detail

struct InsightDetailView: View {
    @StateObject var presenter: InsightDetailPresenter

    var body: some View {
        ScreenScaffold {
            if let metric = presenter.metric {
                ScreenBlock(spacing: 10) {
                    ScreenHeader(metric.kind.title, subtitle: metric.isLocked ? nil : metric.subtitle)
                }

                if metric.isLocked {
                    ScreenBlock {
                        EmptyStateView(
                            title: "not enough records",
                            message: metric.lockedMessage ?? "There is not enough history for this figure yet."
                        )
                    }
                } else {
                    ScreenBlock(spacing: 14) {
                        BigNumber(value: metric.headline, label: metric.kind.title)
                    }

                    if metric.rows.isEmpty {
                        ScreenBlock {
                            EmptyStateView(
                                title: "nothing to list",
                                message: "This figure has no rows behind it yet."
                            )
                        }
                    } else {
                        ScreenBlock(spacing: 10) {
                            SectionHeader("breakdown")
                            ForEach(metric.rows) { row in
                                rowView(row, kind: metric.kind)
                            }
                        }
                    }
                }
            } else {
                LoadingStateView(message: "Working it out…")
            }
        }
        .onAppear { presenter.onAppear() }
    }

    private func rowView(_ row: InsightRow, kind: InsightKind) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                presenter.didTapRow(row)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        if let colour = row.colour {
                            Circle()
                                .fill(colour.colour)
                                .frame(width: 16, height: 16)
                                .overlay(Circle().strokeBorder(Palette.anchor.opacity(0.2), lineWidth: 1))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.label)
                                .font(TypeScale.bodyBold)
                                .foregroundStyle(Palette.anchor)
                                .multilineTextAlignment(.leading)
                            if let detail = row.detail {
                                Text(detail)
                                    .font(TypeScale.captionSmall)
                                    .foregroundStyle(Palette.anchor.opacity(0.55))
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        Spacer(minLength: 8)
                        Text(row.valueText)
                            .font(TypeScale.bodyBold.monospacedDigit())
                            .foregroundStyle(Palette.anchor)
                    }
                    if let fraction = row.fraction {
                        ValueBar(fraction: fraction)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if presenter.expandedRow?.id == row.id {
                relatedRecordsView(row)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PlateBackground(cornerRadius: 14))
    }

    @ViewBuilder
    private func relatedRecordsView(_ row: InsightRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(Palette.anchor.opacity(0.12))

            if let pieceID = row.pieceID {
                Button("Open Piece") { presenter.didTapPiece(pieceID) }
                    .buttonStyle(CompactOutlineButtonStyle())
            }

            Text("Related Records")
                .font(TypeScale.captionSmall)
                .foregroundStyle(Palette.anchor.opacity(0.55))

            if presenter.relatedRecords.isEmpty {
                Text("No wear records lie behind this row.")
                    .font(TypeScale.captionSmall)
                    .foregroundStyle(Palette.anchor.opacity(0.5))
            } else {
                ForEach(presenter.relatedRecords) { record in
                    HStack(alignment: .top, spacing: 10) {
                        Rectangle()
                            .fill(Palette.amber)
                            .frame(width: 3)
                            .clipShape(Capsule())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(record.title)
                                .font(TypeScale.caption)
                                .foregroundStyle(Palette.anchor)
                            Text(record.detail)
                                .font(TypeScale.captionSmall)
                                .foregroundStyle(Palette.anchor.opacity(0.55))
                        }
                        Spacer(minLength: 8)
                        Text(record.dateText)
                            .font(TypeScale.captionSmall.monospacedDigit())
                            .foregroundStyle(Palette.anchor.opacity(0.5))
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .transition(.opacity)
    }
}
