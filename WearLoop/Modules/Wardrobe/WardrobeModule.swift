//
//  WardrobeModule.swift
//  WearLoop
//
//  The single source of pieces. Sections, search and filters live here; a piece
//  is entered once and used by every other part of the app.
//

import Combine
import SwiftUI

// MARK: - Contract

enum WardrobeSection: String, CaseIterable, Identifiable, Hashable {
    case all
    case inRotation
    case inWash
    case needsRepair
    case storedAway
    case archived

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All Pieces"
        case .inRotation: return "In Rotation"
        case .inWash: return "In the Wash"
        case .needsRepair: return "Needs Repair"
        case .storedAway: return "Stored Away"
        case .archived: return "Archived"
        }
    }

    var status: PieceStatus? {
        switch self {
        case .all: return nil
        case .inRotation: return .inRotation
        case .inWash: return .inWash
        case .needsRepair: return .needsRepair
        case .storedAway: return .storedAway
        case .archived: return .archived
        }
    }
}

/// The filter sheet's state.
struct WardrobeFilter: Equatable {
    var categories: [PieceCategory] = []
    var colours: [PieceColour] = []
    var seasons: [Season] = []
    var occasions: [Occasion] = []
    var conditions: [PieceCondition] = []
    var storagePlace: String?
    var neverWornOnly: Bool = false

    var isActive: Bool { activeCount > 0 }

    var activeCount: Int {
        var count = categories.count
        count += colours.count
        count += seasons.count
        count += occasions.count
        count += conditions.count
        if storagePlace != nil { count += 1 }
        if neverWornOnly { count += 1 }
        return count
    }

    mutating func clear() { self = WardrobeFilter() }
}

/// A group of pieces shown as one rail.
struct WardrobeGroup: Identifiable, Equatable {
    var id: String
    var title: String
    var pieces: [Piece]
}

protocol WardrobeInteractorProtocol: AnyObject {
    var repository: WardrobeRepositoryProtocol { get }
    func buildViewState(section: WardrobeSection, search: String, filter: WardrobeFilter) -> WardrobeViewState
    func sendToWash(pieceID: UUID)
    func returnFromWash(pieceID: UUID)
}

protocol WardrobeRouterProtocol: ModuleRouterProtocol {
    func openAddPiece()
    func openPiece(_ id: UUID)
    func openLaundry()
    func openRepairs()
}

struct WardrobeViewState {
    var sectionCounts: [WardrobeSection: Int] = [:]
    var groups: [WardrobeGroup] = []
    var totalMatching: Int = 0
    var totalInWardrobe: Int = 0
    var storagePlaces: [String] = []
    var isEmptyWardrobe: Bool = true
    var isSearching: Bool = false
    var hasActiveFilter: Bool = false
    var showHalftone: Bool = true
    /// Text under the header, e.g. "18 of 42 pieces".
    var summaryText: String = ""
}

// MARK: - Interactor

final class WardrobeInteractor: WardrobeInteractorProtocol {
    let repository: WardrobeRepositoryProtocol

    init(repository: WardrobeRepositoryProtocol) {
        self.repository = repository
    }

    func buildViewState(section: WardrobeSection, search: String, filter: WardrobeFilter) -> WardrobeViewState {
        let state = repository.state
        var view = WardrobeViewState()
        view.showHalftone = state.appearance.showHalftoneMotif
        view.totalInWardrobe = state.pieces.count
        view.isEmptyWardrobe = state.pieces.isEmpty
        view.isSearching = !search.wlIsBlank
        view.hasActiveFilter = filter.isActive

        // Counts for the segment badges.
        for candidate in WardrobeSection.allCases {
            if let status = candidate.status {
                view.sectionCounts[candidate] = state.pieces.filter { $0.status == status }.count
            } else {
                view.sectionCounts[candidate] = state.pieces.count
            }
        }

        view.storagePlaces = state.pieces
            .map(\.storagePlace)
            .filter { !$0.wlIsBlank }
            .map { $0.wlTrimmed }
            .wlUnique
            .sorted()

        // Filter down.
        var pieces = state.pieces
        if let status = section.status {
            pieces = pieces.filter { $0.status == status }
        } else {
            // "All Pieces" keeps archived items out of the way.
            pieces = pieces.filter { $0.status != .archived }
        }

        if !search.wlIsBlank {
            let needle = search.wlTrimmed.lowercased()
            pieces = pieces.filter { $0.searchHaystack.contains(needle) }
        }
        if !filter.categories.isEmpty {
            pieces = pieces.filter { filter.categories.contains($0.category) }
        }
        if !filter.colours.isEmpty {
            pieces = pieces.filter { !Set($0.colours).isDisjoint(with: Set(filter.colours)) }
        }
        if !filter.seasons.isEmpty {
            pieces = pieces.filter { !Set($0.seasons).isDisjoint(with: Set(filter.seasons)) }
        }
        if !filter.occasions.isEmpty {
            pieces = pieces.filter { !Set($0.occasions).isDisjoint(with: Set(filter.occasions)) }
        }
        if !filter.conditions.isEmpty {
            pieces = pieces.filter { filter.conditions.contains($0.condition) }
        }
        if let place = filter.storagePlace {
            pieces = pieces.filter { $0.storagePlace.wlTrimmed.caseInsensitiveCompare(place) == .orderedSame }
        }
        if filter.neverWornOnly {
            pieces = pieces.filter { state.wearCount(forPiece: $0.id) == 0 }
        }

        view.totalMatching = pieces.count

        // Grouped into rails by category, in the order categories are declared.
        view.groups = PieceCategory.allCases.compactMap { category in
            let matching = pieces
                .filter { $0.category == category }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            guard !matching.isEmpty else { return nil }
            return WardrobeGroup(id: category.rawValue, title: category.title, pieces: matching)
        }

        let shownTotal = section.status == nil ? state.pieces.filter { $0.status != .archived }.count : (view.sectionCounts[section] ?? 0)
        view.summaryText = view.totalMatching == shownTotal
            ? Plural.count(view.totalMatching, "piece")
            : "\(view.totalMatching) of \(Plural.count(shownTotal, "piece"))"

        return view
    }

    func sendToWash(pieceID: UUID) {
        repository.mutate { state in
            WardrobeActions.sendToWash(pieceIDs: [pieceID], in: &state)
        }
    }

    func returnFromWash(pieceID: UUID) {
        repository.mutate { state in
            WardrobeActions.returnFromWash(pieceIDs: [pieceID], in: &state)
        }
    }
}

// MARK: - Presenter

final class WardrobePresenter: ObservableObject {
    @Published private(set) var viewState = WardrobeViewState()
    @Published var section: WardrobeSection = .all { didSet { refresh() } }
    @Published var search: String = "" { didSet { refresh() } }
    @Published var filter = WardrobeFilter() { didSet { refresh() } }
    @Published var isFilterPresented = false
    @Published var toast: ToastMessage?

    private let interactor: WardrobeInteractorProtocol
    private let router: WardrobeRouterProtocol
    private var cancellables = Set<AnyCancellable>()

    init(interactor: WardrobeInteractorProtocol, router: WardrobeRouterProtocol) {
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
        viewState = interactor.buildViewState(section: section, search: search, filter: filter)
    }

    func segmentItems() -> [SegmentItem<WardrobeSection>] {
        WardrobeSection.allCases.map { candidate in
            SegmentItem(
                value: candidate,
                title: candidate.title,
                badge: candidate == .all ? nil : viewState.sectionCounts[candidate]
            )
        }
    }

    // MARK: Intents

    func didTapAddPiece() { router.openAddPiece() }
    func didTapPiece(_ id: UUID) { router.openPiece(id) }
    func didTapFilter() { isFilterPresented = true }
    func didTapLaundry() { router.openLaundry() }
    func didTapRepairs() { router.openRepairs() }

    func didTapClearFilters() {
        filter.clear()
        search = ""
        toast = ToastMessage(text: "Filters cleared", kind: .info)
    }

    func didSendToWash(_ id: UUID, name: String) {
        interactor.sendToWash(pieceID: id)
        toast = ToastMessage(
            text: "\(name) sent to the wash",
            kind: .success,
            actionTitle: "Undo",
            action: { [weak self] in self?.interactor.returnFromWash(pieceID: id) }
        )
    }

    func didReturnFromWash(_ id: UUID, name: String) {
        interactor.returnFromWash(pieceID: id)
        toast = ToastMessage(text: "\(name) is back in rotation", kind: .success)
    }
}

// MARK: - Router

final class WardrobeRouter: WardrobeRouterProtocol {
    let coordinator: NavigationCoordinator

    init(coordinator: NavigationCoordinator) {
        self.coordinator = coordinator
    }

    func openAddPiece() { coordinator.push(.pieceForm(pieceID: nil)) }
    func openPiece(_ id: UUID) { coordinator.push(.pieceDetails(id)) }
    func openLaundry() { coordinator.push(.laundry) }
    func openRepairs() { coordinator.push(.repairs) }
}

// MARK: - Builder

enum WardrobeBuilder {
    static func build(dependencies: AppDependencies) -> WardrobeView {
        let interactor = WardrobeInteractor(repository: dependencies.repository)
        let router = WardrobeRouter(coordinator: dependencies.coordinator)
        let presenter = WardrobePresenter(interactor: interactor, router: router)
        return WardrobeView(presenter: presenter)
    }
}
