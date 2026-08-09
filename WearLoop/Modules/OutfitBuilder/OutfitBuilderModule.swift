//
//  OutfitBuilderModule.swift
//  WearLoop
//
//  Building an outfit by layer, laid out on a light board. An outfit needs a
//  name, an occasion and at least two pieces.
//

import SwiftUI

// MARK: - Contract

protocol OutfitBuilderInteractorProtocol: AnyObject {
    func loadOutfit(_ id: UUID) -> Outfit?
    func piece(_ id: UUID) -> Piece?
    /// Pieces that can be put into a layer, available ones first.
    func candidates(for layer: OutfitLayer, excluding used: [UUID]) -> [Piece]
    func derived(pieceIDs: [UUID]) -> (seasons: [Season], min: Double, max: Double, widened: Bool, formality: Formality)
    func save(_ outfit: Outfit) -> SaveOutcome
    func duplicate(_ outfit: Outfit) -> SaveOutcome
    func units() -> MeasurementUnits
    func showHalftone() -> Bool
}

protocol OutfitBuilderRouterProtocol: ModuleRouterProtocol {
    func finish(outfitID: UUID, wasEditing: Bool)
    func cancel()
    func openAddPiece()
}

struct OutfitBuilderViewState {
    var isEditing: Bool = false
    var name: String = ""
    var occasion: Occasion?
    var items: [OutfitItem] = []
    var notes: String = ""

    var seasons: [Season] = []
    var temperatureMin: Double = 5
    var temperatureMax: Double = 20
    var formality: Formality = .casual
    var isRangeManual: Bool = false
    var isSeasonManual: Bool = false
    /// Set when the pieces disagree about the weather and the range was widened.
    var rangeWasWidened: Bool = false

    var isFavorite: Bool = false
    var isArchived: Bool = false

    var nameError: String?
    var occasionError: String?
    var piecesError: String?
    var saveError: String?

    var isSaving: Bool = false
    var didSave: Bool = false

    /// Pieces resolved for the flat-lay, in layer order.
    var boardPieces: [(piece: Piece, layer: OutfitLayer)] = []
    var unavailableIDs: Set<UUID> = []
    var checkNotes: [String] = []

    var units: MeasurementUnits = .metric
    var showHalftone: Bool = true

    var title: String { isEditing ? "edit outfit" : "build outfit" }
    var canSave: Bool { !isSaving && !didSave }
    var pieceCount: Int { items.count }
}

// MARK: - Interactor

final class OutfitBuilderInteractor: OutfitBuilderInteractorProtocol {
    private let repository: WardrobeRepositoryProtocol

    init(repository: WardrobeRepositoryProtocol) {
        self.repository = repository
    }

    func loadOutfit(_ id: UUID) -> Outfit? { repository.state.outfit(id) }
    func piece(_ id: UUID) -> Piece? { repository.state.piece(id) }
    func units() -> MeasurementUnits { repository.state.profile.units }
    func showHalftone() -> Bool { repository.state.appearance.showHalftoneMotif }

    func candidates(for layer: OutfitLayer, excluding used: [UUID]) -> [Piece] {
        let state = repository.state
        return state.pieces
            .filter { layer.allowedCategories.contains($0.category) }
            .filter { $0.status != .archived }
            .filter { !used.contains($0.id) }
            .sorted { a, b in
                // Available pieces first, then alphabetically.
                if a.status.isAvailable != b.status.isAvailable { return a.status.isAvailable }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
    }

    func derived(pieceIDs: [UUID]) -> (seasons: [Season], min: Double, max: Double, widened: Bool, formality: Formality) {
        let state = repository.state
        let range = AvailabilityEngine.derivedTemperatureRange(pieceIDs: pieceIDs, state: state)
        let seasons = AvailabilityEngine.derivedSeasons(pieceIDs: pieceIDs, state: state)
        let formality = AvailabilityEngine.derivedFormality(pieceIDs: pieceIDs, state: state)
        return (seasons, range.min, range.max, range.widened, formality)
    }

    func save(_ outfit: Outfit) -> SaveOutcome {
        var updated = outfit
        updated.updatedAt = Date()
        let error = repository.mutateThrowing { state in
            if let index = state.outfits.firstIndex(where: { $0.id == updated.id }) {
                updated.createdAt = state.outfits[index].createdAt
                state.outfits[index] = updated
            } else {
                state.outfits.append(updated)
            }
            // Any trip that uses this outfit gets a fresh packing list.
            for trip in state.trips where trip.phase != .completed {
                let usesOutfit = trip.days.contains { $0.outfitID == updated.id }
                if usesOutfit {
                    WardrobeActions.refreshPacking(tripID: trip.id, in: &state)
                }
            }
        }
        if let error { return .failed(error) }
        return .saved(updated.id)
    }

    func duplicate(_ outfit: Outfit) -> SaveOutcome {
        var copy = outfit
        copy.id = UUID()
        copy.name = "\(outfit.name) copy"
        copy.createdAt = Date()
        copy.updatedAt = Date()
        copy.isFavorite = false
        copy.items = outfit.items.map { OutfitItem(pieceID: $0.pieceID, layer: $0.layer) }
        let error = repository.mutateThrowing { state in
            state.outfits.append(copy)
        }
        if let error { return .failed(error) }
        return .saved(copy.id)
    }
}

// MARK: - Presenter

final class OutfitBuilderPresenter: ObservableObject {
    @Published var viewState = OutfitBuilderViewState()
    /// The layer whose picker is open.
    @Published var pickerLayer: OutfitLayer?
    @Published var pickerCandidates: [Piece] = []
    /// Set when the picker is swapping an existing piece rather than adding one.
    @Published var swappingItemID: UUID?
    @Published var toast: ToastMessage?

    private let interactor: OutfitBuilderInteractorProtocol
    private let router: OutfitBuilderRouterProtocol
    private let editingID: UUID?
    private let prefillPieceID: UUID?
    private var didLoad = false

    init(
        interactor: OutfitBuilderInteractorProtocol,
        router: OutfitBuilderRouterProtocol,
        outfitID: UUID?,
        prefillPieceID: UUID?
    ) {
        self.interactor = interactor
        self.router = router
        self.editingID = outfitID
        self.prefillPieceID = prefillPieceID
        viewState.isEditing = outfitID != nil
    }

    func onAppear() {
        viewState.units = interactor.units()
        viewState.showHalftone = interactor.showHalftone()
        guard !didLoad else {
            rebuildBoard()
            return
        }
        didLoad = true

        if let editingID, let outfit = interactor.loadOutfit(editingID) {
            viewState.name = outfit.name
            viewState.occasion = outfit.occasion
            viewState.items = outfit.items
            viewState.notes = outfit.notes
            viewState.seasons = outfit.seasons
            viewState.temperatureMin = outfit.temperatureMin
            viewState.temperatureMax = outfit.temperatureMax
            viewState.formality = outfit.formality
            viewState.isRangeManual = outfit.isRangeManual
            viewState.isSeasonManual = outfit.isSeasonManual
            viewState.isFavorite = outfit.isFavorite
            viewState.isArchived = outfit.isArchived
        } else if let prefillPieceID, let piece = interactor.piece(prefillPieceID) {
            viewState.items = [OutfitItem(pieceID: piece.id, layer: piece.category.naturalLayer)]
            recomputeDerived()
        }
        rebuildBoard()
    }

    // MARK: Board

    private func rebuildBoard() {
        var board: [(piece: Piece, layer: OutfitLayer)] = []
        var unavailable = Set<UUID>()
        var notes: [String] = []

        for item in viewState.items {
            guard let piece = interactor.piece(item.pieceID) else { continue }
            board.append((piece, item.layer))
            if !piece.status.isAvailable {
                unavailable.insert(piece.id)
                switch piece.status {
                case .inWash:
                    if let back = piece.expectedBackDate {
                        notes.append("\(piece.name): in the wash until \(DateFormatterCache.relativeDayText(back)).")
                    } else {
                        notes.append("\(piece.name): in the wash.")
                    }
                case .needsRepair:
                    notes.append("\(piece.name): needs repair.")
                case .storedAway:
                    notes.append("\(piece.name): stored away.")
                case .archived:
                    notes.append("\(piece.name): archived.")
                case .inRotation:
                    break
                }
            }
        }

        board.sort { $0.layer.flatLayOrder < $1.layer.flatLayOrder }
        viewState.boardPieces = board
        viewState.unavailableIDs = unavailable

        if notes.isEmpty && !board.isEmpty {
            notes.append("All pieces are in rotation.")
        }
        if viewState.rangeWasWidened {
            notes.append("These pieces suit different weather, so the range was widened. Adjust it by hand if you like.")
        }
        viewState.checkNotes = notes
    }

    private func recomputeDerived() {
        let ids = viewState.items.map(\.pieceID)
        guard !ids.isEmpty else {
            viewState.rangeWasWidened = false
            return
        }
        let derived = interactor.derived(pieceIDs: ids)
        if !viewState.isSeasonManual { viewState.seasons = derived.seasons }
        if !viewState.isRangeManual {
            viewState.temperatureMin = derived.min
            viewState.temperatureMax = derived.max
            viewState.rangeWasWidened = derived.widened
        }
        // Formality follows the pieces until the user picks one themselves.
        if !viewState.isEditing || viewState.formality == .casual {
            viewState.formality = derived.formality
        }
    }

    // MARK: Intents

    func setName(_ value: String) {
        viewState.name = value
        if !value.wlIsBlank { viewState.nameError = nil }
    }

    func setOccasion(_ value: Occasion) {
        viewState.occasion = value
        viewState.occasionError = nil
    }

    func setFormality(_ value: Formality) { viewState.formality = value }

    func toggleSeason(_ season: Season) {
        viewState.isSeasonManual = true
        viewState.seasons.wlToggle(season)
    }

    func setTemperature(min: Double, max: Double) {
        viewState.isRangeManual = true
        viewState.rangeWasWidened = false
        viewState.temperatureMin = min
        viewState.temperatureMax = max
        rebuildBoard()
    }

    func resetDerivedValues() {
        viewState.isRangeManual = false
        viewState.isSeasonManual = false
        recomputeDerived()
        rebuildBoard()
        toast = ToastMessage(text: "Season and range recalculated from the pieces", kind: .info)
    }

    func didTapAddToLayer(_ layer: OutfitLayer) {
        swappingItemID = nil
        pickerCandidates = interactor.candidates(for: layer, excluding: viewState.items.map(\.pieceID))
        pickerLayer = layer
    }

    func didTapSwap(item: OutfitItem) {
        swappingItemID = item.id
        pickerCandidates = interactor.candidates(
            for: item.layer,
            excluding: viewState.items.filter { $0.id != item.id }.map(\.pieceID)
        )
        pickerLayer = item.layer
    }

    func didPickPiece(_ piece: Piece) {
        guard let layer = pickerLayer else { return }
        if let swappingItemID, let index = viewState.items.firstIndex(where: { $0.id == swappingItemID }) {
            viewState.items[index].pieceID = piece.id
        } else {
            viewState.items.append(OutfitItem(pieceID: piece.id, layer: layer))
        }
        viewState.piecesError = nil
        pickerLayer = nil
        swappingItemID = nil
        recomputeDerived()
        rebuildBoard()
    }

    func didDismissPicker() {
        pickerLayer = nil
        swappingItemID = nil
    }

    func didTapRemove(item: OutfitItem) {
        viewState.items.removeAll { $0.id == item.id }
        recomputeDerived()
        rebuildBoard()
    }

    func items(in layer: OutfitLayer) -> [OutfitItem] {
        viewState.items.filter { $0.layer == layer }
    }

    func pieceFor(_ item: OutfitItem) -> Piece? {
        interactor.piece(item.pieceID)
    }

    // MARK: Save

    func didTapSave() {
        guard viewState.canSave else { return }

        viewState.nameError = viewState.name.wlIsBlank ? "Enter a name to continue." : nil
        viewState.occasionError = viewState.occasion == nil ? "Select an occasion." : nil
        viewState.piecesError = viewState.items.count < 2 ? "An outfit needs at least two pieces." : nil

        guard viewState.nameError == nil,
              viewState.occasionError == nil,
              viewState.piecesError == nil,
              let occasion = viewState.occasion else { return }

        viewState.isSaving = true
        viewState.saveError = nil

        let outfit = Outfit(
            id: editingID ?? UUID(),
            name: viewState.name.wlTrimmed,
            occasion: occasion,
            items: viewState.items,
            seasons: viewState.seasons,
            temperatureMin: viewState.temperatureMin,
            temperatureMax: viewState.temperatureMax,
            isRangeManual: viewState.isRangeManual,
            isSeasonManual: viewState.isSeasonManual,
            formality: viewState.formality,
            notes: viewState.notes.wlTrimmed,
            isFavorite: viewState.isFavorite,
            isArchived: viewState.isArchived
        )

        switch interactor.save(outfit) {
        case .saved(let id):
            viewState.isSaving = false
            viewState.didSave = true
            router.finish(outfitID: id, wasEditing: viewState.isEditing)
        case .failed(let message):
            viewState.isSaving = false
            viewState.saveError = message
        }
    }

    func didTapDuplicate() {
        guard let editingID, let outfit = interactor.loadOutfit(editingID) else { return }
        switch interactor.duplicate(outfit) {
        case .saved:
            toast = ToastMessage(text: "Outfit duplicated", kind: .success)
        case .failed(let message):
            toast = ToastMessage(text: message, kind: .failure)
        }
    }

    func didTapCancel() { router.cancel() }
    func didTapAddPiece() { router.openAddPiece() }
}

// MARK: - Router

final class OutfitBuilderRouter: OutfitBuilderRouterProtocol {
    let coordinator: NavigationCoordinator

    init(coordinator: NavigationCoordinator) {
        self.coordinator = coordinator
    }

    func finish(outfitID: UUID, wasEditing: Bool) { coordinator.pop() }
    func cancel() { coordinator.pop() }
    func openAddPiece() { coordinator.jump(to: .wardrobe, then: .pieceForm(pieceID: nil)) }
}

// MARK: - Builder

enum OutfitBuilderBuilder {
    static func build(dependencies: AppDependencies, outfitID: UUID?, prefillPieceID: UUID?) -> OutfitBuilderView {
        let interactor = OutfitBuilderInteractor(repository: dependencies.repository)
        let router = OutfitBuilderRouter(coordinator: dependencies.coordinator)
        let presenter = OutfitBuilderPresenter(
            interactor: interactor,
            router: router,
            outfitID: outfitID,
            prefillPieceID: prefillPieceID
        )
        return OutfitBuilderView(presenter: presenter)
    }
}
