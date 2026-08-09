//
//  TripModeModule.swift
//  WearLoop
//
//  The one dark screen in the app. Photographs keep their natural colour and the
//  plaques turn white.
//

import Combine
import SwiftUI

// MARK: - Contract

protocol TripModeInteractorProtocol: AnyObject {
    var repository: WardrobeRepositoryProtocol { get }
    func buildViewState(tripID: UUID, now: Date) -> TripModeViewState?
    func markWorn(tripID: UUID, dayIndex: Int, outfitID: UUID?, pieceIDs: [UUID], wasUnplanned: Bool)
    func markNotWorn(tripID: UUID, dayIndex: Int)
    func clearRecord(tripID: UUID, dayIndex: Int)
    func addUnplannedPieces(_ ids: [UUID], tripID: UUID, dayIndex: Int)
    func startRoadLaundry(pieceIDs: [UUID], tripID: UUID)
    func finishTrip(tripID: UUID, withoutRecords: Bool)
    func candidates(tripID: UUID, dayIndex: Int) -> [OutfitListItem]
    func packedPieces(tripID: UUID) -> [Piece]
}

protocol TripModeRouterProtocol: AnyObject {
    func close()
    func openRecap(_ id: UUID)
}

struct TripModeViewState {
    var tripName: String = ""
    var dayLabel: String = ""
    var dayIndex: Int = 0
    var dayNumber: Int = 1
    var dayCount: Int = 1
    var dateText: String = ""
    var occasionText: String = ""

    var plannedOutfitName: String?
    var plannedOutfitID: UUID?
    var plannedPieces: [Piece] = []

    var wornOutfitName: String?
    var wornPieces: [Piece] = []
    var isLogged: Bool = false
    var isNotWorn: Bool = false
    var wasUnplanned: Bool = false

    var daysLogged: Int = 0
    var daysTotal: Int = 0
    var canFinish: Bool = false
    var finishBlockReason: String?
    var laundryAvailable: Bool = false
    var roadLaundryCount: Int = 0
    var useDarkMode: Bool = true
    var allDays: [TripModeDay] = []
}

struct TripModeDay: Identifiable, Equatable {
    var id: UUID
    var index: Int
    var dayNumber: Int
    var isLogged: Bool
    var isNotWorn: Bool
    var isCurrent: Bool
    var hasPlan: Bool
}

// MARK: - Interactor

final class TripModeInteractor: TripModeInteractorProtocol {
    let repository: WardrobeRepositoryProtocol

    init(repository: WardrobeRepositoryProtocol) {
        self.repository = repository
    }

    func buildViewState(tripID: UUID, now: Date) -> TripModeViewState? {
        buildViewState(tripID: tripID, now: now, forcedDayIndex: nil)
    }

    func buildViewState(tripID: UUID, now: Date, forcedDayIndex: Int?) -> TripModeViewState? {
        let state = repository.state
        guard let trip = state.trip(tripID) else { return nil }

        var view = TripModeViewState()
        view.tripName = trip.name
        view.dayCount = trip.dayCount
        view.laundryAvailable = trip.laundryAvailable
        view.roadLaundryCount = trip.laundryOnRoadCount
        view.useDarkMode = state.appearance.useDarkTripMode

        let day: TripDay?
        if let forcedDayIndex, trip.days.indices.contains(forcedDayIndex) {
            day = trip.days[forcedDayIndex]
        } else {
            day = trip.currentDay(now: now)
        }
        guard let day else { return view }

        view.dayIndex = day.index
        view.dayNumber = day.dayNumber
        view.dayLabel = "Day \(day.dayNumber) of \(trip.dayCount)"
        view.dateText = DateFormatterCache.dayMonthYear.string(from: day.date)
        view.occasionText = day.occasionText

        if let outfitID = day.outfitID, let outfit = state.outfit(outfitID) {
            view.plannedOutfitID = outfitID
            view.plannedOutfitName = outfit.name
            view.plannedPieces = outfit.items.compactMap { state.piece($0.pieceID) }
        }

        if let recordID = day.wearRecordID, let record = state.wearRecord(recordID) {
            view.isLogged = true
            view.wasUnplanned = record.wasUnplanned
            view.wornOutfitName = record.outfitName
            view.wornPieces = record.pieceIDs.compactMap { state.piece($0) }
        }
        view.isNotWorn = day.notWorn

        view.daysLogged = trip.days.filter(\.isLogged).count
        view.daysTotal = trip.dayCount
        view.finishBlockReason = TripReadinessEngine.blockReason(for: .recap, trip: trip, state: state)
        view.canFinish = view.finishBlockReason == nil

        view.allDays = trip.days.map { candidate in
            TripModeDay(
                id: candidate.id,
                index: candidate.index,
                dayNumber: candidate.dayNumber,
                isLogged: candidate.wearRecordID != nil,
                isNotWorn: candidate.notWorn,
                isCurrent: candidate.index == day.index,
                hasPlan: candidate.outfitID != nil
            )
        }

        return view
    }

    func candidates(tripID: UUID, dayIndex: Int) -> [OutfitListItem] {
        let state = repository.state
        guard let trip = state.trip(tripID) else { return [] }
        // On the road, only what was actually packed is realistic.
        let packedIDs = Set(trip.activePacking.compactMap(\.pieceID))

        return state.activeOutfits
            .map { outfit -> (OutfitListItem, Int) in
                let overlap = outfit.pieceIDs.filter { packedIDs.contains($0) }.count
                let check = AvailabilityEngine.check(outfit: outfit, state: state)
                let subtitle = overlap == outfit.items.count && overlap > 0
                    ? "Fully packed for this trip"
                    : "\(overlap) of \(Plural.count(outfit.items.count, "piece")) packed"
                return (
                    OutfitListItem(
                        outfit: outfit,
                        pieces: outfit.items.compactMap { state.piece($0.pieceID) },
                        status: check.status,
                        subtitle: subtitle
                    ),
                    overlap
                )
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    func packedPieces(tripID: UUID) -> [Piece] {
        let state = repository.state
        guard let trip = state.trip(tripID) else { return [] }
        let packedIDs = trip.activePacking.compactMap(\.pieceID)
        let packed = packedIDs.compactMap { state.piece($0) }
        // Anything else still available, in case something unplanned was worn.
        let others = state.availablePieces.filter { !packedIDs.contains($0.id) }
        return packed + others
    }

    func markWorn(tripID: UUID, dayIndex: Int, outfitID: UUID?, pieceIDs: [UUID], wasUnplanned: Bool) {
        repository.mutate { state in
            guard let tripIndex = state.trips.firstIndex(where: { $0.id == tripID }),
                  state.trips[tripIndex].days.indices.contains(dayIndex) else { return }
            let day = state.trips[tripIndex].days[dayIndex]
            // Replace any previous record for this day rather than stacking them.
            if let existing = day.wearRecordID {
                WardrobeActions.deleteWearRecord(existing, in: &state)
            }
            let recordID = WardrobeActions.recordWear(
                outfitID: outfitID,
                pieceIDs: pieceIDs,
                date: day.date,
                context: .trip,
                tripID: tripID,
                wasUnplanned: wasUnplanned,
                in: &state
            )
            state.trips[tripIndex].days[dayIndex].wearRecordID = recordID
            state.trips[tripIndex].days[dayIndex].notWorn = false
            state.trips[tripIndex].updatedAt = Date()
        }
    }

    func markNotWorn(tripID: UUID, dayIndex: Int) {
        repository.mutate { state in
            guard let tripIndex = state.trips.firstIndex(where: { $0.id == tripID }),
                  state.trips[tripIndex].days.indices.contains(dayIndex) else { return }
            if let existing = state.trips[tripIndex].days[dayIndex].wearRecordID {
                WardrobeActions.deleteWearRecord(existing, in: &state)
            }
            state.trips[tripIndex].days[dayIndex].notWorn = true
        }
    }

    func clearRecord(tripID: UUID, dayIndex: Int) {
        repository.mutate { state in
            guard let tripIndex = state.trips.firstIndex(where: { $0.id == tripID }),
                  state.trips[tripIndex].days.indices.contains(dayIndex) else { return }
            if let existing = state.trips[tripIndex].days[dayIndex].wearRecordID {
                WardrobeActions.deleteWearRecord(existing, in: &state)
            }
            state.trips[tripIndex].days[dayIndex].notWorn = false
        }
    }

    /// Adds pieces worn on top of what was planned, keeping the plan intact.
    func addUnplannedPieces(_ ids: [UUID], tripID: UUID, dayIndex: Int) {
        repository.mutate { state in
            guard let tripIndex = state.trips.firstIndex(where: { $0.id == tripID }),
                  state.trips[tripIndex].days.indices.contains(dayIndex) else { return }
            let day = state.trips[tripIndex].days[dayIndex]

            var combined = ids
            var outfitID: UUID?
            if let recordID = day.wearRecordID, let record = state.wearRecord(recordID) {
                combined = (record.pieceIDs + ids).wlUnique
                outfitID = record.outfitID
                WardrobeActions.deleteWearRecord(recordID, in: &state)
            } else if let planned = day.outfitID, let outfit = state.outfit(planned) {
                combined = (outfit.pieceIDs + ids).wlUnique
                outfitID = planned
            }

            let recordID = WardrobeActions.recordWear(
                outfitID: outfitID,
                pieceIDs: combined,
                date: day.date,
                context: .trip,
                tripID: tripID,
                wasUnplanned: true,
                in: &state
            )
            state.trips[tripIndex].days[dayIndex].wearRecordID = recordID
            state.trips[tripIndex].days[dayIndex].notWorn = false
        }
    }

    func startRoadLaundry(pieceIDs: [UUID], tripID: UUID) {
        repository.mutate { state in
            WardrobeActions.sendToWash(pieceIDs: pieceIDs, in: &state)
            WardrobeActions.startLoad(
                name: "On the road",
                pieceIDs: pieceIDs,
                temperatureC: 30,
                notes: "Washed during a trip",
                in: &state
            )
            if let index = state.trips.firstIndex(where: { $0.id == tripID }) {
                state.trips[index].laundryOnRoadCount += 1
            }
        }
    }

    func finishTrip(tripID: UUID, withoutRecords: Bool) {
        repository.mutate { state in
            guard let index = state.trips.firstIndex(where: { $0.id == tripID }) else { return }
            let recap = TripRecapEngine.build(
                trip: state.trips[index],
                state: state,
                finishedWithoutRecords: withoutRecords
            )
            state.trips[index].recap = recap
            state.trips[index].stage = .recap
            state.trips[index].updatedAt = Date()
        }
    }
}

// MARK: - Presenter

final class TripModePresenter: ObservableObject {
    @Published private(set) var viewState: TripModeViewState?
    @Published private(set) var isMissing = false
    @Published var selectedDayIndex: Int? { didSet { refresh() } }
    @Published var isChangePlanPresented = false
    @Published var isUnplannedPresented = false
    @Published var isLaundryPresented = false
    @Published var toast: ToastMessage?
    @Published var confirm: ConfirmRequest?

    private let interactor: TripModeInteractor
    private let router: TripModeRouterProtocol
    private let tripID: UUID
    private var cancellables = Set<AnyCancellable>()

    init(interactor: TripModeInteractor, router: TripModeRouterProtocol, tripID: UUID) {
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
        let built = interactor.buildViewState(tripID: tripID, now: Date(), forcedDayIndex: selectedDayIndex)
        viewState = built
        isMissing = built == nil
    }

    var candidates: [OutfitListItem] {
        interactor.candidates(tripID: tripID, dayIndex: viewState?.dayIndex ?? 0)
    }

    var packedPieces: [Piece] { interactor.packedPieces(tripID: tripID) }

    // MARK: Intents

    func didSelectDay(_ index: Int) { selectedDayIndex = index }
    func didTapClose() { router.close() }

    func didTapMarkWorn() {
        guard let state = viewState else { return }
        guard let outfitID = state.plannedOutfitID else {
            isChangePlanPresented = true
            return
        }
        interactor.markWorn(
            tripID: tripID,
            dayIndex: state.dayIndex,
            outfitID: outfitID,
            pieceIDs: [],
            wasUnplanned: false
        )
        toast = ToastMessage(text: "Day \(state.dayNumber) recorded", kind: .success)
    }

    func didTapChangeOfPlan() { isChangePlanPresented = true }

    func didPickActualOutfit(_ id: UUID) {
        guard let state = viewState else { return }
        interactor.markWorn(
            tripID: tripID,
            dayIndex: state.dayIndex,
            outfitID: id,
            pieceIDs: [],
            wasUnplanned: id != state.plannedOutfitID
        )
        isChangePlanPresented = false
        toast = ToastMessage(text: "Recorded what you actually wore", kind: .success)
    }

    func didTapNotWornToday() {
        guard let state = viewState else { return }
        interactor.markNotWorn(tripID: tripID, dayIndex: state.dayIndex)
        toast = ToastMessage(text: "Day \(state.dayNumber) marked as nothing worn", kind: .info)
    }

    func didTapClearRecord() {
        guard let state = viewState else { return }
        interactor.clearRecord(tripID: tripID, dayIndex: state.dayIndex)
        toast = ToastMessage(text: "Record cleared", kind: .info)
    }

    func didTapAddUnplanned() { isUnplannedPresented = true }

    func didAddUnplanned(_ ids: [UUID]) {
        guard let state = viewState, !ids.isEmpty else {
            isUnplannedPresented = false
            return
        }
        interactor.addUnplannedPieces(ids, tripID: tripID, dayIndex: state.dayIndex)
        isUnplannedPresented = false
        toast = ToastMessage(text: "\(Plural.count(ids.count, "piece")) added to today", kind: .success)
    }

    func didTapLaundry() { isLaundryPresented = true }

    func didStartLaundry(_ ids: [UUID]) {
        guard !ids.isEmpty else {
            isLaundryPresented = false
            return
        }
        interactor.startRoadLaundry(pieceIDs: ids, tripID: tripID)
        isLaundryPresented = false
        toast = ToastMessage(text: "Wash load started", kind: .success)
    }

    func didTapFinish() {
        guard let state = viewState else { return }
        if state.canFinish {
            confirm = ConfirmRequest(
                title: "Finish This Trip?",
                message: "The recap compares what you packed with what you actually wore.",
                confirmTitle: "Finish Trip",
                isDestructive: false,
                onConfirm: { [weak self] in
                    guard let self else { return }
                    self.interactor.finishTrip(tripID: self.tripID, withoutRecords: false)
                    self.router.openRecap(self.tripID)
                }
            )
        } else {
            confirm = ConfirmRequest(
                title: "Finish Without Records?",
                message: "\(state.finishBlockReason ?? "Some days have no record.") The recap will be less accurate, and those days count as nothing worn.",
                confirmTitle: "Finish Without Records",
                cancelTitle: "Go Back",
                isDestructive: true,
                onConfirm: { [weak self] in
                    guard let self else { return }
                    self.interactor.finishTrip(tripID: self.tripID, withoutRecords: true)
                    self.router.openRecap(self.tripID)
                }
            )
        }
    }
}

// MARK: - Router

final class TripModeRouter: TripModeRouterProtocol {
    private let coordinator: NavigationCoordinator

    init(coordinator: NavigationCoordinator) {
        self.coordinator = coordinator
    }

    func close() { coordinator.dismissSheet() }

    func openRecap(_ id: UUID) {
        coordinator.dismissSheet()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [coordinator] in
            coordinator.jump(to: .trips, then: .tripRecap(id))
        }
    }
}

// MARK: - Builder

enum TripModeBuilder {
    static func build(dependencies: AppDependencies, tripID: UUID) -> TripModeView {
        let interactor = TripModeInteractor(repository: dependencies.repository)
        let router = TripModeRouter(coordinator: dependencies.coordinator)
        let presenter = TripModePresenter(interactor: interactor, router: router, tripID: tripID)
        return TripModeView(presenter: presenter)
    }
}
