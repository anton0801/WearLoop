//
//  OutfitsModule.swift
//  WearLoop
//
//  Outfits with their live availability. An outfit whose piece is in the wash is
//  never hidden — it says so and shows the return date.
//

import Combine
import SwiftUI

// MARK: - Contract

enum OutfitSection: String, CaseIterable, Identifiable, Hashable {
    case all
    case readyToWear
    case partlyInWash
    case byOccasion
    case favorites
    case archived

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All Outfits"
        case .readyToWear: return "Ready to Wear"
        case .partlyInWash: return "Partly in the Wash"
        case .byOccasion: return "By Occasion"
        case .favorites: return "Favorites"
        case .archived: return "Archived"
        }
    }
}

/// An outfit with everything the list needs to draw it.
struct OutfitListItem: Identifiable, Equatable {
    var id: UUID { outfit.id }
    var outfit: Outfit
    var pieces: [Piece]
    var status: OutfitStatus
    var subtitle: String

    static func == (lhs: OutfitListItem, rhs: OutfitListItem) -> Bool {
        lhs.outfit == rhs.outfit && lhs.pieces == rhs.pieces && lhs.status == rhs.status && lhs.subtitle == rhs.subtitle
    }
}

struct OutfitGroup: Identifiable, Equatable {
    var id: String
    var title: String
    var items: [OutfitListItem]
}

protocol OutfitsInteractorProtocol: AnyObject {
    var repository: WardrobeRepositoryProtocol { get }
    func buildViewState(section: OutfitSection, search: String) -> OutfitsViewState
    func toggleFavorite(_ id: UUID)
}

protocol OutfitsRouterProtocol: ModuleRouterProtocol {
    func openBuilder(outfitID: UUID?)
    func openOutfit(_ id: UUID)
    func openAddPiece()
    func openLaundry()
}

struct OutfitsViewState {
    var groups: [OutfitGroup] = []
    var sectionCounts: [OutfitSection: Int] = [:]
    var totalOutfits: Int = 0
    var hasPieces: Bool = false
    var canBuild: Bool = false
    var availablePieceCount: Int = 0
    var summaryText: String = ""
    var isSearching: Bool = false
    var showHalftone: Bool = true
}

// MARK: - Interactor

final class OutfitsInteractor: OutfitsInteractorProtocol {
    let repository: WardrobeRepositoryProtocol

    init(repository: WardrobeRepositoryProtocol) {
        self.repository = repository
    }

    func buildViewState(section: OutfitSection, search: String) -> OutfitsViewState {
        let state = repository.state
        var view = OutfitsViewState()
        view.showHalftone = state.appearance.showHalftoneMotif
        view.totalOutfits = state.outfits.count
        view.hasPieces = !state.activePieces.isEmpty
        view.availablePieceCount = state.availablePieces.count
        view.canBuild = state.availablePieces.count >= 2
        view.isSearching = !search.wlIsBlank

        // Build the list items once, then reuse them for counts and groups.
        let allItems: [OutfitListItem] = state.outfits.map { outfit in
            let check = AvailabilityEngine.check(outfit: outfit, state: state)
            let pieces = outfit.items.compactMap { state.piece($0.pieceID) }
            return OutfitListItem(
                outfit: outfit,
                pieces: pieces,
                status: check.status,
                subtitle: subtitle(for: outfit, check: check, state: state)
            )
        }

        view.sectionCounts[.all] = allItems.filter { !$0.outfit.isArchived }.count
        view.sectionCounts[.readyToWear] = allItems.filter { !$0.outfit.isArchived && $0.status == .ready }.count
        view.sectionCounts[.partlyInWash] = allItems.filter { !$0.outfit.isArchived && !$0.outfit.isArchived && $0.status == .partlyUnavailable }.count
        view.sectionCounts[.byOccasion] = allItems.filter { !$0.outfit.isArchived }.count
        view.sectionCounts[.favorites] = allItems.filter { !$0.outfit.isArchived && $0.outfit.isFavorite }.count
        view.sectionCounts[.archived] = allItems.filter { $0.outfit.isArchived }.count

        var filtered: [OutfitListItem]
        switch section {
        case .all, .byOccasion:
            filtered = allItems.filter { !$0.outfit.isArchived }
        case .readyToWear:
            filtered = allItems.filter { !$0.outfit.isArchived && $0.status == .ready }
        case .partlyInWash:
            filtered = allItems.filter { !$0.outfit.isArchived && $0.status == .partlyUnavailable }
        case .favorites:
            filtered = allItems.filter { !$0.outfit.isArchived && $0.outfit.isFavorite }
        case .archived:
            filtered = allItems.filter { $0.outfit.isArchived }
        }

        if !search.wlIsBlank {
            let needle = search.wlTrimmed.lowercased()
            filtered = filtered.filter { item in
                item.outfit.name.lowercased().contains(needle)
                    || item.outfit.occasion.title.lowercased().contains(needle)
                    || item.pieces.contains { $0.name.lowercased().contains(needle) }
            }
        }

        // Grouping
        if section == .byOccasion {
            view.groups = Occasion.allCases.compactMap { occasion in
                let matching = filtered
                    .filter { $0.outfit.occasion == occasion }
                    .sorted { $0.outfit.name.localizedCaseInsensitiveCompare($1.outfit.name) == .orderedAscending }
                guard !matching.isEmpty else { return nil }
                return OutfitGroup(id: occasion.rawValue, title: occasion.title, items: matching)
            }
        } else {
            let sorted = filtered.sorted { a, b in
                if a.outfit.isFavorite != b.outfit.isFavorite { return a.outfit.isFavorite }
                return a.outfit.updatedAt > b.outfit.updatedAt
            }
            view.groups = sorted.isEmpty ? [] : [OutfitGroup(id: "all", title: section.title, items: sorted)]
        }

        let shown = filtered.count
        view.summaryText = Plural.count(shown, "outfit")
        return view
    }

    private func subtitle(for outfit: Outfit, check: OutfitCheck, state: AppState) -> String {
        switch check.status {
        case .ready:
            return "\(outfit.occasion.title) · \(Plural.count(outfit.items.count, "piece"))"
        case .partlyUnavailable:
            if let back = check.earliestReturn {
                return "Back \(DateFormatterCache.relativeDayText(back))"
            }
            return "\(Plural.count(check.unavailablePieceIDs.count, "piece")) unavailable"
        case .needsRepair:
            return "\(Plural.count(check.needsRepairPieceIDs.count, "piece")) need repair"
        case .outOfSeason:
            return "Set for \(outfit.seasons.map(\.title).joined(separator: ", ").lowercased())"
        }
    }

    func toggleFavorite(_ id: UUID) {
        repository.mutate { state in
            guard let index = state.outfits.firstIndex(where: { $0.id == id }) else { return }
            state.outfits[index].isFavorite.toggle()
        }
    }
}

// MARK: - Presenter

final class OutfitsPresenter: ObservableObject {
    @Published private(set) var viewState = OutfitsViewState()
    @Published var section: OutfitSection = .all { didSet { refresh() } }
    @Published var search: String = "" { didSet { refresh() } }
    @Published var toast: ToastMessage?

    private let interactor: OutfitsInteractorProtocol
    private let router: OutfitsRouterProtocol
    private var cancellables = Set<AnyCancellable>()

    init(interactor: OutfitsInteractorProtocol, router: OutfitsRouterProtocol) {
        self.interactor = interactor
        self.router = router
    }

    func onAppear() {
        observeStoreIfNeeded()
        refresh()
    }

    /// The store is observed from the first appearance rather than from init,
    /// so a presenter built during a re-render and immediately discarded never
    /// does the work of rebuilding view state.
    private func observeStoreIfNeeded() {
        guard cancellables.isEmpty else { return }
        interactor.repository.changes
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    private func refresh() {
        viewState = interactor.buildViewState(section: section, search: search)
    }

    func segmentItems() -> [SegmentItem<OutfitSection>] {
        OutfitSection.allCases.map { candidate in
            SegmentItem(
                value: candidate,
                title: candidate.title,
                badge: candidate == .all || candidate == .byOccasion ? nil : viewState.sectionCounts[candidate]
            )
        }
    }

    func didTapBuild() { router.openBuilder(outfitID: nil) }
    func didTapOutfit(_ id: UUID) { router.openOutfit(id) }
    func didTapAddPiece() { router.openAddPiece() }
    func didTapLaundry() { router.openLaundry() }

    func didToggleFavorite(_ id: UUID, name: String, wasFavorite: Bool) {
        interactor.toggleFavorite(id)
        toast = ToastMessage(
            text: wasFavorite ? "\(name) removed from favourites" : "\(name) added to favourites",
            kind: .info
        )
    }
}

// MARK: - Router

final class OutfitsRouter: OutfitsRouterProtocol {
    let coordinator: NavigationCoordinator

    init(coordinator: NavigationCoordinator) {
        self.coordinator = coordinator
    }

    func openBuilder(outfitID: UUID?) {
        coordinator.push(.outfitBuilder(outfitID: outfitID, prefillPieceID: nil))
    }
    func openOutfit(_ id: UUID) { coordinator.push(.outfitDetails(id)) }
    func openAddPiece() { coordinator.jump(to: .wardrobe, then: .pieceForm(pieceID: nil)) }
    func openLaundry() { coordinator.push(.laundry) }
}

// MARK: - Builder

enum OutfitsBuilder {
    static func build(dependencies: AppDependencies) -> OutfitsView {
        let interactor = OutfitsInteractor(repository: dependencies.repository)
        let router = OutfitsRouter(coordinator: dependencies.coordinator)
        let presenter = OutfitsPresenter(interactor: interactor, router: router)
        return OutfitsView(presenter: presenter)
    }
}
