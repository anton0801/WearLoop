//
//  WardrobeStore.swift
//  WearLoop
//
//  The single source of truth. Interactors read and mutate through the
//  repository protocol; presenters listen for changes and rebuild view state.
//

import Combine
import SwiftUI

/// Where the document is in its life cycle, so every screen can show a real
/// loading and error state instead of pretending the data is there.
enum StoreLoadState: Equatable {
    case loading
    case loaded
    case failed(String)

    var isLoaded: Bool { self == .loaded }
    var errorMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

protocol WardrobeRepositoryProtocol: AnyObject {
    var state: AppState { get }
    var loadState: StoreLoadState { get }
    var changes: AnyPublisher<AppState, Never> { get }

    /// Applies a change and persists it.
    func mutate(_ block: (inout AppState) -> Void)
    /// Applies a change and reports a write failure back to the caller.
    func mutateThrowing(_ block: (inout AppState) -> Void) -> String?

    func load()
    func flush()

    // Photos
    func savePhoto(_ image: UIImage) -> String?
    func photo(_ id: String) -> UIImage?
    func deletePhoto(_ id: String)

    // Data management
    func exportData() throws -> Data
    func importBackup(_ data: Data) throws
    func deleteAllData() throws
    /// Starts again from an empty document, keeping the unreadable one on disk.
    func startFreshAfterFailure() -> String?
    /// Photographs on disk that nothing refers to any more.
    func unusedPhotoCount() -> Int
    @discardableResult
    func cleanUpUnusedPhotos() -> Int
}

final class WardrobeStore: ObservableObject, WardrobeRepositoryProtocol {

    @Published private(set) var stateValue: AppState = AppState()
    @Published private(set) var loadStateValue: StoreLoadState = .loading
    /// Set when a save fails so the UI can tell the truth about it.
    @Published var lastSaveError: String?

    var state: AppState { stateValue }
    var loadState: StoreLoadState { loadStateValue }
    var changes: AnyPublisher<AppState, Never> { $stateValue.eraseToAnyPublisher() }

    private let persistence: PersistenceServiceProtocol
    private let photoStore: PhotoStoreProtocol
    private var saveCancellable: AnyCancellable?
    private let saveTrigger = PassthroughSubject<Void, Never>()

    init(
        persistence: PersistenceServiceProtocol = PersistenceService(),
        photoStore: PhotoStoreProtocol = PhotoStore()
    ) {
        self.persistence = persistence
        self.photoStore = photoStore

        // Writes are coalesced: rapid edits produce one file write.
        saveCancellable = saveTrigger
            .debounce(for: .milliseconds(350), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.performSave() }
    }

    // MARK: - Loading

    func load() {
        loadStateValue = .loading
        let persistence = self.persistence
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<AppState, Error>
            do {
                result = .success(try persistence.load())
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch result {
                case .success(let loaded):
                    self.stateValue = self.migrated(loaded)
                    self.loadStateValue = .loaded
                case .failure(let error):
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    self.loadStateValue = .failed(message)
                }
            }
        }
    }

    /// Fills in anything a document from an older build might be missing.
    private func migrated(_ input: AppState) -> AppState {
        var state = input
        state.schemaVersion = AppState.currentSchemaVersion
        // Category weights must always cover every category.
        for category in PieceCategory.allCases where state.categoryWeights[category] == nil {
            state.categoryWeights[category] = category.defaultWeightGrams
        }
        // A piece marked in the wash but held by nothing is put back in rotation.
        for index in state.pieces.indices where state.pieces[index].status == .inWash {
            let id = state.pieces[index].id
            let held = state.washBasket.contains(id) || state.laundryLoads.contains { $0.pieceIDs.contains(id) }
            if !held {
                state.pieces[index].status = .inRotation
                state.pieces[index].expectedBackDate = nil
            }
        }
        // Day indexes are rebuilt so a trip is never out of order.
        for tripIndex in state.trips.indices {
            for (position, _) in state.trips[tripIndex].days.enumerated() {
                state.trips[tripIndex].days[position].index = position
            }
        }
        return state
    }

    // MARK: - Mutation

    func mutate(_ block: (inout AppState) -> Void) {
        var copy = stateValue
        block(&copy)
        stateValue = copy
        saveTrigger.send()
    }

    /// Same as `mutate` but writes immediately and returns an error message on
    /// failure, for forms that must confirm the save before closing.
    func mutateThrowing(_ block: (inout AppState) -> Void) -> String? {
        var copy = stateValue
        block(&copy)
        do {
            try persistence.save(copy)
            stateValue = copy
            lastSaveError = nil
            return nil
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            lastSaveError = message
            return message
        }
    }

    func flush() { performSave() }

    private func performSave() {
        guard loadStateValue.isLoaded else { return }
        do {
            try persistence.save(stateValue)
            if lastSaveError != nil { lastSaveError = nil }
        } catch {
            lastSaveError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Photos

    func savePhoto(_ image: UIImage) -> String? {
        do {
            return try photoStore.save(image)
        } catch {
            lastSaveError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    func photo(_ id: String) -> UIImage? { photoStore.image(for: id) }

    func deletePhoto(_ id: String) { photoStore.delete(id) }

    /// Photos are never tidied away on their own. A document that was partly
    /// recovered, or an older backup restored later, would otherwise find its
    /// images already deleted — so this only runs when the user asks for it.
    func unusedPhotoCount() -> Int {
        photoStore.orphanCount(keeping: WardrobeActions.referencedPhotoIDs(in: stateValue))
    }

    @discardableResult
    func cleanUpUnusedPhotos() -> Int {
        photoStore.pruneOrphans(keeping: WardrobeActions.referencedPhotoIDs(in: stateValue))
    }

    // MARK: - Data management

    func exportData() throws -> Data {
        try persistence.encode(stateValue)
    }

    func importBackup(_ data: Data) throws {
        let imported = try persistence.decode(data)
        let migratedState = migrated(imported)
        try persistence.save(migratedState)
        stateValue = migratedState
        loadStateValue = .loaded
    }

    /// Called only from the failure screen. The damaged file is renamed rather
    /// than deleted, so a user who wants it back can still get at it.
    func startFreshAfterFailure() -> String? {
        do {
            let movedTo = try persistence.setAsideUnreadableDocument()
            stateValue = AppState()
            loadStateValue = .loaded
            try persistence.save(stateValue)
            return movedTo.lastPathComponent
        } catch {
            loadStateValue = .failed(
                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
            return nil
        }
    }

    func deleteAllData() throws {
        try persistence.wipeEverything()
        photoStore.deleteAll()
        stateValue = AppState()
        loadStateValue = .loaded
    }
}
