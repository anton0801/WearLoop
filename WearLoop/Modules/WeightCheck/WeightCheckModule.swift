//
//  WeightCheckModule.swift
//  WearLoop
//
//  The luggage gauge and concrete ways to get under the limit — never abstract
//  advice about packing light.
//

import Combine
import SwiftUI

// MARK: - Contract

protocol WeightCheckInteractorProtocol: AnyObject {
    var repository: WardrobeRepositoryProtocol { get }
    func buildViewState(tripID: UUID) -> WeightCheckViewState?
    func setNotPacking(pieceID: UUID, tripID: UUID)
    func setWeight(_ grams: Double?, pieceID: UUID)
    func setManualWeight(_ grams: Double?, entryID: UUID, tripID: UUID)
    func advanceStage(tripID: UUID)
}

protocol WeightCheckRouterProtocol: ModuleRouterProtocol {
    func openReadiness(_ id: UUID)
    func openPackingList(_ id: UUID)
    func openCategoryWeights()
}

struct WeightRefineRow: Identifiable, Equatable {
    var id: UUID
    var name: String
    var currentGrams: Double
    var isEstimate: Bool
    var pieceID: UUID?
    var categoryTitle: String
}

struct WeightCheckViewState {
    var tripName: String = ""
    var estimate: LuggageEstimate
    var weightText: String = ""
    var limitText: String?
    var overText: String?
    var summary: String = ""
    var estimateNote: String?
    var suggestions: [LuggageSuggestion] = []
    var heaviest: [LuggageLine] = []
    var refineRows: [WeightRefineRow] = []
    var estimatedValueText: String?
    var hasLimit: Bool = false
    var units: MeasurementUnits = .metric
    var showHalftone: Bool = true
}

// MARK: - Interactor

final class WeightCheckInteractor: WeightCheckInteractorProtocol {
    let repository: WardrobeRepositoryProtocol

    init(repository: WardrobeRepositoryProtocol) {
        self.repository = repository
    }

    func buildViewState(tripID: UUID) -> WeightCheckViewState? {
        let state = repository.state
        guard let trip = state.trip(tripID) else { return nil }

        let estimate = LuggageEngine.estimate(trip: trip, state: state)
        var view = WeightCheckViewState(estimate: estimate)
        view.tripName = trip.name
        view.units = state.profile.units
        view.showHalftone = state.appearance.showHalftoneMotif
        view.hasLimit = estimate.limitGrams != nil

        view.weightText = UnitFormatter.bagWeight(grams: estimate.totalGrams, units: state.profile.units)
        view.limitText = estimate.limitGrams.map { UnitFormatter.bagWeight(grams: $0, units: state.profile.units) }
        view.overText = estimate.isOverLimit
            ? "Over by \(UnitFormatter.bagWeight(grams: estimate.overByGrams, units: state.profile.units))"
            : nil
        view.summary = LuggageEngine.summarySentence(estimate: estimate, units: state.profile.units)
        view.estimateNote = LuggageEngine.estimateNote(estimate: estimate)
        view.suggestions = LuggageEngine.suggestions(
            trip: trip,
            state: state,
            estimate: estimate,
            units: state.profile.units
        )
        view.heaviest = estimate.heaviest

        if estimate.estimatedValue > 0 {
            view.estimatedValueText = UnitFormatter.money(estimate.estimatedValue)
        }

        // Only lines using a guessed weight need refining.
        view.refineRows = estimate.lines
            .filter(\.isEstimate)
            .sorted { $0.grams > $1.grams }
            .map { line in
                WeightRefineRow(
                    id: line.id,
                    name: line.name,
                    currentGrams: line.grams,
                    isEstimate: true,
                    pieceID: line.pieceID,
                    categoryTitle: line.pieceID
                        .flatMap { state.piece($0)?.category.title }
                        ?? "Added by hand"
                )
            }

        return view
    }

    func setNotPacking(pieceID: UUID, tripID: UUID) {
        repository.mutate { state in
            guard let index = state.trips.firstIndex(where: { $0.id == tripID }) else { return }
            for entryIndex in state.trips[index].packing.indices
            where state.trips[index].packing[entryIndex].pieceID == pieceID {
                state.trips[index].packing[entryIndex].isNotPacking = true
                state.trips[index].packing[entryIndex].isPacked = false
            }
        }
    }

    func setWeight(_ grams: Double?, pieceID: UUID) {
        repository.mutate { state in
            guard let index = state.pieces.firstIndex(where: { $0.id == pieceID }) else { return }
            state.pieces[index].weightGrams = grams
            state.pieces[index].updatedAt = Date()
        }
    }

    func setManualWeight(_ grams: Double?, entryID: UUID, tripID: UUID) {
        repository.mutate { state in
            guard let index = state.trips.firstIndex(where: { $0.id == tripID }),
                  let entryIndex = state.trips[index].packing.firstIndex(where: { $0.id == entryID }) else { return }
            state.trips[index].packing[entryIndex].manualWeightGrams = grams
        }
    }

    func advanceStage(tripID: UUID) {
        repository.mutate { state in
            guard let index = state.trips.firstIndex(where: { $0.id == tripID }) else { return }
            if state.trips[index].stage.order < TripStage.ready.order {
                state.trips[index].stage = .ready
            }
        }
    }
}

// MARK: - Presenter

final class WeightCheckPresenter: ObservableObject {
    @Published private(set) var viewState: WeightCheckViewState?
    @Published private(set) var isMissing = false
    @Published var isRefinePresented = false
    @Published var toast: ToastMessage?

    private let interactor: WeightCheckInteractorProtocol
    private let router: WeightCheckRouterProtocol
    private let tripID: UUID
    private var cancellables = Set<AnyCancellable>()

    init(interactor: WeightCheckInteractorProtocol, router: WeightCheckRouterProtocol, tripID: UUID) {
        self.interactor = interactor
        self.router = router
        self.tripID = tripID
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
        let built = interactor.buildViewState(tripID: tripID)
        viewState = built
        isMissing = built == nil
    }

    func didTapRemove(_ suggestion: LuggageSuggestion) {
        guard let pieceID = suggestion.pieceID else { return }
        interactor.setNotPacking(pieceID: pieceID, tripID: tripID)
        toast = ToastMessage(text: "Moved to Not Packing", kind: .success)
    }

    func didTapRemoveLine(_ line: LuggageLine) {
        guard let pieceID = line.pieceID else { return }
        interactor.setNotPacking(pieceID: pieceID, tripID: tripID)
        toast = ToastMessage(text: "\(line.name) moved to Not Packing", kind: .success)
    }

    func didTapRefine() { isRefinePresented = true }
    func didTapPackingList() { router.openPackingList(tripID) }
    func didTapCategoryWeights() { router.openCategoryWeights() }

    func didSetWeight(_ grams: Double?, row: WeightRefineRow) {
        if let pieceID = row.pieceID {
            interactor.setWeight(grams, pieceID: pieceID)
        } else {
            interactor.setManualWeight(grams, entryID: row.id, tripID: tripID)
        }
    }

    func didTapContinue() {
        interactor.advanceStage(tripID: tripID)
        router.openReadiness(tripID)
    }
}

// MARK: - Router

final class WeightCheckRouter: WeightCheckRouterProtocol {
    let coordinator: NavigationCoordinator

    init(coordinator: NavigationCoordinator) {
        self.coordinator = coordinator
    }

    func openReadiness(_ id: UUID) { coordinator.push(.tripReadiness(id)) }
    func openPackingList(_ id: UUID) { coordinator.push(.packingList(id)) }
    func openCategoryWeights() { coordinator.push(.categoryWeights) }
}

// MARK: - Builder

enum WeightCheckBuilder {
    static func build(dependencies: AppDependencies, tripID: UUID) -> WeightCheckView {
        let interactor = WeightCheckInteractor(repository: dependencies.repository)
        let router = WeightCheckRouter(coordinator: dependencies.coordinator)
        let presenter = WeightCheckPresenter(interactor: interactor, router: router, tripID: tripID)
        return WeightCheckView(presenter: presenter)
    }
}
