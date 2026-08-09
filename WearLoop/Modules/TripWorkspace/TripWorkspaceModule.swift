//
//  TripWorkspaceModule.swift
//  WearLoop
//
//  The hub of a trip. The stage indicator only lets the user move on when the
//  previous stage genuinely allows it, and says why when it does not.
//

import Combine
import SwiftUI

// MARK: - Contract

protocol TripWorkspaceInteractorProtocol: AnyObject {
    var repository: WardrobeRepositoryProtocol { get }
    func buildViewState(tripID: UUID, now: Date) -> TripWorkspaceViewState?
    func setStage(_ stage: TripStage, tripID: UUID)
    func markReady(tripID: UUID)
    func startTrip(tripID: UUID)
    func setConditionsReviewed(tripID: UUID)
    func refreshPacking(tripID: UUID)
}

protocol TripWorkspaceRouterProtocol: ModuleRouterProtocol {
    func openDayPlan(_ id: UUID)
    func openPackingList(_ id: UUID)
    func openWeightCheck(_ id: UUID)
    func openReadiness(_ id: UUID)
    func openTripMode(_ id: UUID)
    func openRecap(_ id: UUID)
    func openEdit(_ id: UUID)
    func openLaundry()
    func openRepairs()
}

struct TripWorkspaceViewState {
    var trip: Trip
    var readiness: TripReadiness
    var coverage: TripCoverage
    var estimate: LuggageEstimate
    var weightText: String
    var limitText: String?
    var isOverLimit: Bool
    var overText: String?
    var reachableStages: Set<TripStage> = []
    var blockReasons: [TripStage: String] = [:]
    var outsideConditionOutfits: [String] = []
    var units: MeasurementUnits = .metric
    var showHalftone: Bool = true
    var daysNeedingPlanText: String?
    var canMarkReady: Bool = false
    var canStart: Bool = false
}

// MARK: - Interactor

final class TripWorkspaceInteractor: TripWorkspaceInteractorProtocol {
    let repository: WardrobeRepositoryProtocol

    init(repository: WardrobeRepositoryProtocol) {
        self.repository = repository
    }

    func buildViewState(tripID: UUID, now: Date) -> TripWorkspaceViewState? {
        let state = repository.state
        guard let trip = state.trip(tripID) else { return nil }

        let readiness = TripReadinessEngine.readiness(trip: trip, state: state, now: now)
        let coverage = TripPlanEngine.coverage(trip: trip, state: state)
        let estimate = LuggageEngine.estimate(trip: trip, state: state)

        var view = TripWorkspaceViewState(
            trip: trip,
            readiness: readiness,
            coverage: coverage,
            estimate: estimate,
            weightText: UnitFormatter.bagWeight(grams: estimate.totalGrams, units: state.profile.units),
            limitText: estimate.limitGrams.map { UnitFormatter.bagWeight(grams: $0, units: state.profile.units) },
            isOverLimit: estimate.isOverLimit,
            overText: estimate.isOverLimit
                ? "Over by \(UnitFormatter.bagWeight(grams: estimate.overByGrams, units: state.profile.units))"
                : nil
        )
        view.units = state.profile.units
        view.showHalftone = state.appearance.showHalftoneMotif

        for stage in TripStage.allCases {
            if let reason = TripReadinessEngine.blockReason(for: stage, trip: trip, state: state) {
                view.blockReasons[stage] = reason
            } else {
                view.reachableStages.insert(stage)
            }
        }

        let outsideIDs = TripPlanEngine.outfitsOutsideConditions(trip: trip, state: state)
        view.outsideConditionOutfits = outsideIDs.compactMap { state.outfit($0)?.name }

        let unplanned = trip.daysWithoutPlan
        if !unplanned.isEmpty {
            view.daysNeedingPlanText = "\(Plural.days(unplanned.map(\.dayNumber))) need an outfit or an Undecided mark."
        }

        view.canMarkReady = readiness.isReady && trip.stage != .inProgress && trip.recap == nil
        view.canStart = trip.stage == .ready || trip.stage == .inProgress

        return view
    }

    func setStage(_ stage: TripStage, tripID: UUID) {
        repository.mutate { state in
            guard let index = state.trips.firstIndex(where: { $0.id == tripID }) else { return }
            state.trips[index].stage = stage
            state.trips[index].updatedAt = Date()
        }
    }

    func markReady(tripID: UUID) {
        repository.mutate { state in
            guard let index = state.trips.firstIndex(where: { $0.id == tripID }) else { return }
            state.trips[index].stage = .ready
            state.trips[index].isDraft = false
            state.trips[index].updatedAt = Date()
        }
    }

    func startTrip(tripID: UUID) {
        repository.mutate { state in
            guard let index = state.trips.firstIndex(where: { $0.id == tripID }) else { return }
            state.trips[index].stage = .inProgress
            state.trips[index].isDraft = false
            state.trips[index].updatedAt = Date()
        }
    }

    func setConditionsReviewed(tripID: UUID) {
        repository.mutate { state in
            guard let index = state.trips.firstIndex(where: { $0.id == tripID }) else { return }
            state.trips[index].conditionsReviewed = true
        }
    }

    func refreshPacking(tripID: UUID) {
        repository.mutate { state in
            WardrobeActions.refreshPacking(tripID: tripID, in: &state)
            WardrobeActions.syncEssentials(tripID: tripID, in: &state)
        }
    }
}

// MARK: - Presenter

final class TripWorkspacePresenter: ObservableObject {
    @Published private(set) var viewState: TripWorkspaceViewState?
    @Published private(set) var isMissing = false
    @Published var toast: ToastMessage?
    @Published var confirm: ConfirmRequest?

    private let interactor: TripWorkspaceInteractorProtocol
    private let router: TripWorkspaceRouterProtocol
    private let tripID: UUID
    private var cancellables = Set<AnyCancellable>()

    init(interactor: TripWorkspaceInteractorProtocol, router: TripWorkspaceRouterProtocol, tripID: UUID) {
        self.interactor = interactor
        self.router = router
        self.tripID = tripID
    }

    func onAppear() {
        observeStoreIfNeeded()
        // Keep the packing list in step with whatever changed elsewhere.
        interactor.refreshPacking(tripID: tripID)
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
        let built = interactor.buildViewState(tripID: tripID, now: Date())
        viewState = built
        isMissing = built == nil
    }

    // MARK: Intents

    func didSelectStage(_ stage: TripStage) {
        guard let state = viewState else { return }
        if let reason = state.blockReasons[stage] {
            toast = ToastMessage(text: reason, kind: .failure)
            return
        }
        switch stage {
        case .setup: router.openEdit(tripID)
        case .dayPlan: router.openDayPlan(tripID)
        case .packingList: router.openPackingList(tripID)
        case .weightCheck: router.openWeightCheck(tripID)
        case .ready: router.openReadiness(tripID)
        case .inProgress: router.openTripMode(tripID)
        case .recap: router.openRecap(tripID)
        }
    }

    func didTapDayPlan() { didSelectStage(.dayPlan) }
    func didTapPacking() { didSelectStage(.packingList) }
    func didTapWeight() { didSelectStage(.weightCheck) }
    func didTapReadiness() { didSelectStage(.ready) }
    func didTapEdit() { router.openEdit(tripID) }
    func didTapRecap() { router.openRecap(tripID) }
    func didTapLaundry() { router.openLaundry() }
    func didTapRepairs() { router.openRepairs() }

    func didTapReadinessItem(_ item: ReadinessItem) {
        switch item.target {
        case .dayPlan: router.openDayPlan(tripID)
        case .packingList: router.openPackingList(tripID)
        case .weightCheck: router.openWeightCheck(tripID)
        case .laundry: router.openLaundry()
        case .repairs: router.openRepairs()
        case .conditions:
            interactor.setConditionsReviewed(tripID: tripID)
            toast = ToastMessage(text: "Conditions marked as reviewed", kind: .success)
        }
    }

    func didTapMarkReady() {
        guard let state = viewState else { return }
        guard state.readiness.isReady else {
            router.openReadiness(tripID)
            return
        }
        interactor.markReady(tripID: tripID)
        toast = ToastMessage(text: "Trip marked as ready", kind: .success)
    }

    func didTapStart() {
        guard let state = viewState else { return }
        if state.trip.stage == .inProgress {
            router.openTripMode(tripID)
            return
        }
        confirm = ConfirmRequest(
            title: "Start This Trip?",
            message: "Trip mode opens and you can record what you actually wear each day.",
            confirmTitle: "Start Trip",
            isDestructive: false,
            onConfirm: { [weak self] in
                guard let self else { return }
                self.interactor.startTrip(tripID: self.tripID)
                self.router.openTripMode(self.tripID)
            }
        )
    }
}

// MARK: - Router

final class TripWorkspaceRouter: TripWorkspaceRouterProtocol {
    let coordinator: NavigationCoordinator

    init(coordinator: NavigationCoordinator) {
        self.coordinator = coordinator
    }

    func openDayPlan(_ id: UUID) { coordinator.push(.tripDayPlan(id)) }
    func openPackingList(_ id: UUID) { coordinator.push(.packingList(id)) }
    func openWeightCheck(_ id: UUID) { coordinator.push(.weightCheck(id)) }
    func openReadiness(_ id: UUID) { coordinator.push(.tripReadiness(id)) }
    func openTripMode(_ id: UUID) { coordinator.present(.tripMode(id)) }
    func openRecap(_ id: UUID) { coordinator.push(.tripRecap(id)) }
    func openEdit(_ id: UUID) { coordinator.push(.tripWizard(tripID: id)) }
    func openLaundry() { coordinator.push(.laundry) }
    func openRepairs() { coordinator.push(.repairs) }
}

// MARK: - Builder

enum TripWorkspaceBuilder {
    static func build(dependencies: AppDependencies, tripID: UUID) -> TripWorkspaceView {
        let interactor = TripWorkspaceInteractor(repository: dependencies.repository)
        let router = TripWorkspaceRouter(coordinator: dependencies.coordinator)
        let presenter = TripWorkspacePresenter(interactor: interactor, router: router, tripID: tripID)
        return TripWorkspaceView(presenter: presenter)
    }
}
