//
//  TripReadinessView.swift
//  WearLoop
//

import SwiftUI

struct TripReadinessView: View {
    @StateObject var presenter: TripReadinessPresenter

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
                ScreenScaffold { LoadingStateView(message: "Checking the trip…") }
            }
        }
        .toast($presenter.toast)
        .confirm($presenter.confirm)
        .onAppear { presenter.onAppear() }
    }

    private func content(_ state: TripReadinessViewState) -> some View {
        ScreenScaffold {
            ScreenBlock(spacing: 10) {
                ScreenHeader("trip readiness", subtitle: "\(state.tripName) · \(state.startsInText)")
            }

            ScreenBlock(spacing: 14) {
                HStack(alignment: .top, spacing: 20) {
                    BigNumber(
                        value: "\(state.readiness.passedCount)/\(state.readiness.totalCount)",
                        label: "checks passed",
                        colour: state.isReady ? Palette.success : Palette.anchor
                    )
                    Spacer(minLength: 0)
                }
                ValueBar(
                    fraction: state.readiness.totalCount > 0
                        ? Double(state.readiness.passedCount) / Double(state.readiness.totalCount)
                        : 0,
                    fill: state.isReady ? Palette.success : Palette.amber,
                    height: 12
                )
            }

            ScreenBlock(spacing: 10) {
                SectionHeader("checks")
                ForEach(state.readiness.items) { item in
                    checkRow(item)
                }
            }

            ScreenBlock(spacing: 10) {
                if state.isInProgress {
                    PrimaryButton(title: "Open Trip Mode") { presenter.didTapOpenTripMode() }
                } else if state.isReady {
                    if state.isAlreadyReady {
                        InlineNotice(
                            text: "This trip is marked as ready.",
                            icon: "checkmark.seal.fill",
                            colour: Palette.success
                        )
                        PrimaryButton(title: "Start the Trip") { presenter.didTapStart() }
                    } else {
                        PrimaryButton(title: "Mark Trip as Ready") { presenter.didTapMarkReady() }
                    }
                } else {
                    PrimaryButton(title: "Fix Remaining Issues") { presenter.didTapFixRemaining() }
                    Text("\(Plural.count(state.readiness.outstanding.count, "check")) still need attention. Tap any row above to go straight to it.")
                        .font(TypeScale.captionSmall)
                        .foregroundStyle(Palette.anchor.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func checkRow(_ item: ReadinessItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                presenter.didTapItem(item)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(item.isPassed ? Palette.success : Palette.surface)
                        Circle()
                            .strokeBorder(item.isPassed ? Palette.success : Palette.anchor.opacity(0.3), lineWidth: 2)
                        Image(systemName: item.isPassed ? "checkmark" : "exclamationmark")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(item.isPassed ? .white : Palette.anchor.opacity(0.5))
                    }
                    .frame(width: 30, height: 30)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(TypeScale.bodyBold)
                            .foregroundStyle(Palette.anchor)
                            .multilineTextAlignment(.leading)
                        Text(item.detail)
                            .font(TypeScale.captionSmall)
                            .foregroundStyle(item.isPassed ? Palette.anchor.opacity(0.55) : Palette.berry)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(Palette.anchor.opacity(0.35))
                        .padding(.top, 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !item.isPassed, let quickFix = presenter.quickFixTitle(item) {
                Button(quickFix) { presenter.didTapQuickFix(item) }
                    .buttonStyle(CompactButtonStyle(fill: Palette.amber, textColour: Palette.anchor))
                    .padding(.leading, 42)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.surface))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(item.isPassed ? "passed" : "not passed"). \(item.detail)")
    }
}
