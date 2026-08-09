//
//  EventFormModule.swift
//  WearLoop
//
//  Creating and editing an event, with the dress-code check and a reminder of
//  what was worn at similar events before.
//

import Combine
import SwiftUI

// MARK: - Contract

protocol EventFormInteractorProtocol: AnyObject {
    var repository: WardrobeRepositoryProtocol { get }
    func loadEvent(_ id: UUID) -> EventEntity?
    func save(_ event: EventEntity) -> SaveOutcome
    func delete(_ id: UUID)
    func markWorn(eventID: UUID, sendToWash: Bool)
    func undoWorn(eventID: UUID)
    func candidates(dressCode: DressCode, occasion: Occasion, date: Date) -> [OutfitListItem]
    /// Past events with the same dress code where this outfit was already worn.
    func previousWearings(outfitID: UUID, excluding eventID: UUID) -> String?
    func units() -> MeasurementUnits
    func hasOutfits() -> Bool
    func weatherLookup() -> WeatherLookup
}

protocol EventFormRouterProtocol: ModuleRouterProtocol {
    func finish()
    func closeAfterDelete()
    func openOutfit(_ id: UUID)
    func openBuildOutfit()
}

struct EventFormViewState {
    var isEditing: Bool = false
    var name: String = ""
    var date: Date = Date()
    var occasion: Occasion = .goingOut
    var dressCode: DressCode = .smartCasual
    var location: String = ""
    var weather: WeatherInput?
    var outfitID: UUID?
    var backupOutfitID: UUID?
    var notes: String = ""

    var outfitName: String?
    var outfitPieces: [Piece] = []
    var outfitStatus: OutfitStatus?
    var backupName: String?

    var isWorn: Bool = false
    var formalityWarning: String?
    var availabilityWarning: String?
    var weatherWarning: String?
    var repeatWarning: String?

    var nameError: String?
    var saveError: String?
    var isSaving: Bool = false
    var didSave: Bool = false
    var hasOutfits: Bool = true
    var units: MeasurementUnits = .metric
    var showHalftone: Bool = true

    var title: String { isEditing ? "edit event" : "add event" }
    var weatherText: String? {
        guard let weather else { return nil }
        var text = UnitFormatter.temperature(weather.temperatureC, units: units)
        if weather.rain { text += " · rain" }
        return text
    }
}

// MARK: - Interactor

final class EventFormInteractor: EventFormInteractorProtocol {
    let repository: WardrobeRepositoryProtocol
    private let weather: WeatherServiceProtocol
    private let location: LocationProviderProtocol

    init(
        repository: WardrobeRepositoryProtocol,
        weather: WeatherServiceProtocol,
        location: LocationProviderProtocol
    ) {
        self.repository = repository
        self.weather = weather
        self.location = location
    }

    func weatherLookup() -> WeatherLookup {
        WeatherLookup(
            service: weather,
            location: location,
            settings: repository.state.weatherSettings
        )
    }

    func loadEvent(_ id: UUID) -> EventEntity? { repository.state.event(id) }
    func units() -> MeasurementUnits { repository.state.profile.units }
    func hasOutfits() -> Bool { !repository.state.activeOutfits.isEmpty }

    func save(_ event: EventEntity) -> SaveOutcome {
        var updated = event
        updated.name = event.name.wlTrimmed
        let error = repository.mutateThrowing { state in
            if let index = state.events.firstIndex(where: { $0.id == updated.id }) {
                updated.createdAt = state.events[index].createdAt
                updated.wearRecordID = state.events[index].wearRecordID
                state.events[index] = updated
            } else {
                state.events.append(updated)
            }
        }
        if let error { return .failed(error) }
        return .saved(updated.id)
    }

    func delete(_ id: UUID) {
        repository.mutate { state in
            WardrobeActions.deleteEvent(id, in: &state)
        }
    }

    func markWorn(eventID: UUID, sendToWash: Bool) {
        repository.mutate { state in
            guard let index = state.events.firstIndex(where: { $0.id == eventID }),
                  let outfitID = state.events[index].outfitID,
                  state.events[index].wearRecordID == nil else { return }
            let recordID = WardrobeActions.recordWear(
                outfitID: outfitID,
                pieceIDs: [],
                date: state.events[index].date,
                context: .event,
                eventID: eventID,
                in: &state
            )
            state.events[index].wearRecordID = recordID
            if sendToWash, let outfit = state.outfit(outfitID) {
                WardrobeActions.sendToWash(pieceIDs: outfit.pieceIDs, in: &state)
            }
        }
    }

    func undoWorn(eventID: UUID) {
        repository.mutate { state in
            guard let index = state.events.firstIndex(where: { $0.id == eventID }),
                  let recordID = state.events[index].wearRecordID else { return }
            WardrobeActions.deleteWearRecord(recordID, in: &state)
        }
    }

    func candidates(dressCode: DressCode, occasion: Occasion, date: Date) -> [OutfitListItem] {
        let state = repository.state
        let required = dressCode.expectedFormality
        let ranked = SuggestionEngine.rank(
            outfits: state.activeOutfits,
            state: state,
            temperature: nil,
            occasion: occasion,
            requiredFormality: required
        )
        return ranked.map { outfit in
            let check = AvailabilityEngine.check(outfit: outfit, state: state, referenceDate: date)
            var subtitle = "\(outfit.formality.title) · \(outfit.occasion.title)"
            if let required, outfit.formality.rank < required.rank {
                subtitle = "Below the dress code · \(outfit.formality.title)"
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

    func previousWearings(outfitID: UUID, excluding eventID: UUID) -> String? {
        let state = repository.state
        // Wear records tied to another event that used the same outfit.
        let matches = state.wearRecords
            .filter { $0.outfitID == outfitID && $0.eventID != nil && $0.eventID != eventID }
            .sorted { $0.date > $1.date }
        guard let latest = matches.first else { return nil }
        let eventName = latest.eventID.flatMap { state.event($0)?.name }
        let dateText = DateFormatterCache.dayMonth.string(from: latest.date)
        if let eventName {
            return "You wore this outfit at \(eventName) on \(dateText)."
        }
        return "You wore this outfit at a similar event on \(dateText)."
    }
}

// MARK: - Presenter

final class EventFormPresenter: ObservableObject {
    @Published var viewState = EventFormViewState()
    @Published var isOutfitPickerPresented = false
    @Published var isBackupPickerPresented = false
    @Published var isWeatherPresented = false
    @Published var isMarkWornPresented = false
    @Published var toast: ToastMessage?
    @Published var confirm: ConfirmRequest?
    @Published var didDismissWarnings = false

    private let interactor: EventFormInteractorProtocol
    private let router: EventFormRouterProtocol
    private let eventID: UUID
    private let isExisting: Bool
    private var didLoad = false
    private var cancellables = Set<AnyCancellable>()

    init(interactor: EventFormInteractorProtocol, router: EventFormRouterProtocol, eventID: UUID?) {
        self.interactor = interactor
        self.router = router
        self.eventID = eventID ?? UUID()
        self.isExisting = eventID != nil
        viewState.isEditing = eventID != nil

        interactor.repository.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.recomputeDerived() }
            .store(in: &cancellables)
    }

    func onAppear() {
        viewState.units = interactor.units()
        viewState.hasOutfits = interactor.hasOutfits()

        if !didLoad {
            didLoad = true
            if isExisting, let event = interactor.loadEvent(eventID) {
                viewState.name = event.name
                viewState.date = event.date
                viewState.occasion = event.occasion
                viewState.dressCode = event.dressCode
                viewState.location = event.location
                viewState.weather = event.weather
                viewState.outfitID = event.outfitID
                viewState.backupOutfitID = event.backupOutfitID
                viewState.notes = event.notes
                viewState.isWorn = event.isWorn
            }
        }
        recomputeDerived()
    }

    /// Rebuilds the parts of the state that depend on the wardrobe.
    private func recomputeDerived() {
        let state = interactor.repository.state
        viewState.hasOutfits = !state.activeOutfits.isEmpty

        if isExisting, let event = interactor.loadEvent(eventID) {
            viewState.isWorn = event.isWorn
        }

        guard let outfitID = viewState.outfitID, let outfit = state.outfit(outfitID) else {
            viewState.outfitName = nil
            viewState.outfitPieces = []
            viewState.outfitStatus = nil
            viewState.formalityWarning = nil
            viewState.availabilityWarning = nil
            viewState.weatherWarning = nil
            viewState.repeatWarning = nil
            viewState.backupName = viewState.backupOutfitID.flatMap { state.outfit($0)?.name }
            return
        }

        viewState.outfitName = outfit.name
        viewState.outfitPieces = outfit.items.compactMap { state.piece($0.pieceID) }
        viewState.backupName = viewState.backupOutfitID.flatMap { state.outfit($0)?.name }

        let check = AvailabilityEngine.check(outfit: outfit, state: state, referenceDate: viewState.date)
        viewState.outfitStatus = check.status

        if let required = viewState.dressCode.expectedFormality {
            viewState.formalityWarning = AvailabilityEngine.formalityMismatch(
                outfit: outfit,
                required: required,
                requiredLabel: "event"
            )
        } else {
            viewState.formalityWarning = nil
        }

        if !check.isAvailable {
            viewState.availabilityWarning = check.earliestReturn.map {
                "\(Plural.count(check.unavailablePieceIDs.count, "piece")) in this outfit are unavailable until \(DateFormatterCache.relativeDayText($0, now: Date()))."
            } ?? "\(Plural.count(check.unavailablePieceIDs.count, "piece")) in this outfit are unavailable."
        } else {
            viewState.availabilityWarning = nil
        }

        if let weather = viewState.weather {
            viewState.weatherWarning = AvailabilityEngine.weatherMismatch(
                outfit: outfit,
                weather: weather,
                units: viewState.units,
                dayLabel: "This event"
            )
        } else {
            viewState.weatherWarning = nil
        }

        viewState.repeatWarning = interactor.previousWearings(outfitID: outfitID, excluding: eventID)
    }

    var candidates: [OutfitListItem] {
        interactor.candidates(
            dressCode: viewState.dressCode,
            occasion: viewState.occasion,
            date: viewState.date
        )
    }

    // MARK: Intents

    func setName(_ value: String) {
        viewState.name = value
        if !value.wlIsBlank { viewState.nameError = nil }
    }

    func setDate(_ value: Date) {
        viewState.date = value
        recomputeDerived()
    }

    func setOccasion(_ value: Occasion) { viewState.occasion = value }

    func setDressCode(_ value: DressCode) {
        viewState.dressCode = value
        didDismissWarnings = false
        recomputeDerived()
    }

    func didTapAssign() { isOutfitPickerPresented = true }
    func didTapAssignBackup() { isBackupPickerPresented = true }
    func didTapWeather() { isWeatherPresented = true }

    /// Fetches the forecast for the event's own date.
    func fetchWeatherForEvent() async -> WeatherLookupOutcome {
        await interactor.weatherLookup().weather(on: viewState.date)
    }

    var canFetchWeather: Bool { interactor.weatherLookup().isAvailable }
    var weatherFetchUnavailableReason: String? { interactor.weatherLookup().unavailableReason }
    func didTapBuildOutfit() { router.openBuildOutfit() }

    func didTapOpenOutfit() {
        guard let id = viewState.outfitID else { return }
        router.openOutfit(id)
    }

    func didPickOutfit(_ id: UUID, isBackup: Bool) {
        if isBackup {
            viewState.backupOutfitID = id
            isBackupPickerPresented = false
        } else {
            viewState.outfitID = id
            isOutfitPickerPresented = false
            didDismissWarnings = false
        }
        recomputeDerived()
        // Save straight away when editing, so the assignment is not lost.
        if isExisting { persist(silent: true) }
    }

    func didTapClearOutfit() {
        viewState.outfitID = nil
        recomputeDerived()
        if isExisting { persist(silent: true) }
    }

    func didSaveWeather(_ weather: WeatherInput?) {
        viewState.weather = weather
        isWeatherPresented = false
        didDismissWarnings = false
        recomputeDerived()
        if isExisting { persist(silent: true) }
    }

    func didTapKeepAnyway() { didDismissWarnings = true }

    func didTapSave() { persist(silent: false) }

    private func persist(silent: Bool) {
        guard !viewState.isSaving else { return }
        viewState.nameError = viewState.name.wlIsBlank ? "Enter a name for this event." : nil
        guard viewState.nameError == nil else { return }

        viewState.isSaving = true
        viewState.saveError = nil

        let event = EventEntity(
            id: eventID,
            name: viewState.name,
            date: viewState.date,
            occasion: viewState.occasion,
            dressCode: viewState.dressCode,
            location: viewState.location.wlTrimmed,
            weather: viewState.weather,
            outfitID: viewState.outfitID,
            backupOutfitID: viewState.backupOutfitID,
            notes: viewState.notes.wlTrimmed
        )

        switch interactor.save(event) {
        case .saved:
            viewState.isSaving = false
            if silent {
                recomputeDerived()
            } else {
                viewState.didSave = true
                router.finish()
            }
        case .failed(let message):
            viewState.isSaving = false
            viewState.saveError = message
        }
    }

    func didTapMarkWorn() {
        guard viewState.outfitID != nil, !viewState.isWorn else { return }
        // Make sure the event exists before a record points at it.
        if !isExisting && !viewState.didSave { persist(silent: true) }
        isMarkWornPresented = true
    }

    func didConfirmMarkWorn(sendToWash: Bool) {
        interactor.markWorn(eventID: eventID, sendToWash: sendToWash)
        isMarkWornPresented = false
        recomputeDerived()
        toast = ToastMessage(
            text: sendToWash ? "Recorded and sent to the wash" : "Recorded as worn",
            kind: .success
        )
    }

    func didTapUndoWorn() {
        confirm = ConfirmRequest(
            title: "Remove This Wear Record?",
            message: "The event goes back to planned and the statistics lose this wearing.",
            confirmTitle: "Remove Record",
            isDestructive: true,
            onConfirm: { [weak self] in
                guard let self else { return }
                self.interactor.undoWorn(eventID: self.eventID)
                self.recomputeDerived()
                self.toast = ToastMessage(text: "Wear record removed", kind: .info)
            }
        )
    }

    func didTapDelete() {
        confirm = ConfirmRequest(
            title: "Delete This Event?",
            message: viewState.isWorn
                ? "The event is removed. The wear record made for it stays, because it describes what you actually wore."
                : "The event and its outfit assignment are removed.",
            confirmTitle: "Delete Event",
            cancelTitle: "Keep",
            isDestructive: true,
            onConfirm: { [weak self] in
                guard let self else { return }
                self.interactor.delete(self.eventID)
                self.router.closeAfterDelete()
            }
        )
    }
}

// MARK: - Router

final class EventFormRouter: EventFormRouterProtocol {
    let coordinator: NavigationCoordinator

    init(coordinator: NavigationCoordinator) {
        self.coordinator = coordinator
    }

    func finish() { coordinator.pop() }
    func closeAfterDelete() { coordinator.pop() }
    func openOutfit(_ id: UUID) { coordinator.push(.outfitDetails(id)) }
    func openBuildOutfit() { coordinator.jump(to: .outfits, then: .outfitBuilder(outfitID: nil, prefillPieceID: nil)) }
}

// MARK: - Builder

enum EventFormBuilder {
    static func build(dependencies: AppDependencies, eventID: UUID?) -> EventFormView {
        let interactor = EventFormInteractor(
            repository: dependencies.repository,
            weather: dependencies.weather,
            location: dependencies.location
        )
        let router = EventFormRouter(coordinator: dependencies.coordinator)
        let presenter = EventFormPresenter(interactor: interactor, router: router, eventID: eventID)
        return EventFormView(presenter: presenter)
    }
}
