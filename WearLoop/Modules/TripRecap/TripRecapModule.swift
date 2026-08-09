//
//  TripRecapModule.swift
//  WearLoop
//
//  Plan against reality, and a template the user can carry to the next trip.
//

import Combine
import SwiftUI

// MARK: - Contract

protocol TripRecapInteractorProtocol: AnyObject {
    var repository: WardrobeRepositoryProtocol { get }
    func buildViewState(tripID: UUID) -> TripRecapViewState?
    func saveNote(_ note: String, tripID: UUID)
    func createTemplate(name: String, tripID: UUID) -> SaveOutcome
    func closeTrip(tripID: UUID)
    func rebuildRecap(tripID: UUID)
}

protocol TripRecapRouterProtocol: ModuleRouterProtocol {
    func openPiece(_ id: UUID)
    func openTemplates()
    func closeToTrips()
}

struct TripRecapViewState {
    var tripName: String = ""
    var dateText: String = ""
    var recap: TripRecapData?
    var packedCount: Int = 0
    var wornCount: Int = 0
    var accuracyText: String = "—"
    var accuracyFraction: Double = 0
    var neverWorn: [Piece] = []
    var wornNotPacked: [Piece] = []
    var outfitsChanged: Int = 0
    var laundryDone: Int = 0
    var finalWeightText: String = ""
    var conclusions: [String] = []
    var note: String = ""
    var isFinished: Bool = false
    var hasTemplate: Bool = false
    var units: MeasurementUnits = .metric
    var showHalftone: Bool = true
}

// MARK: - Interactor

final class TripRecapInteractor: TripRecapInteractorProtocol {
    let repository: WardrobeRepositoryProtocol

    init(repository: WardrobeRepositoryProtocol) {
        self.repository = repository
    }

    func buildViewState(tripID: UUID) -> TripRecapViewState? {
        let state = repository.state
        guard let trip = state.trip(tripID) else { return nil }

        var view = TripRecapViewState()
        view.tripName = trip.name
        view.dateText = trip.dateRangeText
        view.units = state.profile.units
        view.showHalftone = state.appearance.showHalftoneMotif
        view.isFinished = trip.recap != nil
        view.hasTemplate = state.templates.contains { $0.sourceTripName == trip.name }

        guard let recap = trip.recap else {
            // Not finished yet: show a preview built from what is known so far.
            let preview = TripRecapEngine.build(trip: trip, state: state)
            fill(&view, with: preview, trip: trip, state: state)
            return view
        }

        view.recap = recap
        view.note = recap.note
        fill(&view, with: recap, trip: trip, state: state)
        return view
    }

    private func fill(_ view: inout TripRecapViewState, with recap: TripRecapData, trip: Trip, state: AppState) {
        view.packedCount = recap.packedCount
        view.wornCount = recap.wornCount
        view.outfitsChanged = recap.outfitsChangedCount
        view.laundryDone = recap.laundryLoadsDone
        view.finalWeightText = UnitFormatter.bagWeight(
            grams: recap.finalWeightKg * 1000,
            units: state.profile.units
        )
        view.accuracyFraction = recap.packedCount > 0
            ? Double(recap.wornCount) / Double(recap.packedCount)
            : 0
        view.accuracyText = recap.packedCount > 0 ? UnitFormatter.percent(view.accuracyFraction) : "—"
        view.neverWorn = recap.neverWornPieceIDs.compactMap { state.piece($0) }
        view.wornNotPacked = recap.wornNotPackedPieceIDs.compactMap { state.piece($0) }
        view.conclusions = TripRecapEngine.conclusions(trip: trip, recap: recap, state: state)
    }

    func saveNote(_ note: String, tripID: UUID) {
        repository.mutate { state in
            guard let index = state.trips.firstIndex(where: { $0.id == tripID }) else { return }
            state.trips[index].recap?.note = note
        }
    }

    func createTemplate(name: String, tripID: UUID) -> SaveOutcome {
        let state = repository.state
        guard let trip = state.trip(tripID) else {
            return .failed("This trip no longer exists.")
        }

        // Only what actually went into the bag is worth keeping.
        let packedEntries = trip.activePacking.filter(\.isPacked)
        let pieceIDs = packedEntries.compactMap(\.pieceID)
        let snapshots = pieceIDs.compactMap { state.piece($0).map(PieceSnapshot.init(piece:)) }
        let manual = packedEntries
            .filter { $0.pieceID == nil }
            .compactMap(\.manualName)

        guard !pieceIDs.isEmpty || !manual.isEmpty else {
            return .failed("Nothing on this trip was ticked off as packed, so there is nothing to save.")
        }

        let template = PackingTemplate(
            name: name.wlIsBlank ? "\(trip.name) template" : name.wlTrimmed,
            tripType: trip.type,
            dayCount: trip.dayCount,
            pieceIDs: pieceIDs,
            snapshots: snapshots,
            manualItems: manual,
            sourceTripName: trip.name
        )

        let error = repository.mutateThrowing { state in
            state.templates.append(template)
        }
        if let error { return .failed(error) }
        return .saved(template.id)
    }

    func closeTrip(tripID: UUID) {
        repository.mutate { state in
            guard let index = state.trips.firstIndex(where: { $0.id == tripID }) else { return }
            state.trips[index].stage = .recap
            if state.trips[index].recap == nil {
                state.trips[index].recap = TripRecapEngine.build(trip: state.trips[index], state: state)
            }
        }
    }

    /// Recomputes the recap after the user changed a record.
    func rebuildRecap(tripID: UUID) {
        repository.mutate { state in
            guard let index = state.trips.firstIndex(where: { $0.id == tripID }),
                  let existing = state.trips[index].recap else { return }
            var rebuilt = TripRecapEngine.build(
                trip: state.trips[index],
                state: state,
                finishedWithoutRecords: existing.finishedWithoutRecords
            )
            rebuilt.note = existing.note
            state.trips[index].recap = rebuilt
        }
    }
}

// MARK: - Presenter

final class TripRecapPresenter: ObservableObject {
    @Published private(set) var viewState: TripRecapViewState?
    @Published private(set) var isMissing = false
    @Published var isTemplateSheetPresented = false
    @Published var toast: ToastMessage?
    @Published var confirm: ConfirmRequest?

    private let interactor: TripRecapInteractorProtocol
    private let router: TripRecapRouterProtocol
    private let tripID: UUID
    private var cancellables = Set<AnyCancellable>()

    init(interactor: TripRecapInteractorProtocol, router: TripRecapRouterProtocol, tripID: UUID) {
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

    func didTapPiece(_ id: UUID) { router.openPiece(id) }
    func didTapTemplates() { router.openTemplates() }
    func didTapCreateTemplate() { isTemplateSheetPresented = true }

    func didSaveNote(_ note: String) {
        interactor.saveNote(note, tripID: tripID)
    }

    func didCreateTemplate(name: String) {
        switch interactor.createTemplate(name: name, tripID: tripID) {
        case .saved:
            isTemplateSheetPresented = false
            toast = ToastMessage(text: "Template saved", kind: .success)
        case .failed(let message):
            isTemplateSheetPresented = false
            toast = ToastMessage(text: message, kind: .failure)
        }
    }

    func didTapSaveRecap() {
        interactor.closeTrip(tripID: tripID)
        toast = ToastMessage(text: "Recap saved", kind: .success)
    }

    func didTapCloseTrip() {
        confirm = ConfirmRequest(
            title: "Close This Trip?",
            message: "The trip moves to Completed. Its recap and wear records are kept.",
            confirmTitle: "Close Trip",
            isDestructive: false,
            onConfirm: { [weak self] in
                guard let self else { return }
                self.interactor.closeTrip(tripID: self.tripID)
                self.router.closeToTrips()
            }
        )
    }
}

// MARK: - Router

final class TripRecapRouter: TripRecapRouterProtocol {
    let coordinator: NavigationCoordinator

    init(coordinator: NavigationCoordinator) {
        self.coordinator = coordinator
    }

    func openPiece(_ id: UUID) { coordinator.jump(to: .wardrobe, then: .pieceDetails(id)) }
    func openTemplates() { coordinator.push(.templates) }
    func closeToTrips() { coordinator.popToRoot() }
}

// MARK: - Builder

enum TripRecapBuilder {
    static func build(dependencies: AppDependencies, tripID: UUID) -> TripRecapView {
        let interactor = TripRecapInteractor(repository: dependencies.repository)
        let router = TripRecapRouter(coordinator: dependencies.coordinator)
        let presenter = TripRecapPresenter(interactor: interactor, router: router, tripID: tripID)
        return TripRecapView(presenter: presenter)
    }
}
