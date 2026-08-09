//
//  EventsView.swift
//  WearLoop
//

import SwiftUI

struct EventsView: View {
    @StateObject var presenter: EventsPresenter

    var body: some View {
        ScreenScaffold {
            ScreenBlock(spacing: 10) {
                ScreenHeader("events", subtitle: presenter.viewState.summaryText) {
                    Button {
                        presenter.didTapCreate()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(IconButtonStyle())
                    .accessibilityLabel("Add an event")
                }
            }

            SegmentBar(items: presenter.segmentItems(), selection: $presenter.section)

            content
        }
        .toast($presenter.toast)
        .confirm($presenter.confirm)
        .onAppear { presenter.onAppear() }
    }

    @ViewBuilder
    private var content: some View {
        if presenter.viewState.totalEvents == 0 {
            ScreenBlock {
                EmptyStateView(
                    title: "no events yet",
                    message: "Add a wedding, an interview or a shoot and the app checks your outfit against its dress code.",
                    actionTitle: "Add an Event",
                    action: { presenter.didTapCreate() },
                    showHalftone: presenter.viewState.showHalftone
                )
            }
        } else if presenter.viewState.items.isEmpty {
            ScreenBlock {
                EmptyStateView(
                    title: "nothing in this section",
                    message: presenter.section == .upcoming
                        ? "No events are coming up."
                        : "No past events yet.",
                    actionTitle: "Add an Event",
                    action: { presenter.didTapCreate() },
                    showHalftone: presenter.viewState.showHalftone
                )
            }
        } else {
            ScreenBlock(spacing: 12) {
                ForEach(presenter.viewState.items) { item in
                    eventCard(item)
                }
            }
        }
    }

    private func eventCard(_ item: EventListItem) -> some View {
        Button {
            presenter.didTapEvent(item.id)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name)
                            .font(TypeScale.sectionTitle)
                            .tracking(TypeScale.sectionTitleTracking)
                            .foregroundStyle(Palette.anchor)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text("\(item.relativeText) · \(item.dateText)")
                            .font(TypeScale.captionSmall)
                            .foregroundStyle(Palette.anchor.opacity(0.6))
                    }
                    Spacer(minLength: 8)
                    if item.isWorn {
                        StatusTag(text: "WORN", fill: Palette.success)
                    } else if !item.hasOutfit {
                        StatusTag(text: "NO OUTFIT", fill: Palette.berry)
                    }
                }

                HStack(spacing: 8) {
                    ChipView(title: item.dressCode.title, isSelected: true, accent: Palette.anchor) {}
                        .allowsHitTesting(false)
                    Spacer(minLength: 0)
                }

                if !item.outfitPieces.isEmpty {
                    HStack(spacing: -8) {
                        ForEach(item.outfitPieces.prefix(5)) { piece in
                            PieceImage(
                                photoID: piece.photoID,
                                fallbackColour: piece.primaryColour,
                                fallbackInitial: piece.name.wlInitial,
                                initialSize: 18
                            )
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Palette.surface, lineWidth: 2)
                            )
                        }
                        if let name = item.outfitName {
                            Text(name)
                                .font(TypeScale.caption)
                                .foregroundStyle(Palette.anchor)
                                .padding(.leading, 16)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                } else {
                    InlineNotice(text: "No outfit assigned yet.", icon: "exclamationmark.circle", colour: Palette.berry)
                }

                if let warning = item.warning {
                    Text(warning)
                        .font(TypeScale.captionSmall)
                        .foregroundStyle(Palette.danger)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .fill(Palette.surface)
            )
            .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
        .buttonStyle(CardPressStyle())
        .contextMenu {
            Button(role: .destructive) {
                presenter.didTapDelete(item)
            } label: {
                Label("Delete Event", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name), \(item.relativeText), \(item.dressCode.title)\(item.hasOutfit ? "" : ", no outfit")")
    }
}
