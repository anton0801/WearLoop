//
//  TripReadinessModule.swift
//  WearLoop
//
//  The pre-departure checklist. Readiness is a count of real checks passed, not
//  a decorative percentage.
//

import Combine
import SwiftUI

// MARK: - Contract

protocol TripReadinessInteractorProtocol: AnyObject {
    var repository: WardrobeRepositoryProtocol { get }
    func buildViewState(tripID: UUID, now: Date) -> TripReadinessViewState?
    func markReady(tripID: UUID)
    func startTrip(tripID: UUID)
    func setConditionsReviewed(tripID: UUID)
    func packAllEssentials(tripID: UUID)
    func returnWashedPieces(tripID: UUID)
}

protocol TripReadinessRouterProtocol: ModuleRouterProtocol {
    func openDayPlan(_ id: UUID)
    func openPackingList(_ id: UUID)
    func openWeightCheck(_ id: UUID)
    func openLaundry()
    func openRepairs()
    func openTripMode(_ id: UUID)
}

struct TripReadinessViewState {
    var tripName: String = ""
    var readiness: TripReadiness
    var isReady: Bool = false
    var isAlreadyReady: Bool = false
    var isInProgress: Bool = false
    var startsInText: String = ""
    var showHalftone: Bool = true
}

// MARK: - Interactor

final class TripReadinessInteractor: TripReadinessInteractorProtocol {
    let repository: WardrobeRepositoryProtocol

    init(repository: WardrobeRepositoryProtocol) {
        self.repository = repository
    }

    func buildViewState(tripID: UUID, now: Date) -> TripReadinessViewState? {
        let state = repository.state
        guard let trip = state.trip(tripID) else { return nil }

        let readiness = TripReadinessEngine.readiness(trip: trip, state: state, now: now)
        var view = TripReadinessViewState(readiness: readiness)
        view.tripName = trip.name
        view.isReady = readiness.isReady
        view.isAlreadyReady = trip.stage == .ready
        view.isInProgress = trip.stage == .inProgress
        view.showHalftone = state.appearance.showHalftoneMotif

        let days = Calendar.wl.dayCount(from: now, to: trip.startDate)
        if trip.stage == .inProgress {
            view.startsInText = "This trip is in progress."
        } else if days > 0 {
            view.startsInText = "Starts in \(Plural.count(days, "day"))."
        } else if days == 0 {
            view.startsInText = "Starts today."
        } else {
            view.startsInText = "Started \(Plural.count(-days, "day")) ago."
        }

        return view
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

    func packAllEssentials(tripID: UUID) {
        repository.mutate { state in
            WardrobeActions.syncEssentials(tripID: tripID, in: &state)
            guard let index = state.trips.firstIndex(where: { $0.id == tripID }) else { return }
            for entryIndex in state.trips[index].packing.indices
            where state.trips[index].packing[entryIndex].source == .essential
                && !state.trips[index].packing[entryIndex].isNotPacking {
                state.trips[index].packing[entryIndex].isPacked = true
            }
        }
    }

    /// Brings back anything this trip needs that is sitting in the wash.
    func returnWashedPieces(tripID: UUID) {
        repository.mutate { state in
            guard let trip = state.trip(tripID) else { return }
            let needed = TripReadinessEngine.neededPieces(trip: trip, state: state)
                .filter { $0.status == .inWash }
                .map(\.id)
            guard !needed.isEmpty else { return }
            WardrobeActions.returnFromWash(pieceIDs: needed, in: &state)
        }
    }
}

// MARK: - Presenter

final class TripReadinessPresenter: ObservableObject {
    @Published private(set) var viewState: TripReadinessViewState?
    @Published private(set) var isMissing = false
    @Published var toast: ToastMessage?
    @Published var confirm: ConfirmRequest?

    private let interactor: TripReadinessInteractorProtocol
    private let router: TripReadinessRouterProtocol
    private let tripID: UUID
    private var cancellables = Set<AnyCancellable>()

    init(interactor: TripReadinessInteractorProtocol, router: TripReadinessRouterProtocol, tripID: UUID) {
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
        let built = interactor.buildViewState(tripID: tripID, now: Date())
        viewState = built
        isMissing = built == nil
    }

    func didTapItem(_ item: ReadinessItem) {
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

    /// A direct fix offered on the checklist row itself, where one exists.
    func didTapQuickFix(_ item: ReadinessItem) {
        switch item.id {
        case "essentials":
            interactor.packAllEssentials(tripID: tripID)
            toast = ToastMessage(text: "Essentials added and ticked off", kind: .success)
        case "laundry":
            confirm = ConfirmRequest(
                title: "Return These Pieces?",
                message: "Everything this trip needs comes straight back out of the wash and into rotation.",
                confirmTitle: "Return Pieces",
                isDestructive: false,
                onConfirm: { [weak self] in
                    guard let self else { return }
                    self.interactor.returnWashedPieces(tripID: self.tripID)
                    self.toast = ToastMessage(text: "Pieces returned to rotation", kind: .success)
                }
            )
        case "conditions":
            interactor.setConditionsReviewed(tripID: tripID)
            toast = ToastMessage(text: "Conditions marked as reviewed", kind: .success)
        default:
            didTapItem(item)
        }
    }

    func quickFixTitle(_ item: ReadinessItem) -> String? {
        switch item.id {
        case "essentials": return "Add and Tick Off"
        case "laundry": return "Return Them Now"
        case "conditions": return "Mark as Reviewed"
        default: return nil
        }
    }

    func didTapMarkReady() {
        guard let state = viewState, state.isReady else { return }
        interactor.markReady(tripID: tripID)
        toast = ToastMessage(text: "Trip marked as ready", kind: .success)
    }

    func didTapStart() {
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

    func didTapOpenTripMode() { router.openTripMode(tripID) }

    func didTapFixRemaining() {
        guard let first = viewState?.readiness.outstanding.first else { return }
        didTapItem(first)
    }
}

// MARK: - Router

final class TripReadinessRouter: TripReadinessRouterProtocol {
    let coordinator: NavigationCoordinator

    init(coordinator: NavigationCoordinator) {
        self.coordinator = coordinator
    }

    func openDayPlan(_ id: UUID) { coordinator.push(.tripDayPlan(id)) }
    func openPackingList(_ id: UUID) { coordinator.push(.packingList(id)) }
    func openWeightCheck(_ id: UUID) { coordinator.push(.weightCheck(id)) }
    func openLaundry() { coordinator.push(.laundry) }
    func openRepairs() { coordinator.push(.repairs) }
    func openTripMode(_ id: UUID) { coordinator.present(.tripMode(id)) }
}

// MARK: - Builder

enum TripReadinessBuilder {
    static func build(dependencies: AppDependencies, tripID: UUID) -> TripReadinessView {
        let interactor = TripReadinessInteractor(repository: dependencies.repository)
        let router = TripReadinessRouter(coordinator: dependencies.coordinator)
        let presenter = TripReadinessPresenter(interactor: interactor, router: router, tripID: tripID)
        return TripReadinessView(presenter: presenter)
    }
}
