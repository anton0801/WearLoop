//
//  WardrobeView.swift
//  WearLoop
//

import SwiftUI

struct WardrobeView: View {
    @StateObject var presenter: WardrobePresenter

    var body: some View {
        ScreenScaffold {
            ScreenBlock(spacing: 10) {
                ScreenHeader("wardrobe", subtitle: presenter.viewState.summaryText) {
                    Button {
                        presenter.didTapAddPiece()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(IconButtonStyle())
                    .accessibilityLabel("Add a piece")
                }
            }

            SegmentBar(items: presenter.segmentItems(), selection: $presenter.section)

            ScreenBlock(spacing: 10) {
                searchRow
                if presenter.viewState.hasActiveFilter || presenter.viewState.isSearching {
                    activeFilterRow
                }
            }

            content
        }
        .sheet(isPresented: $presenter.isFilterPresented) {
            WardrobeFilterSheet(
                filter: $presenter.filter,
                storagePlaces: presenter.viewState.storagePlaces
            )
        }
        .toast($presenter.toast)
        .onAppear { presenter.onAppear() }
    }

    // MARK: Search

    private var searchRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Palette.anchor.opacity(0.45))
                TextField("Search Pieces", text: $presenter.search)
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.anchor)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
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

            Button {
                presenter.didTapFilter()
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(presenter.viewState.hasActiveFilter ? Palette.onAnchor : Palette.anchor)
                        .frame(width: 48, height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(presenter.viewState.hasActiveFilter ? Palette.anchor : Palette.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Palette.anchor.opacity(presenter.viewState.hasActiveFilter ? 0 : 0.2), lineWidth: 2)
                        )
                    if presenter.filter.activeCount > 0 {
                        Text("\(presenter.filter.activeCount)")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Palette.berry))
                            .offset(x: 4, y: -4)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(presenter.filter.activeCount > 0 ? "Filter, \(presenter.filter.activeCount) active" : "Filter")
        }
    }

    private var activeFilterRow: some View {
        HStack(spacing: 8) {
            Text(presenter.viewState.summaryText)
                .font(TypeScale.captionSmall)
                .foregroundStyle(Palette.anchor.opacity(0.6))
            Spacer(minLength: 0)
            Button("Clear Filters") { presenter.didTapClearFilters() }
                .buttonStyle(CompactOutlineButtonStyle())
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if presenter.viewState.isEmptyWardrobe {
            ScreenBlock {
                EmptyStateView(
                    title: "nothing here yet",
                    message: "Add your first piece: a photograph, a category, its colours, seasons and occasions.",
                    actionTitle: "Add First Piece",
                    action: { presenter.didTapAddPiece() },
                    showHalftone: presenter.viewState.showHalftone
                )
            }
        } else if presenter.viewState.groups.isEmpty {
            ScreenBlock {
                EmptyStateView(
                    title: "nothing matches",
                    message: emptyMatchMessage,
                    actionTitle: presenter.viewState.hasActiveFilter || presenter.viewState.isSearching ? "Clear Filters" : "Add a Piece",
                    action: {
                        if presenter.viewState.hasActiveFilter || presenter.viewState.isSearching {
                            presenter.didTapClearFilters()
                        } else {
                            presenter.didTapAddPiece()
                        }
                    },
                    showHalftone: presenter.viewState.showHalftone
                )
                sectionShortcut
            }
        } else {
            VStack(alignment: .leading, spacing: Metrics.sectionGap) {
                ForEach(presenter.viewState.groups) { group in
                    RailSection(
                        title: group.title,
                        items: group.pieces
                    ) { piece in
                        PieceCard(
                            piece: piece,
                            statusText: statusText(for: piece),
                            width: Metrics.railCardWidth
                        ) {
                            presenter.didTapPiece(piece.id)
                        }
                        .contextMenu {
                            contextActions(for: piece)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var sectionShortcut: some View {
        switch presenter.section {
        case .inWash:
            SecondaryButton(title: "Open the Laundry Loop") { presenter.didTapLaundry() }
        case .needsRepair:
            SecondaryButton(title: "Open Repairs and Care") { presenter.didTapRepairs() }
        default:
            EmptyView()
        }
    }

    private var emptyMatchMessage: String {
        if presenter.viewState.isSearching || presenter.viewState.hasActiveFilter {
            return "No pieces match this search and filter combination. Clear them to see the rest of your wardrobe."
        }
        switch presenter.section {
        case .inWash: return "Nothing is in the wash. Send a piece from its detail screen when it needs washing."
        case .needsRepair: return "Nothing needs repair right now."
        case .storedAway: return "Nothing is stored away. Use it for out-of-season pieces you still own."
        case .archived: return "Nothing has been archived. Archiving keeps a piece's history without cluttering the wardrobe."
        case .inRotation: return "Nothing is in rotation. Return a piece from the wash or from storage."
        case .all: return "No pieces yet."
        }
    }

    private func statusText(for piece: Piece) -> String {
        switch piece.status {
        case .inWash:
            if let back = piece.expectedBackDate {
                return "Back \(DateFormatterCache.relativeDayText(back))"
            }
            return "In the wash"
        case .needsRepair: return "Needs repair"
        case .storedAway: return "Stored away"
        case .archived: return "Archived"
        case .inRotation:
            return piece.colours.first?.title ?? piece.category.title
        }
    }

    @ViewBuilder
    private func contextActions(for piece: Piece) -> some View {
        Button {
            presenter.didTapPiece(piece.id)
        } label: {
            Label("Open Details", systemImage: "arrow.up.right.square")
        }
        if piece.status == .inRotation {
            Button {
                presenter.didSendToWash(piece.id, name: piece.name)
            } label: {
                Label("Send to Wash", systemImage: "drop.fill")
            }
        }
        if piece.status == .inWash {
            Button {
                presenter.didReturnFromWash(piece.id, name: piece.name)
            } label: {
                Label("Return From Wash", systemImage: "arrow.uturn.backward")
            }
        }
    }
}

// MARK: - Filter sheet

struct WardrobeFilterSheet: View {
    @Binding var filter: WardrobeFilter
    let storagePlaces: [String]

    @Environment(\.dismiss) private var dismiss
    @State private var draft = WardrobeFilter()

    var body: some View {
        NavigationStack {
            ScreenScaffold(bottomInset: 24) {
                ScreenBlock(spacing: 22) {
                    ScreenHeader("filter", subtitle: draft.isActive ? "\(draft.activeCount) active" : "Nothing selected")

                    FieldFrame(label: "Category") {
                        ChipGroup(
                            values: PieceCategory.allCases,
                            title: { $0.title },
                            accent: Palette.anchor,
                            isSelected: { draft.categories.contains($0) },
                            onTap: { draft.categories.wlToggle($0) }
                        )
                    }

                    FieldFrame(label: "Colour") {
                        ChipGroup(
                            values: PieceColour.allCases,
                            title: { $0.title },
                            swatch: { $0.colour },
                            accent: Palette.anchor,
                            isSelected: { draft.colours.contains($0) },
                            onTap: { draft.colours.wlToggle($0) }
                        )
                    }

                    FieldFrame(label: "Season") {
                        ChipGroup(
                            values: Season.allCases,
                            title: { $0.title },
                            accent: Palette.amber,
                            isSelected: { draft.seasons.contains($0) },
                            onTap: { draft.seasons.wlToggle($0) }
                        )
                    }

                    FieldFrame(label: "Occasion") {
                        ChipGroup(
                            values: Occasion.allCases,
                            title: { $0.title },
                            accent: Palette.berry,
                            isSelected: { draft.occasions.contains($0) },
                            onTap: { draft.occasions.wlToggle($0) }
                        )
                    }

                    FieldFrame(label: "Condition") {
                        ChipGroup(
                            values: PieceCondition.allCases,
                            title: { $0.title },
                            accent: Palette.anchor,
                            isSelected: { draft.conditions.contains($0) },
                            onTap: { draft.conditions.wlToggle($0) }
                        )
                    }

                    if !storagePlaces.isEmpty {
                        FieldFrame(label: "Storage Place") {
                            WrappingHStack {
                                ForEach(storagePlaces, id: \.self) { place in
                                    ChipView(
                                        title: place,
                                        isSelected: draft.storagePlace == place,
                                        accent: Palette.anchor
                                    ) {
                                        draft.storagePlace = draft.storagePlace == place ? nil : place
                                    }
                                }
                            }
                        }
                    }

                    WLToggleRow(
                        title: "Never Worn",
                        subtitle: "Only pieces with no wear records at all.",
                        isOn: $draft.neverWornOnly
                    )

                    VStack(spacing: 10) {
                        PrimaryButton(title: "Apply") {
                            filter = draft
                            dismiss()
                        }
                        SecondaryButton(title: "Clear Filters") {
                            draft.clear()
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Palette.anchor)
                }
            }
        }
        .onAppear { draft = filter }
    }
}
