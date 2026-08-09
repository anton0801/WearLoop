//
//  TripWizardModule.swift
//  WearLoop
//
//  Five steps to create a trip, saving a draft at every point so nothing is lost
//  by leaving halfway.
//

import SwiftUI

// MARK: - Contract

protocol TripWizardInteractorProtocol: AnyObject {
    func loadTrip(_ id: UUID) -> Trip?
    func saveDraft(_ trip: Trip) -> SaveOutcome
    func createTrip(_ trip: Trip) -> SaveOutcome
    func units() -> MeasurementUnits
    func hasOutfits() -> Bool
}

protocol TripWizardRouterProtocol: ModuleRouterProtocol {
    func finish(tripID: UUID)
    func cancel()
}

struct TripWizardViewState {
    var step: Int = 1
    var isEditingExisting: Bool = false

    // Step 1
    var name: String = ""
    var destination: String = ""
    var startDate: Date = Date().wlStartOfDay
    var endDate: Date = Calendar.wl.addingDays(3, to: Date().wlStartOfDay)
    var type: TripType = .leisure

    // Step 2
    var days: [TripDay] = []

    // Step 3
    var temperatureMin: Double = 10
    var temperatureMax: Double = 22
    var rainExpected: Bool = false
    var laundryAvailable: Bool = false
    var dressCodeNotes: String = ""

    // Step 4
    var luggageType: LuggageType = .cabinBag
    var weightLimitKg: Double? = 8
    var volumeNotes: String = ""

    // Validation
    var nameError: String?
    var dateError: String?
    var limitError: String?
    var saveError: String?

    var isSaving: Bool = false
    var didFinish: Bool = false
    var units: MeasurementUnits = .metric
    var hasOutfits: Bool = true

    var totalSteps: Int { 5 }
    var dayCount: Int { days.count }

    var stepTitle: String {
        switch step {
        case 1: return "trip basics"
        case 2: return "days and occasions"
        case 3: return "conditions"
        case 4: return "luggage"
        default: return "review"
        }
    }

    var stepSubtitle: String {
        switch step {
        case 1: return "Name it and set the dates."
        case 2: return "What each day is for shapes the outfits and the bag."
        case 3: return "The weather you expect, checked against your outfits."
        case 4: return "The bag you are taking and what it can hold."
        default: return "Anything still missing is listed here."
        }
    }

    /// Days with no occasion, reported in the review step.
    var daysWithoutOccasion: [TripDay] { days.filter { $0.occasions.isEmpty } }
}

// MARK: - Interactor

final class TripWizardInteractor: TripWizardInteractorProtocol {
    private let repository: WardrobeRepositoryProtocol

    init(repository: WardrobeRepositoryProtocol) {
        self.repository = repository
    }

    func loadTrip(_ id: UUID) -> Trip? { repository.state.trip(id) }
    func units() -> MeasurementUnits { repository.state.profile.units }
    func hasOutfits() -> Bool { !repository.state.activeOutfits.isEmpty }

    func saveDraft(_ trip: Trip) -> SaveOutcome {
        write(trip, asDraft: true)
    }

    func createTrip(_ trip: Trip) -> SaveOutcome {
        write(trip, asDraft: false)
    }

    private func write(_ trip: Trip, asDraft: Bool) -> SaveOutcome {
        var updated = trip
        updated.isDraft = asDraft
        updated.updatedAt = Date()
        if !asDraft && updated.stage == .setup {
            updated.stage = .dayPlan
        }

        let error = repository.mutateThrowing { state in
            if let index = state.trips.firstIndex(where: { $0.id == updated.id }) {
                updated.createdAt = state.trips[index].createdAt
                // Keep the work already done in the workspace.
                updated.packing = state.trips[index].packing
                updated.recap = state.trips[index].recap
                updated.laundryOnRoadCount = state.trips[index].laundryOnRoadCount
                if state.trips[index].stage.order > updated.stage.order {
                    updated.stage = state.trips[index].stage
                }
                state.trips[index] = updated
            } else {
                state.trips.append(updated)
            }
            if !asDraft {
                // Rebuild the packing list against the (possibly changed) days.
                WardrobeActions.refreshPacking(tripID: updated.id, in: &state)
                WardrobeActions.syncEssentials(tripID: updated.id, in: &state)
            }
        }
        if let error { return .failed(error) }
        return .saved(updated.id)
    }
}

// MARK: - Presenter

final class TripWizardPresenter: ObservableObject {
    @Published var viewState = TripWizardViewState()
    @Published var toast: ToastMessage?

    private let interactor: TripWizardInteractorProtocol
    private let router: TripWizardRouterProtocol
    private let tripID: UUID
    private let isResuming: Bool
    private var didLoad = false

    init(interactor: TripWizardInteractorProtocol, router: TripWizardRouterProtocol, tripID: UUID?) {
        self.interactor = interactor
        self.router = router
        self.tripID = tripID ?? UUID()
        self.isResuming = tripID != nil
    }

    func onAppear() {
        viewState.units = interactor.units()
        viewState.hasOutfits = interactor.hasOutfits()
        guard !didLoad else { return }
        didLoad = true

        guard isResuming, let trip = interactor.loadTrip(tripID) else {
            rebuildDays()
            return
        }
        viewState.isEditingExisting = !trip.isDraft
        viewState.name = trip.name
        viewState.destination = trip.destination
        viewState.startDate = trip.startDate
        viewState.endDate = trip.endDate
        viewState.type = trip.type
        viewState.days = trip.days
        viewState.temperatureMin = trip.temperatureMin
        viewState.temperatureMax = trip.temperatureMax
        viewState.rainExpected = trip.rainExpected
        viewState.laundryAvailable = trip.laundryAvailable
        viewState.dressCodeNotes = trip.dressCodeNotes
        viewState.luggageType = trip.luggageType
        viewState.weightLimitKg = trip.weightLimitKg
        viewState.volumeNotes = trip.volumeNotes
        viewState.step = min(max(trip.draftStep, 1), 5)
    }

    // MARK: Step 1

    func setName(_ value: String) {
        viewState.name = value
        if !value.wlIsBlank { viewState.nameError = nil }
    }

    func setStartDate(_ date: Date) {
        viewState.startDate = date.wlStartOfDay
        if viewState.endDate < viewState.startDate {
            viewState.endDate = viewState.startDate
        }
        rebuildDays()
    }

    func setEndDate(_ date: Date) {
        viewState.endDate = date.wlStartOfDay
        if viewState.endDate < viewState.startDate {
            viewState.startDate = viewState.endDate
        }
        rebuildDays()
    }

    func setType(_ type: TripType) { viewState.type = type }

    /// Keeps the plans of days that survive a date change.
    private func rebuildDays() {
        var trip = buildTrip()
        WardrobeActions.rebuildDays(for: &trip)
        viewState.days = trip.days
        viewState.dateError = trip.days.count > 60
            ? "A trip longer than 60 days cannot be planned day by day."
            : nil
    }

    // MARK: Step 2

    func toggleOccasion(_ occasion: TripDayOccasion, dayIndex: Int) {
        guard viewState.days.indices.contains(dayIndex) else { return }
        viewState.days[dayIndex].occasions.wlToggle(occasion)
    }

    func copyPreviousDay(to dayIndex: Int) {
        guard dayIndex > 0, viewState.days.indices.contains(dayIndex) else { return }
        viewState.days[dayIndex].occasions = viewState.days[dayIndex - 1].occasions
    }

    func clearDay(_ dayIndex: Int) {
        guard viewState.days.indices.contains(dayIndex) else { return }
        viewState.days[dayIndex].occasions = []
    }

    func applyToAllDays(_ occasions: [TripDayOccasion]) {
        for index in viewState.days.indices {
            viewState.days[index].occasions = occasions
        }
    }

    // MARK: Step 3 & 4

    func setTemperature(min: Double, max: Double) {
        viewState.temperatureMin = min
        viewState.temperatureMax = max
    }

    func setLuggageType(_ type: LuggageType) {
        viewState.luggageType = type
        if type.allowsLimit {
            // Offer the usual allowance for this bag as a starting point.
            if viewState.weightLimitKg == nil {
                viewState.weightLimitKg = type.suggestedLimitKg
            }
        } else {
            viewState.weightLimitKg = nil
        }
        viewState.limitError = nil
    }

    // MARK: Navigation

    func canContinue() -> Bool {
        switch viewState.step {
        case 1: return !viewState.name.wlIsBlank && viewState.dateError == nil
        case 4: return !viewState.luggageType.allowsLimit || (viewState.weightLimitKg ?? 0) > 0
        default: return true
        }
    }

    func didTapContinue() {
        switch viewState.step {
        case 1:
            viewState.nameError = viewState.name.wlIsBlank ? "Enter a name for this trip." : nil
            guard viewState.nameError == nil, viewState.dateError == nil else { return }
        case 4:
            if viewState.luggageType.allowsLimit && (viewState.weightLimitKg ?? 0) <= 0 {
                viewState.limitError = "Enter a weight limit, or choose No Limit."
                return
            }
            viewState.limitError = nil
        default:
            break
        }
        guard viewState.step < viewState.totalSteps else { return }
        viewState.step += 1
        persistDraft(silent: true)
    }

    func didTapBack() {
        guard viewState.step > 1 else {
            router.cancel()
            return
        }
        viewState.step -= 1
    }

    func didSelectStep(_ step: Int) {
        // Only steps already reached can be jumped to.
        guard step >= 1, step <= viewState.step else { return }
        viewState.step = step
    }

    func didTapSaveDraft() {
        persistDraft(silent: false)
    }

    private func persistDraft(silent: Bool) {
        guard !viewState.didFinish else { return }
        var trip = buildTrip()
        trip.draftStep = viewState.step
        switch interactor.saveDraft(trip) {
        case .saved:
            if !silent {
                toast = ToastMessage(text: "Draft saved", kind: .success)
            }
        case .failed(let message):
            viewState.saveError = message
        }
    }

    func didTapCreate() {
        guard !viewState.isSaving, !viewState.didFinish else { return }
        viewState.nameError = viewState.name.wlIsBlank ? "Enter a name for this trip." : nil
        guard viewState.nameError == nil else {
            viewState.step = 1
            return
        }

        viewState.isSaving = true
        viewState.saveError = nil

        var trip = buildTrip()
        trip.draftStep = 5

        switch interactor.createTrip(trip) {
        case .saved(let id):
            viewState.isSaving = false
            viewState.didFinish = true
            router.finish(tripID: id)
        case .failed(let message):
            viewState.isSaving = false
            viewState.saveError = message
        }
    }

    private func buildTrip() -> Trip {
        Trip(
            id: tripID,
            name: viewState.name.wlTrimmed,
            destination: viewState.destination.wlTrimmed,
            startDate: viewState.startDate,
            endDate: viewState.endDate,
            type: viewState.type,
            days: viewState.days,
            temperatureMin: viewState.temperatureMin,
            temperatureMax: viewState.temperatureMax,
            rainExpected: viewState.rainExpected,
            laundryAvailable: viewState.laundryAvailable,
            dressCodeNotes: viewState.dressCodeNotes.wlTrimmed,
            conditionsReviewed: viewState.step >= 3,
            luggageType: viewState.luggageType,
            weightLimitKg: viewState.weightLimitKg,
            volumeNotes: viewState.volumeNotes.wlTrimmed,
            draftStep: viewState.step
        )
    }
}

// MARK: - Router

final class TripWizardRouter: TripWizardRouterProtocol {
    let coordinator: NavigationCoordinator

    init(coordinator: NavigationCoordinator) {
        self.coordinator = coordinator
    }

    func finish(tripID: UUID) {
        // Replace the wizard on the stack with the workspace.
        coordinator.pop()
        DispatchQueue.main.async { [coordinator] in
            coordinator.push(.tripWorkspace(tripID))
        }
    }

    func cancel() { coordinator.pop() }
}

// MARK: - Builder

enum TripWizardBuilder {
    static func build(dependencies: AppDependencies, tripID: UUID?) -> TripWizardView {
        let interactor = TripWizardInteractor(repository: dependencies.repository)
        let router = TripWizardRouter(coordinator: dependencies.coordinator)
        let presenter = TripWizardPresenter(interactor: interactor, router: router, tripID: tripID)
        return TripWizardView(presenter: presenter)
    }
}
