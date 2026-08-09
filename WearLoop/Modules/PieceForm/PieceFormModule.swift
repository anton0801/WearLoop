//
//  PieceFormModule.swift
//  WearLoop
//
//  Add and edit a piece. A piece cannot be saved without a name, a category, a
//  colour, a season and an occasion, and the exact missing field is named.
//

import SwiftUI

// MARK: - Contract

/// Outcome of a save: the identifier written, or the reason it failed.
enum SaveOutcome {
    case saved(UUID)
    case failed(String)
}

protocol PieceFormInteractorProtocol: AnyObject {
    func loadPiece(_ id: UUID) -> Piece?
    /// Saves and reports why it failed when it does.
    func save(_ piece: Piece, newImage: UIImage?, removeExistingPhoto: Bool) -> SaveOutcome
    func suggestedStoragePlaces() -> [String]
    func suggestedTags() -> [String]
    func units() -> MeasurementUnits
}

protocol PieceFormRouterProtocol: ModuleRouterProtocol {
    func finish(savedPieceID: UUID, wasEditing: Bool)
    func cancel()
}

struct PieceFormViewState {
    var isEditing: Bool = false
    var pieceID: UUID?

    // Required
    var name: String = ""
    var category: PieceCategory?
    var colours: [PieceColour] = []
    var seasons: [Season] = []
    var occasions: [Occasion] = []

    // Optional
    var material: String = ""
    var size: String = ""
    var condition: PieceCondition = .good
    var storagePlace: String = ""
    var purchasePrice: Double?
    var purchaseDate: Date?
    var weightGrams: Double?
    var tags: [String] = []
    var tagDraft: String = ""
    var careNotes: String = ""
    var privateNote: String = ""

    // Photo
    var newImage: UIImage?
    var existingPhotoID: String?
    var removePhoto: Bool = false

    // Validation
    var nameError: String?
    var categoryError: String?
    var colourError: String?
    var seasonError: String?
    var occasionError: String?
    var saveError: String?

    var isSaving: Bool = false
    var didSave: Bool = false

    var suggestedStoragePlaces: [String] = []
    var suggestedTags: [String] = []
    var units: MeasurementUnits = .metric

    var hasAnyError: Bool {
        nameError != nil || categoryError != nil || colourError != nil
            || seasonError != nil || occasionError != nil
    }

    var previewColour: PieceColour { colours.first ?? .grey }
    var previewInitial: String { name.wlIsBlank ? "?" : name.wlInitial }

    var title: String { isEditing ? "edit piece" : "add piece" }
}

// MARK: - Interactor

final class PieceFormInteractor: PieceFormInteractorProtocol {
    private let repository: WardrobeRepositoryProtocol

    init(repository: WardrobeRepositoryProtocol) {
        self.repository = repository
    }

    func loadPiece(_ id: UUID) -> Piece? {
        repository.state.piece(id)
    }

    func units() -> MeasurementUnits { repository.state.profile.units }

    func suggestedStoragePlaces() -> [String] {
        repository.state.pieces
            .map(\.storagePlace)
            .filter { !$0.wlIsBlank }
            .map { $0.wlTrimmed }
            .wlUnique
            .sorted()
    }

    func suggestedTags() -> [String] {
        repository.state.pieces
            .flatMap(\.tags)
            .wlUnique
            .sorted()
    }

    func save(_ piece: Piece, newImage: UIImage?, removeExistingPhoto: Bool) -> SaveOutcome {
        var updated = piece
        let previousPhotoID = repository.state.piece(piece.id)?.photoID

        // Write the new photograph before touching the document, so a failed
        // image write never produces a piece pointing at a missing file.
        if let newImage {
            guard let newID = repository.savePhoto(newImage) else {
                return .failed("The photo could not be saved. Try again or save the piece without it.")
            }
            updated.photoID = newID
        } else if removeExistingPhoto {
            updated.photoID = nil
        } else {
            updated.photoID = previousPhotoID
        }

        updated.updatedAt = Date()

        let error = repository.mutateThrowing { state in
            if let index = state.pieces.firstIndex(where: { $0.id == updated.id }) {
                // Status and lifecycle are owned by the detail screen, not the form.
                var merged = updated
                merged.status = state.pieces[index].status
                merged.expectedBackDate = state.pieces[index].expectedBackDate
                merged.createdAt = state.pieces[index].createdAt
                state.pieces[index] = merged
                // Condition and the repair list must agree, or a piece could be
                // stuck out of rotation with nothing to fix it in Repairs.
                let hasOpenRepair = state.repairs.contains { $0.pieceID == merged.id && $0.isOpen }
                if merged.condition == .needsRepair {
                    if !hasOpenRepair {
                        WardrobeActions.reportRepair(
                            pieceID: merged.id,
                            issue: "Marked as needing repair",
                            plannedAction: "",
                            in: &state
                        )
                    } else if merged.status == .inRotation {
                        WardrobeActions.setStatus(.needsRepair, pieceID: merged.id, in: &state)
                    }
                } else if merged.status == .needsRepair && !hasOpenRepair {
                    WardrobeActions.setStatus(.inRotation, pieceID: merged.id, in: &state)
                }
            } else {
                state.pieces.append(updated)
                if updated.condition == .needsRepair {
                    WardrobeActions.reportRepair(
                        pieceID: updated.id,
                        issue: "Marked as needing repair",
                        plannedAction: "",
                        in: &state
                    )
                }
            }
        }

        if let error {
            // Roll the orphan photo back so it does not linger on disk.
            if let newID = updated.photoID, newID != previousPhotoID {
                repository.deletePhoto(newID)
            }
            return .failed(error)
        }

        // The old photo is only removed once the new document is safely on disk.
        if let previousPhotoID, previousPhotoID != updated.photoID {
            repository.deletePhoto(previousPhotoID)
        }
        return .saved(updated.id)
    }
}

// MARK: - Presenter

final class PieceFormPresenter: ObservableObject {
    @Published var viewState = PieceFormViewState()

    private let interactor: PieceFormInteractorProtocol
    private let router: PieceFormRouterProtocol
    private let editingID: UUID?

    init(interactor: PieceFormInteractorProtocol, router: PieceFormRouterProtocol, pieceID: UUID?) {
        self.interactor = interactor
        self.router = router
        self.editingID = pieceID
        viewState.isEditing = pieceID != nil
        viewState.pieceID = pieceID
    }

    func onAppear() {
        viewState.suggestedStoragePlaces = interactor.suggestedStoragePlaces()
        viewState.suggestedTags = interactor.suggestedTags()
        viewState.units = interactor.units()

        guard let editingID, let piece = interactor.loadPiece(editingID), !viewState.didSave else { return }
        // Only load once, so a rebuild does not throw away user edits.
        guard viewState.name.isEmpty && viewState.category == nil else { return }

        viewState.name = piece.name
        viewState.category = piece.category
        viewState.colours = piece.colours
        viewState.seasons = piece.seasons
        viewState.occasions = piece.occasions
        viewState.material = piece.material
        viewState.size = piece.size
        viewState.condition = piece.condition
        viewState.storagePlace = piece.storagePlace
        viewState.purchasePrice = piece.purchasePrice
        viewState.purchaseDate = piece.purchaseDate
        viewState.weightGrams = piece.weightGrams
        viewState.tags = piece.tags
        viewState.careNotes = piece.careNotes
        viewState.privateNote = piece.privateNote
        viewState.existingPhotoID = piece.photoID
    }

    // MARK: Field intents

    func setName(_ value: String) {
        viewState.name = value
        if !value.wlIsBlank { viewState.nameError = nil }
    }

    func setCategory(_ value: PieceCategory) {
        viewState.category = value
        viewState.categoryError = nil
    }

    func toggleColour(_ value: PieceColour) {
        viewState.colours.wlToggle(value)
        if !viewState.colours.isEmpty { viewState.colourError = nil }
    }

    func toggleSeason(_ value: Season) {
        viewState.seasons.wlToggle(value)
        if !viewState.seasons.isEmpty { viewState.seasonError = nil }
    }

    func toggleOccasion(_ value: Occasion) {
        viewState.occasions.wlToggle(value)
        if !viewState.occasions.isEmpty { viewState.occasionError = nil }
    }

    func setCondition(_ value: PieceCondition) { viewState.condition = value }

    func addTag() {
        let trimmed = viewState.tagDraft.wlTrimmed
        guard !trimmed.isEmpty, !viewState.tags.contains(trimmed) else {
            viewState.tagDraft = ""
            return
        }
        viewState.tags.append(trimmed)
        viewState.tagDraft = ""
    }

    func addTag(_ tag: String) {
        guard !viewState.tags.contains(tag) else { return }
        viewState.tags.append(tag)
    }

    func removeTag(_ tag: String) {
        viewState.tags.removeAll { $0 == tag }
    }

    func setStoragePlace(_ value: String) { viewState.storagePlace = value }

    func removePhoto() {
        viewState.newImage = nil
        viewState.removePhoto = true
        viewState.existingPhotoID = nil
    }

    // MARK: Save

    func didTapSave() {
        // A second tap while a save is running must not create a duplicate.
        guard !viewState.isSaving, !viewState.didSave else { return }

        viewState.nameError = viewState.name.wlIsBlank ? "Enter a name to continue." : nil
        viewState.categoryError = viewState.category == nil ? "Select a category." : nil
        viewState.colourError = viewState.colours.isEmpty ? "Choose at least one colour." : nil
        viewState.seasonError = viewState.seasons.isEmpty ? "Select at least one season." : nil
        viewState.occasionError = viewState.occasions.isEmpty ? "Select at least one occasion." : nil

        guard !viewState.hasAnyError, let category = viewState.category else { return }

        viewState.isSaving = true
        viewState.saveError = nil

        let piece = Piece(
            id: editingID ?? UUID(),
            name: viewState.name.wlTrimmed,
            category: category,
            colours: viewState.colours,
            seasons: viewState.seasons,
            occasions: viewState.occasions,
            material: viewState.material.wlTrimmed,
            size: viewState.size.wlTrimmed,
            condition: viewState.condition,
            storagePlace: viewState.storagePlace.wlTrimmed,
            purchasePrice: viewState.purchasePrice,
            purchaseDate: viewState.purchaseDate,
            photoID: nil,
            tags: viewState.tags,
            careNotes: viewState.careNotes.wlTrimmed,
            privateNote: viewState.privateNote.wlTrimmed,
            weightGrams: viewState.weightGrams
        )

        let result = interactor.save(
            piece,
            newImage: viewState.newImage,
            removeExistingPhoto: viewState.removePhoto
        )

        viewState.isSaving = false
        switch result {
        case .saved(let id):
            viewState.didSave = true
            router.finish(savedPieceID: id, wasEditing: viewState.isEditing)
        case .failed(let message):
            viewState.saveError = message
        }
    }

    func didTapCancel() {
        router.cancel()
    }
}

// MARK: - Router

final class PieceFormRouter: PieceFormRouterProtocol {
    let coordinator: NavigationCoordinator

    init(coordinator: NavigationCoordinator) {
        self.coordinator = coordinator
    }

    func finish(savedPieceID: UUID, wasEditing: Bool) {
        coordinator.pop()
    }

    func cancel() {
        coordinator.pop()
    }
}

// MARK: - Builder

enum PieceFormBuilder {
    static func build(dependencies: AppDependencies, pieceID: UUID?) -> PieceFormView {
        let interactor = PieceFormInteractor(repository: dependencies.repository)
        let router = PieceFormRouter(coordinator: dependencies.coordinator)
        let presenter = PieceFormPresenter(interactor: interactor, router: router, pieceID: pieceID)
        return PieceFormView(presenter: presenter)
    }
}
