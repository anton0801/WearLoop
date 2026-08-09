//
//  PlannerModule.swift
//  WearLoop
//
//  Two weeks ahead. Assigning an outfit never counts as wearing it — that is
//  always a separate, explicit confirmation.
//

import Combine
import SwiftUI

// MARK: - Contract

protocol PlannerInteractorProtocol: AnyObject {
    var repository: WardrobeRepositoryProtocol { get }
    func buildViewState(selected: Date, now: Date) -> PlannerViewState
    func assignOutfit(_ outfitID: UUID?, to date: Date, isBackup: Bool)
    func setOccasion(_ occasion: Occasion?, for date: Date)
    func setWeather(_ weather: WeatherInput?, for date: Date)
    func weatherLookup() -> WeatherLookup
    func setNotes(_ notes: String, for date: Date)
    func clearAssignment(for date: Date)
    func markWorn(date: Date, sendToWash: Bool)
    func undoWorn(date: Date)
    /// Outfits ranked for this day's weather and occasion.
    func candidates(for date: Date) -> [OutfitListItem]
}

protocol PlannerRouterProtocol: ModuleRouterProtocol {
    func openOutfit(_ id: UUID)
    func openBuildOutfit()
    func openEvents()
}

struct PlannerViewState {
    var days: [WearCalendarDay] = []
    var selectedDate: Date = Date()
    var selectedDayTitle: String = ""
    var selectedDaySubtitle: String = ""

    var occasion: Occasion?
    var weather: WeatherInput?
    var weatherTemperatureText: String?
    var weatherDetailText: String?
    var notes: String = ""

    var assignedOutfit: Outfit?
    var assignedPieces: [Piece] = []
    var assignedStatus: OutfitStatus?
    var backupOutfit: Outfit?

    var isWorn: Bool = false
    var isPast: Bool = false
    var weatherMismatch: String?
    var rainWarning: String?
    var availabilityNote: String?

    /// Event happening on the selected day, if any.
    var eventName: String?

    var hasOutfits: Bool = false
    var units: MeasurementUnits = .metric
    var showHalftone: Bool = true
}

// MARK: - Interactor

final class PlannerInteractor: PlannerInteractorProtocol {
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

    func buildViewState(selected: Date, now: Date) -> PlannerViewState {
        let state = repository.state
        var view = PlannerViewState()
        view.units = state.profile.units
        view.showHalftone = state.appearance.showHalftoneMotif
        view.selectedDate = selected.wlStartOfDay
        view.hasOutfits = !state.activeOutfits.isEmpty

        // A week behind and a fortnight ahead.
        let start = Calendar.wl.addingDays(-7, to: now.wlStartOfDay)
        let end = Calendar.wl.addingDays(14, to: now.wlStartOfDay)

        // A day counts as worn when any record falls on it, whichever screen
        // recorded it — a day plan, an event, a trip or a single piece.
        let wornDays = Set(state.wearRecords.map { $0.date.wlStartOfDay })

        view.days = start.wlDays(through: end).map { day in
            let plan = state.dayPlan(for: day)
            return WearCalendarDay(
                date: day,
                isWorn: wornDays.contains(day),
                isPlanned: plan?.outfitID != nil,
                isToday: Calendar.wl.isSameDay(day, now)
            )
        }

        let day = selected.wlStartOfDay
        view.isPast = day < now.wlStartOfDay
        view.selectedDayTitle = DateFormatterCache.weekdayLong.string(from: day).lowercased()
        view.selectedDaySubtitle = DateFormatterCache.dayMonthYear.string(from: day)

        let plan = state.dayPlan(for: day)
        view.occasion = plan?.occasion
        view.weather = plan?.weather
        view.notes = plan?.notes ?? ""
        view.isWorn = plan?.isWorn ?? false

        if let weather = plan?.weather {
            view.weatherTemperatureText = UnitFormatter.temperature(
                weather.temperatureC,
                units: state.profile.units
            )
            var details: [String] = []
            if weather.rain { details.append("rain expected") }
            if let wind = weather.windKph, wind > 0 { details.append("\(Int(wind.rounded())) km/h wind") }
            if let place = weather.locationName { details.append(place) }
            view.weatherDetailText = details.isEmpty ? nil : details.joined(separator: " · ")
        }

        if let outfitID = plan?.outfitID, let outfit = state.outfit(outfitID) {
            view.assignedOutfit = outfit
            view.assignedPieces = outfit.items.compactMap { state.piece($0.pieceID) }
            let check = AvailabilityEngine.check(outfit: outfit, state: state, referenceDate: day)
            view.assignedStatus = check.status
            if !check.isAvailable {
                if let back = check.earliestReturn {
                    view.availabilityNote = "\(Plural.count(check.unavailablePieceIDs.count, "piece")) in this outfit are unavailable until \(DateFormatterCache.relativeDayText(back, now: now))."
                } else {
                    view.availabilityNote = "\(Plural.count(check.unavailablePieceIDs.count, "piece")) in this outfit are unavailable."
                }
            }
            if let weather = plan?.weather {
                let label = Calendar.wl.isSameDay(day, now)
                    ? "Today"
                    : DateFormatterCache.relativeDayText(day, now: now).capitalizedFirst
                view.weatherMismatch = AvailabilityEngine.weatherMismatch(
                    outfit: outfit,
                    weather: weather,
                    units: state.profile.units,
                    dayLabel: label
                )
                view.rainWarning = AvailabilityEngine.rainWarning(outfit: outfit, weather: weather, state: state)
            }
        }

        if let backupID = plan?.backupOutfitID {
            view.backupOutfit = state.outfit(backupID)
        }

        if let event = state.events.first(where: { Calendar.wl.isSameDay($0.date, day) }) {
            view.eventName = event.name
        }

        return view
    }

    func candidates(for date: Date) -> [OutfitListItem] {
        let state = repository.state
        let day = date.wlStartOfDay
        let plan = state.dayPlan(for: day)
        let ranked = SuggestionEngine.rank(
            outfits: state.activeOutfits,
            state: state,
            temperature: plan?.weather?.temperatureC,
            occasion: plan?.occasion,
            requiredFormality: nil
        )
        return ranked.map { outfit in
            let check = AvailabilityEngine.check(outfit: outfit, state: state, referenceDate: day)
            return OutfitListItem(
                outfit: outfit,
                pieces: outfit.items.compactMap { state.piece($0.pieceID) },
                status: check.status,
                subtitle: subtitleFor(outfit: outfit, check: check, plan: plan, state: state)
            )
        }
    }

    private func subtitleFor(outfit: Outfit, check: OutfitCheck, plan: DayPlan?, state: AppState) -> String {
        if let temperature = plan?.weather?.temperatureC,
           temperature >= outfit.temperatureMin, temperature <= outfit.temperatureMax {
            return "Fits the weather · \(outfit.occasion.title)"
        }
        if check.status != .ready, let back = check.earliestReturn {
            return "Back \(DateFormatterCache.relativeDayText(back))"
        }
        if check.status != .ready {
            return "\(Plural.count(check.unavailablePieceIDs.count, "piece")) unavailable"
        }
        return "\(outfit.occasion.title) · \(outfit.temperatureText)"
    }

    // MARK: Mutations

    private func withPlan(_ date: Date, _ block: @escaping (inout DayPlan) -> Void) {
        repository.mutate { state in
            let planID = WardrobeActions.ensureDayPlan(for: date, in: &state)
            guard let index = state.dayPlans.firstIndex(where: { $0.id == planID }) else { return }
            block(&state.dayPlans[index])
        }
    }

    func assignOutfit(_ outfitID: UUID?, to date: Date, isBackup: Bool) {
        withPlan(date) { plan in
            if isBackup {
                plan.backupOutfitID = outfitID
            } else {
                plan.outfitID = outfitID
            }
        }
    }

    func setOccasion(_ occasion: Occasion?, for date: Date) {
        withPlan(date) { $0.occasion = occasion }
    }

    func setWeather(_ weather: WeatherInput?, for date: Date) {
        withPlan(date) { $0.weather = weather }
    }

    func setNotes(_ notes: String, for date: Date) {
        withPlan(date) { $0.notes = notes }
    }

    func clearAssignment(for date: Date) {
        withPlan(date) { plan in
            plan.outfitID = nil
            plan.backupOutfitID = nil
        }
    }

    func markWorn(date: Date, sendToWash: Bool) {
        repository.mutate { state in
            let planID = WardrobeActions.ensureDayPlan(for: date, in: &state)
            guard let index = state.dayPlans.firstIndex(where: { $0.id == planID }),
                  let outfitID = state.dayPlans[index].outfitID else { return }
            // Nothing is marked worn twice for the same day.
            guard state.dayPlans[index].wearRecordID == nil else { return }
            let recordID = WardrobeActions.recordWear(
                outfitID: outfitID,
                pieceIDs: [],
                date: date,
                context: .day,
                in: &state
            )
            state.dayPlans[index].wearRecordID = recordID
            if sendToWash, let outfit = state.outfit(outfitID) {
                WardrobeActions.sendToWash(pieceIDs: outfit.pieceIDs, in: &state)
            }
        }
    }

    func undoWorn(date: Date) {
        repository.mutate { state in
            guard let index = state.dayPlans.firstIndex(where: { $0.date.wlStartOfDay == date.wlStartOfDay }),
                  let recordID = state.dayPlans[index].wearRecordID else { return }
            WardrobeActions.deleteWearRecord(recordID, in: &state)
        }
    }
}

// MARK: - Presenter

final class PlannerPresenter: ObservableObject {
    @Published private(set) var viewState = PlannerViewState()
    @Published var selectedDate: Date = Date().wlStartOfDay { didSet { refresh() } }
    @Published var isOutfitPickerPresented = false
    @Published var isBackupPickerPresented = false
    @Published var isWeatherPresented = false
    @Published var isMarkWornPresented = false
    @Published var toast: ToastMessage?
    @Published var confirm: ConfirmRequest?
    /// Set when the user chose to keep an outfit despite a weather warning.
    @Published var dismissedWarningDates: Set<Date> = []

    private let interactor: PlannerInteractorProtocol
    private let router: PlannerRouterProtocol
    private var cancellables = Set<AnyCancellable>()

    init(interactor: PlannerInteractorProtocol, router: PlannerRouterProtocol) {
        self.interactor = interactor
        self.router = router
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
        viewState = interactor.buildViewState(selected: selectedDate, now: Date())
    }

    var candidates: [OutfitListItem] { interactor.candidates(for: selectedDate) }

    var showsWeatherWarning: Bool {
        guard viewState.weatherMismatch != nil || viewState.rainWarning != nil else { return false }
        return !dismissedWarningDates.contains(viewState.selectedDate)
    }

    // MARK: Intents

    func didSelectDay(_ date: Date) { selectedDate = date.wlStartOfDay }
    func didTapAssign() { isOutfitPickerPresented = true }
    func didTapAssignBackup() { isBackupPickerPresented = true }
    func didTapWeather() { isWeatherPresented = true }

    /// Fetches the forecast for whichever day is selected.
    func fetchWeatherForSelectedDay() async -> WeatherLookupOutcome {
        await interactor.weatherLookup().weather(on: selectedDate)
    }

    var canFetchWeather: Bool { interactor.weatherLookup().isAvailable }
    var weatherFetchUnavailableReason: String? { interactor.weatherLookup().unavailableReason }
    func didTapOutfit(_ id: UUID) { router.openOutfit(id) }
    func didTapBuildOutfit() { router.openBuildOutfit() }
    func didTapEvents() { router.openEvents() }

    func didPickOutfit(_ id: UUID, isBackup: Bool) {
        interactor.assignOutfit(id, to: selectedDate, isBackup: isBackup)
        dismissedWarningDates.remove(viewState.selectedDate)
        isOutfitPickerPresented = false
        isBackupPickerPresented = false
        toast = ToastMessage(text: isBackup ? "Backup outfit set" : "Outfit assigned", kind: .success)
    }

    func didSetOccasion(_ occasion: Occasion?) {
        interactor.setOccasion(occasion, for: selectedDate)
    }

    func didSaveWeather(_ weather: WeatherInput?) {
        interactor.setWeather(weather, for: selectedDate)
        dismissedWarningDates.remove(viewState.selectedDate)
        isWeatherPresented = false
        toast = ToastMessage(text: weather == nil ? "Weather cleared" : "Weather saved", kind: .success)
    }

    func didEditNotes(_ notes: String) {
        interactor.setNotes(notes, for: selectedDate)
    }

    func didTapClearAssignment() {
        confirm = ConfirmRequest(
            title: "Clear This Day?",
            message: "The assigned and backup outfits are removed. Nothing else about the day changes.",
            confirmTitle: "Clear",
            isDestructive: true,
            onConfirm: { [weak self] in
                guard let self else { return }
                self.interactor.clearAssignment(for: self.selectedDate)
                self.toast = ToastMessage(text: "Day cleared", kind: .info)
            }
        )
    }

    func didTapKeepAnyway() {
        dismissedWarningDates.insert(viewState.selectedDate)
    }

    func didTapMarkWorn() { isMarkWornPresented = true }

    func didConfirmMarkWorn(sendToWash: Bool) {
        interactor.markWorn(date: selectedDate, sendToWash: sendToWash)
        isMarkWornPresented = false
        toast = ToastMessage(
            text: sendToWash ? "Marked as worn and sent to the wash" : "Marked as worn",
            kind: .success
        )
    }

    func didTapUndoWorn() {
        confirm = ConfirmRequest(
            title: "Remove This Wear Record?",
            message: "The day goes back to planned, and the statistics lose this wearing. Pieces already sent to the wash stay there.",
            confirmTitle: "Remove Record",
            isDestructive: true,
            onConfirm: { [weak self] in
                guard let self else { return }
                self.interactor.undoWorn(date: self.selectedDate)
                self.toast = ToastMessage(text: "Wear record removed", kind: .info)
            }
        )
    }
}

// MARK: - Router

final class PlannerRouter: PlannerRouterProtocol {
    let coordinator: NavigationCoordinator

    init(coordinator: NavigationCoordinator) {
        self.coordinator = coordinator
    }

    func openOutfit(_ id: UUID) { coordinator.push(.outfitDetails(id)) }
    func openBuildOutfit() { coordinator.push(.outfitBuilder(outfitID: nil, prefillPieceID: nil)) }
    func openEvents() { coordinator.push(.events) }
}

// MARK: - Builder

enum PlannerBuilder {
    static func build(dependencies: AppDependencies) -> PlannerView {
        let interactor = PlannerInteractor(
            repository: dependencies.repository,
            weather: dependencies.weather,
            location: dependencies.location
        )
        let router = PlannerRouter(coordinator: dependencies.coordinator)
        let presenter = PlannerPresenter(interactor: interactor, router: router)
        return PlannerView(presenter: presenter)
    }
}
