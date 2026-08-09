//
//  TripDayPlanModule.swift
//  WearLoop
//
//  An outfit for each day. Reuse is shown clearly, because reuse is what makes
//  the bag smaller.
//

import Combine
import SwiftUI

// MARK: - Contract

protocol TripDayPlanInteractorProtocol: AnyObject {
    var repository: WardrobeRepositoryProtocol { get }
    func buildViewState(tripID: UUID, now: Date) -> TripDayPlanViewState?
    func assign(outfitID: UUID?, dayIndex: Int, tripID: UUID)
    func setUndecided(_ undecided: Bool, dayIndex: Int, tripID: UUID)
    func candidates(tripID: UUID, dayIndex: Int) -> [OutfitListItem]
    func advanceStage(tripID: UUID)
}

protocol TripDayPlanRouterProtocol: ModuleRouterProtocol {
    func openBuildOutfit()
    func openOutfit(_ id: UUID)
    func openPackingList(_ id: UUID)
}

struct TripDayPlanRow: Identifiable, Equatable {
    var id: UUID
    var index: Int
    var dayNumber: Int
    var dateText: String
    var occasionText: String
    var outfitName: String?
    var outfitID: UUID?
    var pieces: [Piece]
    var status: OutfitStatus?
    var isUndecided: Bool
    /// "Also used on days 2 and 5."
    var reuseText: String?
    var warningText: String?
}

struct TripDayPlanViewState {
    var tripName: String = ""
    var rows: [TripDayPlanRow] = []
    var coverage: TripCoverage
    var notes: [String] = []
    var hasOutfits: Bool = true
    var canContinue: Bool = false
    var blockReason: String?
    var units: MeasurementUnits = .metric
    var showHalftone: Bool = true
}

// MARK: - Interactor

final class TripDayPlanInteractor: TripDayPlanInteractorProtocol {
    let repository: WardrobeRepositoryProtocol

    init(repository: WardrobeRepositoryProtocol) {
        self.repository = repository
    }

    func buildViewState(tripID: UUID, now: Date) -> TripDayPlanViewState? {
        let state = repository.state
        guard let trip = state.trip(tripID) else { return nil }

        let coverage = TripPlanEngine.coverage(trip: trip, state: state)
        var view = TripDayPlanViewState(coverage: coverage)
        view.tripName = trip.name
        view.units = state.profile.units
        view.showHalftone = state.appearance.showHalftoneMotif
        view.hasOutfits = !state.activeOutfits.isEmpty
        view.notes = coverage.notes

        // Which days share each outfit.
        var outfitDays: [UUID: [Int]] = [:]
        for day in trip.days {
            if let outfitID = day.outfitID {
                outfitDays[outfitID, default: []].append(day.dayNumber)
            }
        }

        view.rows = trip.days.map { day in
            var row = TripDayPlanRow(
                id: day.id,
                index: day.index,
                dayNumber: day.dayNumber,
                dateText: DateFormatterCache.dayMonth.string(from: day.date),
                occasionText: day.occasionText,
                outfitName: nil,
                outfitID: day.outfitID,
                pieces: [],
                status: nil,
                isUndecided: day.isUndecided,
                reuseText: nil,
                warningText: nil
            )

            guard let outfitID = day.outfitID, let outfit = state.outfit(outfitID) else {
                return row
            }

            row.outfitName = outfit.name
            row.pieces = outfit.items.compactMap { state.piece($0.pieceID) }
            let check = AvailabilityEngine.check(outfit: outfit, state: state, referenceDate: day.date)
            row.status = check.status

            if let days = outfitDays[outfitID], days.count > 1 {
                let others = days.filter { $0 != day.dayNumber }
                row.reuseText = "Also used on \(Plural.days(others))."
            }

            var warnings: [String] = []
            if !check.isAvailable {
                if let back = check.earliestReturn {
                    warnings.append("\(Plural.count(check.unavailablePieceIDs.count, "piece")) unavailable until \(DateFormatterCache.relativeDayText(back, now: now)).")
                } else {
                    warnings.append("\(Plural.count(check.unavailablePieceIDs.count, "piece")) unavailable.")
                }
            }
            // Against the trip's own conditions rather than a single day's weather.
            if outfit.temperatureMax < trip.temperatureMin - 1 || outfit.temperatureMin > trip.temperatureMax + 1 {
                warnings.append("Outside trip conditions: set for \(UnitFormatter.temperatureRange(outfit.temperatureMin, outfit.temperatureMax, units: state.profile.units)), the trip expects \(UnitFormatter.temperatureRange(trip.temperatureMin, trip.temperatureMax, units: state.profile.units)).")
            }
            if let required = day.requiredFormality, outfit.formality.rank < required.rank {
                warnings.append("This outfit is \(outfit.formality.title). \(day.occasionText) expects \(required.title).")
            }
            if trip.rainExpected && !outfit.items.contains(where: { $0.layer == .outer }) {
                warnings.append("Rain is expected on this trip and this outfit has no outer layer.")
            }
            row.warningText = warnings.isEmpty ? nil : warnings.joined(separator: " ")
            return row
        }

        view.blockReason = TripReadinessEngine.blockReason(for: .packingList, trip: trip, state: state)
        view.canContinue = view.blockReason == nil

        return view
    }

    func candidates(tripID: UUID, dayIndex: Int) -> [OutfitListItem] {
        let state = repository.state
        guard let trip = state.trip(tripID), trip.days.indices.contains(dayIndex) else { return [] }
        let day = trip.days[dayIndex]

        let midpoint = (trip.temperatureMin + trip.temperatureMax) / 2
        let ranked = SuggestionEngine.rank(
            outfits: state.activeOutfits,
            state: state,
            temperature: midpoint,
            occasion: day.occasions.first?.wardrobeOccasion,
            requiredFormality: day.requiredFormality
        )

        // Outfits already used on another day come first: reuse shrinks the bag.
        let usedElsewhere = Set(trip.days.filter { $0.index != dayIndex }.compactMap(\.outfitID))

        return ranked
            .sorted { a, b in
                let aUsed = usedElsewhere.contains(a.id)
                let bUsed = usedElsewhere.contains(b.id)
                if aUsed != bUsed { return aUsed }
                return false
            }
            .map { outfit in
                let check = AvailabilityEngine.check(outfit: outfit, state: state, referenceDate: day.date)
                var subtitle = "\(outfit.occasion.title) · \(outfit.temperatureText)"
                if usedElsewhere.contains(outfit.id) {
                    let days = trip.days.filter { $0.outfitID == outfit.id }.map(\.dayNumber)
                    subtitle = "Already packed for \(Plural.days(days))"
                } else if check.status != .ready, let back = check.earliestReturn {
                    subtitle = "Back \(DateFormatterCache.relativeDayText(back))"
                }
                return OutfitListItem(
                    outfit: outfit,
                    pieces: outfit.items.compactMap { state.piece($0.pieceID) },
                    status: check.status,
                    subtitle: subtitle
                )
            }
    }

    func assign(outfitID: UUID?, dayIndex: Int, tripID: UUID) {
        repository.mutate { state in
            guard let tripIndex = state.trips.firstIndex(where: { $0.id == tripID }),
                  state.trips[tripIndex].days.indices.contains(dayIndex) else { return }
            state.trips[tripIndex].days[dayIndex].outfitID = outfitID
            if outfitID != nil {
                state.trips[tripIndex].days[dayIndex].isUndecided = false
            }
            state.trips[tripIndex].updatedAt = Date()
            WardrobeActions.refreshPacking(tripID: tripID, in: &state)
        }
    }

    func setUndecided(_ undecided: Bool, dayIndex: Int, tripID: UUID) {
        repository.mutate { state in
            guard let tripIndex = state.trips.firstIndex(where: { $0.id == tripID }),
                  state.trips[tripIndex].days.indices.contains(dayIndex) else { return }
            state.trips[tripIndex].days[dayIndex].isUndecided = undecided
            if undecided {
                state.trips[tripIndex].days[dayIndex].outfitID = nil
            }
            WardrobeActions.refreshPacking(tripID: tripID, in: &state)
        }
    }

    func advanceStage(tripID: UUID) {
        repository.mutate { state in
            guard let index = state.trips.firstIndex(where: { $0.id == tripID }) else { return }
            if state.trips[index].stage.order < TripStage.packingList.order {
                state.trips[index].stage = .packingList
            }
            WardrobeActions.refreshPacking(tripID: tripID, in: &state)
            WardrobeActions.syncEssentials(tripID: tripID, in: &state)
        }
    }
}

// MARK: - Presenter

final class TripDayPlanPresenter: ObservableObject {
    @Published private(set) var viewState: TripDayPlanViewState?
    @Published private(set) var isMissing = false
    @Published var pickerDayIndex: Int?
    @Published var toast: ToastMessage?

    private let interactor: TripDayPlanInteractorProtocol
    private let router: TripDayPlanRouterProtocol
    private let tripID: UUID
    private var cancellables = Set<AnyCancellable>()

    init(interactor: TripDayPlanInteractorProtocol, router: TripDayPlanRouterProtocol, tripID: UUID) {
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

    func candidates(for dayIndex: Int) -> [OutfitListItem] {
        interactor.candidates(tripID: tripID, dayIndex: dayIndex)
    }

    // MARK: Intents

    func didTapAssign(dayIndex: Int) { pickerDayIndex = dayIndex }
    func didTapOutfit(_ id: UUID) { router.openOutfit(id) }
    func didTapBuildOutfit() { router.openBuildOutfit() }

    func didPickOutfit(_ id: UUID, dayIndex: Int) {
        interactor.assign(outfitID: id, dayIndex: dayIndex, tripID: tripID)
        pickerDayIndex = nil
        toast = ToastMessage(text: "Outfit assigned to day \(dayIndex + 1)", kind: .success)
    }

    func didTapClear(dayIndex: Int) {
        interactor.assign(outfitID: nil, dayIndex: dayIndex, tripID: tripID)
        toast = ToastMessage(text: "Day \(dayIndex + 1) cleared", kind: .info)
    }

    func didToggleUndecided(dayIndex: Int, current: Bool) {
        interactor.setUndecided(!current, dayIndex: dayIndex, tripID: tripID)
        toast = ToastMessage(
            text: current ? "Day \(dayIndex + 1) no longer undecided" : "Day \(dayIndex + 1) marked as undecided",
            kind: .info
        )
    }

    func didTapContinue() {
        guard let state = viewState else { return }
        guard state.canContinue else {
            toast = ToastMessage(text: state.blockReason ?? "Some days still need an outfit.", kind: .failure)
            return
        }
        interactor.advanceStage(tripID: tripID)
        router.openPackingList(tripID)
    }
}

// MARK: - Router

final class TripDayPlanRouter: TripDayPlanRouterProtocol {
    let coordinator: NavigationCoordinator

    init(coordinator: NavigationCoordinator) {
        self.coordinator = coordinator
    }

    func openBuildOutfit() { coordinator.jump(to: .outfits, then: .outfitBuilder(outfitID: nil, prefillPieceID: nil)) }
    func openOutfit(_ id: UUID) { coordinator.push(.outfitDetails(id)) }
    func openPackingList(_ id: UUID) { coordinator.push(.packingList(id)) }
}

// MARK: - Builder

enum TripDayPlanBuilder {
    static func build(dependencies: AppDependencies, tripID: UUID) -> TripDayPlanView {
        let interactor = TripDayPlanInteractor(repository: dependencies.repository)
        let router = TripDayPlanRouter(coordinator: dependencies.coordinator)
        let presenter = TripDayPlanPresenter(interactor: interactor, router: router, tripID: tripID)
        return TripDayPlanView(presenter: presenter)
    }
}
