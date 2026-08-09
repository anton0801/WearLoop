//
//  OutfitsView.swift
//  WearLoop
//

import SwiftUI

struct OutfitsView: View {
    @StateObject var presenter: OutfitsPresenter

    var body: some View {
        ScreenScaffold {
            ScreenBlock(spacing: 10) {
                ScreenHeader("outfits", subtitle: presenter.viewState.summaryText) {
                    Button {
                        presenter.didTapBuild()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(IconButtonStyle())
                    .accessibilityLabel("Build an outfit")
                    .disabled(!presenter.viewState.canBuild)
                    .opacity(presenter.viewState.canBuild ? 1 : 0.4)
                }
            }

            SegmentBar(items: presenter.segmentItems(), selection: $presenter.section)

            ScreenBlock {
                searchRow
            }

            content
        }
        .toast($presenter.toast)
        .onAppear { presenter.onAppear() }
    }

    private var searchRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Palette.anchor.opacity(0.45))
            TextField("Search outfits and pieces", text: $presenter.search)
                .font(TypeScale.body)
                .foregroundStyle(Palette.anchor)
                .autocorrectionDisabled()
            if !presenter.search.isEmpty {
                Button {
                    presenter.search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.anchor.opacity(0.35))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.surface))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.anchor.opacity(0.2), lineWidth: 2)
        )
    }

    @ViewBuilder
    private var content: some View {
        if !presenter.viewState.hasPieces {
            ScreenBlock {
                EmptyStateView(
                    title: "no pieces to build with",
                    message: "An outfit is made of pieces from your wardrobe. Add a few first.",
                    actionTitle: "Add First Piece",
                    action: { presenter.didTapAddPiece() },
                    showHalftone: presenter.viewState.showHalftone
                )
            }
        } else if presenter.viewState.totalOutfits == 0 {
            ScreenBlock {
                EmptyStateView(
                    title: "no outfits yet",
                    message: presenter.viewState.canBuild
                        ? "Outfits are what the app plans and packs with. One piece can live in as many outfits as you like."
                        : "An outfit needs at least two pieces that are in rotation. You have \(Plural.count(presenter.viewState.availablePieceCount, "piece")) available.",
                    actionTitle: presenter.viewState.canBuild ? "Build First Outfit" : "Add Another Piece",
                    action: {
                        if presenter.viewState.canBuild {
                            presenter.didTapBuild()
                        } else {
                            presenter.didTapAddPiece()
                        }
                    },
                    showHalftone: presenter.viewState.showHalftone
                )
            }
        } else if presenter.viewState.groups.isEmpty {
            ScreenBlock {
                EmptyStateView(
                    title: "nothing in this section",
                    message: emptySectionMessage,
                    actionTitle: sectionActionTitle,
                    action: sectionAction,
                    showHalftone: presenter.viewState.showHalftone
                )
            }
        } else {
            VStack(alignment: .leading, spacing: Metrics.sectionGap) {
                ForEach(presenter.viewState.groups) { group in
                    RailSection(
                        title: group.title,
                        accent: Palette.berry,
                        items: group.items
                    ) { item in
                        OutfitCard(
                            outfit: item.outfit,
                            pieces: item.pieces,
                            status: item.status,
                            subtitle: item.subtitle,
                            isDimmed: item.outfit.isArchived
                        ) {
                            presenter.didTapOutfit(item.outfit.id)
                        }
                        .contextMenu {
                            Button {
                                presenter.didTapOutfit(item.outfit.id)
                            } label: {
                                Label("Open Outfit", systemImage: "arrow.up.right.square")
                            }
                            Button {
                                presenter.didToggleFavorite(
                                    item.outfit.id,
                                    name: item.outfit.name,
                                    wasFavorite: item.outfit.isFavorite
                                )
                            } label: {
                                Label(
                                    item.outfit.isFavorite ? "Remove From Favorites" : "Add to Favorites",
                                    systemImage: item.outfit.isFavorite ? "heart.slash" : "heart"
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptySectionMessage: String {
        if presenter.viewState.isSearching {
            return "No outfit matches this search."
        }
        switch presenter.section {
        case .readyToWear:
            return "No outfit is fully available right now. Return something from the wash and it comes back here."
        case .partlyInWash:
            return "Nothing is held up by the wash. Every outfit you own is complete."
        case .favorites:
            return "No favourites yet. Mark the outfits you reach for most and they gather here."
        case .archived:
            return "Nothing is archived. Archiving hides an outfit without losing its history."
        case .byOccasion, .all:
            return "No outfits to show."
        }
    }

    private var sectionActionTitle: String {
        switch presenter.section {
        case .readyToWear, .partlyInWash: return "Open the Laundry Loop"
        default: return "Build an Outfit"
        }
    }

    private func sectionAction() {
        switch presenter.section {
        case .readyToWear, .partlyInWash: presenter.didTapLaundry()
        default: presenter.didTapBuild()
        }
    }
}
