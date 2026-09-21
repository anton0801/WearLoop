//
//  TripsView.swift
//  WearLoop
//

import SwiftUI

struct TripsView: View {
    @StateObject var presenter: TripsPresenter

    var body: some View {
        ScreenScaffold {
            ScreenBlock(spacing: 10) {
                ScreenHeader("trips", subtitle: presenter.viewState.summaryText, artwork: .trips) {
                    Button {
                        presenter.didTapCreate()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(IconButtonStyle())
                    .accessibilityLabel("Create a trip")
                }
            }

            SegmentBar(items: presenter.segmentItems(), selection: $presenter.section)

            if presenter.section == .templates {
                templatesContent
            } else {
                tripsContent
            }
        }
        .toast($presenter.toast)
        .confirm($presenter.confirm)
        .onAppear { presenter.onAppear() }
    }

    // MARK: Trips

    @ViewBuilder
    private var tripsContent: some View {
        if presenter.viewState.totalTrips == 0 {
            ScreenBlock {
                EmptyStateView(
                    title: "no trips yet",
                    message: presenter.viewState.hasOutfits
                        ? "Create a trip and the app will build a packing list from your own outfits."
                        : "Create a trip and the app will build a packing list from your outfits. You have no outfits yet, so build one first.",
                    actionTitle: presenter.viewState.hasOutfits ? "Create Trip" : "Build an Outfit",
                    action: {
                        if presenter.viewState.hasOutfits {
                            presenter.didTapCreate()
                        } else {
                            presenter.didTapBuildOutfit()
                        }
                    },
                    secondaryActionTitle: presenter.viewState.hasOutfits ? nil : "Create Trip Anyway",
                    secondaryAction: presenter.viewState.hasOutfits ? nil : { presenter.didTapCreate() },
                    showHalftone: presenter.viewState.showHalftone
                )
            }
        } else if presenter.viewState.items.isEmpty {
            ScreenBlock {
                EmptyStateView(
                    title: "nothing in this section",
                    message: emptyMessage,
                    actionTitle: "Create Trip",
                    action: { presenter.didTapCreate() },
                    showHalftone: presenter.viewState.showHalftone
                )
            }
        } else {
            ScreenBlock(spacing: 12) {
                ForEach(presenter.viewState.items) { item in
                    tripCard(item)
                }
            }
        }
    }

    private func tripCard(_ item: TripListItem) -> some View {
        Button {
            presenter.didTapTrip(item)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name)
                            .font(TypeScale.sectionTitle)
                            .tracking(TypeScale.sectionTitleTracking)
                            .foregroundStyle(Palette.anchor)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(item.destination.isEmpty
                             ? item.dateText
                             : "\(item.destination) · \(item.dateText)")
                            .font(TypeScale.captionSmall)
                            .foregroundStyle(Palette.anchor.opacity(0.6))
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    phaseTag(item)
                }

                Rectangle()
                    .fill(Palette.amber)
                    .frame(height: 4)
                    .frame(maxWidth: 90, alignment: .leading)

                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(item.dayCount)")
                            .font(.system(size: 26, weight: .black).monospacedDigit())
                            .foregroundStyle(Palette.anchor)
                        Text("days")
                            .font(TypeScale.captionSmall)
                            .foregroundStyle(Palette.anchor.opacity(0.55))
                    }
                    if let weight = item.weightText {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(weight)
                                .font(.system(size: 26, weight: .black).monospacedDigit())
                                .foregroundStyle(item.isOverWeight ? Palette.danger : Palette.anchor)
                            Text(item.isOverWeight ? "over limit" : "in the bag")
                                .font(TypeScale.captionSmall)
                                .foregroundStyle(Palette.anchor.opacity(0.55))
                        }
                    }
                    Spacer(minLength: 0)
                }

                Text(item.statusLine)
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.anchor.opacity(0.7))

                if !item.isDraft && item.phase != .completed {
                    ValueBar(
                        fraction: item.readinessTotal > 0
                            ? Double(item.readinessPassed) / Double(item.readinessTotal)
                            : 0,
                        fill: item.readinessPassed == item.readinessTotal ? Palette.success : Palette.amber
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(
                PlateBackground(cornerRadius: Metrics.cardRadius)
                    .halftoneBacking(
                        enabled: presenter.viewState.showHalftone,
                        colour: Palette.gold,
                        opacity: 0.18,
                        focus: .topTrailing,
                        spacing: 28
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            )
            .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
        .buttonStyle(CardPressStyle())
        .contextMenu {
            Button {
                presenter.didTapOpenWorkspace(item.id)
            } label: {
                Label("Open Workspace", systemImage: "square.grid.2x2")
            }
            Button(role: .destructive) {
                presenter.didTapDelete(item)
            } label: {
                Label("Delete Trip", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name), \(item.dateText), \(item.statusLine)")
    }

    private func phaseTag(_ item: TripListItem) -> some View {
        let text: String
        let colour: Color
        if item.isDraft {
            text = "DRAFT"; colour = Palette.anchor
        } else {
            switch item.phase {
            case .inProgress: text = "IN PROGRESS"; colour = Palette.burgundy
            case .completed: text = "COMPLETED"; colour = Palette.success
            case .upcoming: text = "UPCOMING"; colour = Palette.amber
            }
        }
        return StatusTag(
            text: text,
            fill: colour,
            textColour: colour == Palette.amber ? Palette.anchor : .white
        )
    }

    private var emptyMessage: String {
        switch presenter.section {
        case .upcoming: return "No trips are coming up."
        case .inProgress: return "No trip is running right now. A trip moves here once you mark it as ready and start it."
        case .completed: return "No trips have been finished yet."
        case .drafts: return "No unfinished drafts. A trip you leave halfway through the wizard is kept here."
        case .all, .templates: return "Nothing to show."
        }
    }

    // MARK: Templates

    @ViewBuilder
    private var templatesContent: some View {
        if presenter.viewState.templates.isEmpty {
            ScreenBlock {
                EmptyStateView(
                    title: "no templates yet",
                    message: "Finish a trip and save its packing list as a template. The next trip of the same kind starts from it.",
                    actionTitle: "Create Trip",
                    action: { presenter.didTapCreate() },
                    showHalftone: presenter.viewState.showHalftone
                )
            }
        } else {
            ScreenBlock(spacing: 10) {
                ForEach(presenter.viewState.templates) { template in
                    NavigationRow(
                        title: template.name,
                        subtitle: "\(template.tripType.title) · \(Plural.count(template.dayCount, "day")) · \(Plural.count(template.pieceIDs.count, "piece"))",
                        icon: "doc.on.doc",
                        accent: Palette.burgundy
                    ) {
                        presenter.didTapTemplates()
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            presenter.didTapDeleteTemplate(template)
                        } label: {
                            Label("Delete Template", systemImage: "trash")
                        }
                    }
                }
                SecondaryButton(title: "Manage Templates") { presenter.didTapTemplates() }
            }
        }
    }
}
