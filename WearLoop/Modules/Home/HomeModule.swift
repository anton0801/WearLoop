//
//  HomeModule.swift
//  WearLoop
//
//  "What to wear". The screen changes shape with the state of the data: empty
//  wardrobe, pieces without outfits, or the full picture.
//

import Combine
import SwiftUI

// MARK: - Contract

protocol HomeInteractorProtocol: AnyObject {
    var repository: WardrobeRepositoryProtocol { get }
    func buildViewState(now: Date) -> HomeViewState
    func saveWeather(_ weather: WeatherInput?, for date: Date)
    func weatherLookup() -> WeatherLookup
    /// Fetches today's weather in the background when the settings allow it.
    /// Returns nothing to show — a silent failure simply leaves what is there.
    func refreshTodayWeatherIfNeeded() async
    /// Confirms today's suggested outfit as worn.
    func markWorn(outfitID: UUID, date: Date, sendToWash: Bool)
    func returnFromWash(pieceIDs: [UUID])
}

protocol HomeRouterProtocol: ModuleRouterProtocol {
    func openAddPiece()
    func openBuildOutfit()
    func openHowItWorks()
    func openSettings()
    func openPlanner()
    func openLaundry()
    func openPieceDetails(_ id: UUID)
    func openOutfitDetails(_ id: UUID)
    func openEvents()
    func openEvent(_ id: UUID)
    func openTrip(_ id: UUID)
    func openTripDayPlan(_ id: UUID)
    func openWeightCheck(_ id: UUID)
    func openRepairs()
    func openTripMode(_ id: UUID)
}

/// Which shape the screen takes.
enum HomeMode: Equatable {
    case emptyWardrobe
    case piecesWithoutOutfits(pieceCount: Int)
    case full
}

struct HomeTripSummary: Equatable {
    var id: UUID
    var name: String
    var destination: String
    var startText: String
    var passedChecks: Int
    var totalChecks: Int
    var isInProgress: Bool
    var dayText: String?
}

struct HomeWashItem: Identifiable, Equatable {
    var id: UUID
    var name: String
    var backText: String
    var isOverdue: Bool
}

struct HomeViewState {
    var mode: HomeMode = .emptyWardrobe
    var greeting: String = "today"
    var dateText: String = ""

    // Today's look
    var suggestedOutfit: Outfit?
    var suggestedPieces: [Piece] = []
    var suggestionReasons: [String] = []
    /// Set when the planner already has an outfit assigned for today.
    var isAssignedForToday: Bool = false
    var todayAlreadyWorn: Bool = false
    var weatherMismatch: String?

    // Weather
    var weather: WeatherInput?
    /// The figure on its own, so it never has to wrap.
    var weatherTemperatureText: String?
    /// Wind and rain, shown underneath.
    var weatherDetailText: String?

    // Event
    var nextEventID: UUID?
    var nextEventName: String?
    var nextEventDetail: String?
    var nextEventHasOutfit: Bool = false

    // Trip
    var trip: HomeTripSummary?

    // Wash
    var inWash: [HomeWashItem] = []
    var readyToReturnIDs: [UUID] = []

    // Next step
    var nextStep: NextStep?

    // Rails
    var recentlyWorn: [Piece] = []
    var neverWorn: [Piece] = []

    var units: MeasurementUnits = .metric
    var showHalftone: Bool = true
}

// MARK: - Interactor

final class HomeInteractor: HomeInteractorProtocol {
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

    /// Keeps today's reading current without the user asking. A value typed by
    /// hand always wins — this only fills a gap or replaces a stale fetch.
    func refreshTodayWeatherIfNeeded() async {
        let state = repository.state
        guard state.weatherSettings.updateAutomatically,
              state.weatherSettings.hasPlace,
              weather.isConfigured else { return }

        let today = Date().wlStartOfDay
        let existing = state.dayPlan(for: today)?.weather
        if let existing {
            guard existing.source.isFetched, existing.isStale() else { return }
        }

        let outcome = await weatherLookup().weather(on: today)
        guard let fetched = outcome.input else { return }

        await MainActor.run {
            // The document may have changed while the request was in flight.
            let current = self.repository.state.dayPlan(for: today)?.weather
            if let current, !current.source.isFetched { return }
            self.saveWeather(fetched, for: today)
        }
    }

    func buildViewState(now: Date) -> HomeViewState {
        let state = repository.state
        var view = HomeViewState()
        view.units = state.profile.units
        view.showHalftone = state.appearance.showHalftoneMotif
        view.dateText = DateFormatterCache.weekdayLong.string(from: now).lowercased()

        let name = state.profile.greetingName
        view.greeting = name.isEmpty ? "today" : "hello, \(name.lowercased())"

        // Mode
        if state.activePieces.isEmpty {
            view.mode = .emptyWardrobe
            return view
        }
        if state.activeOutfits.isEmpty {
            view.mode = .piecesWithoutOutfits(pieceCount: state.activePieces.count)
            view.nextStep = NextStepEngine.nextStep(state: state, now: now)
            view.neverWorn = neverWornPieces(state: state)
            return view
        }
        view.mode = .full

        let today = now.wlStartOfDay
        let plan = state.dayPlan(for: today)
        view.weather = plan?.weather
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

        // Today's look: an assigned outfit wins over a suggestion.
        if let assignedID = plan?.outfitID, let assigned = state.outfit(assignedID) {
            view.suggestedOutfit = assigned
            view.isAssignedForToday = true
            view.suggestionReasons = ["You assigned this outfit to today in the planner."]
        } else if let suggestion = SuggestionEngine.suggest(
            for: today,
            state: state,
            weather: plan?.weather,
            occasion: plan?.occasion
        ) {
            view.suggestedOutfit = suggestion.outfit
            view.suggestionReasons = suggestion.reasons
        }

        if let outfit = view.suggestedOutfit {
            view.suggestedPieces = outfit.items.compactMap { state.piece($0.pieceID) }
            if let weather = plan?.weather {
                view.weatherMismatch = AvailabilityEngine.weatherMismatch(
                    outfit: outfit,
                    weather: weather,
                    units: state.profile.units,
                    dayLabel: "Today"
                )
            }
        }
        view.todayAlreadyWorn = plan?.isWorn ?? false

        // Next event
        if let event = state.nextEvent {
            view.nextEventID = event.id
            view.nextEventName = event.name
            let dayText = DateFormatterCache.relativeDayText(event.date, now: now)
            view.nextEventHasOutfit = event.outfitID != nil
            if let outfitID = event.outfitID, let outfit = state.outfit(outfitID) {
                view.nextEventDetail = "\(dayText.capitalizedFirst) · \(outfit.name)"
            } else {
                view.nextEventDetail = "\(dayText.capitalizedFirst) · no outfit yet"
            }
        }

        // Trip
        let activeTrip = state.tripInProgress ?? state.nextTrip
        if let trip = activeTrip {
            let readiness = TripReadinessEngine.readiness(trip: trip, state: state, now: now)
            var dayText: String?
            if trip.stage == .inProgress, let day = trip.currentDay(now: now) {
                dayText = "Day \(day.dayNumber) of \(trip.dayCount)"
            }
            view.trip = HomeTripSummary(
                id: trip.id,
                name: trip.name,
                destination: trip.destination,
                startText: trip.stage == .inProgress
                    ? "In progress"
                    : "Starts \(DateFormatterCache.relativeDayText(trip.startDate, now: now))",
                passedChecks: readiness.passedCount,
                totalChecks: readiness.totalCount,
                isInProgress: trip.stage == .inProgress,
                dayText: dayText
            )
        }

        // In the wash
        view.inWash = state.piecesInWash.map { piece in
            let back = piece.expectedBackDate
            let overdue = back.map { $0.wlStartOfDay < today } ?? false
            return HomeWashItem(
                id: piece.id,
                name: piece.name,
                backText: back.map { "Back by \(DateFormatterCache.relativeDayText($0, now: now))" } ?? "No return date",
                isOverdue: overdue
            )
        }
        view.readyToReturnIDs = state.laundryLoads
            .filter { $0.stage == .readyToReturn }
            .flatMap(\.pieceIDs)

        view.nextStep = NextStepEngine.nextStep(state: state, now: now)

        // Rails
        let recentIDs = state.wearRecords
            .sorted { $0.date > $1.date }
            .flatMap(\.pieceIDs)
            .wlUnique
            .prefix(12)
        view.recentlyWorn = recentIDs.compactMap { state.piece($0) }
        view.neverWorn = neverWornPieces(state: state)

        return view
    }

    private func neverWornPieces(state: AppState) -> [Piece] {
        state.activePieces
            .filter { state.wearCount(forPiece: $0.id) == 0 }
            .sorted { $0.createdAt < $1.createdAt }
            .prefix(12)
            .map { $0 }
    }

    func saveWeather(_ weather: WeatherInput?, for date: Date) {
        repository.mutate { state in
            let planID = WardrobeActions.ensureDayPlan(for: date, in: &state)
            guard let index = state.dayPlans.firstIndex(where: { $0.id == planID }) else { return }
            state.dayPlans[index].weather = weather
        }
    }

    func markWorn(outfitID: UUID, date: Date, sendToWash: Bool) {
        repository.mutate { state in
            let planID = WardrobeActions.ensureDayPlan(for: date, in: &state)
            guard let index = state.dayPlans.firstIndex(where: { $0.id == planID }) else { return }
            state.dayPlans[index].outfitID = outfitID
            // Replace any record already held for today rather than leaving an
            // orphan behind in the statistics.
            if let existing = state.dayPlans[index].wearRecordID {
                WardrobeActions.deleteWearRecord(existing, in: &state)
            }
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

    func returnFromWash(pieceIDs: [UUID]) {
        repository.mutate { state in
            WardrobeActions.returnFromWash(pieceIDs: pieceIDs, in: &state)
        }
    }
}

// MARK: - Presenter

final class HomePresenter: ObservableObject {
    @Published private(set) var viewState = HomeViewState()
    @Published var toast: ToastMessage?
    @Published var isWeatherSheetPresented = false
    @Published var isMarkWornSheetPresented = false
    /// Set when the user chose to keep today's outfit despite the weather.
    @Published var didDismissWeatherWarning = false

    private let interactor: HomeInteractorProtocol
    private let router: HomeRouterProtocol
    private var cancellables = Set<AnyCancellable>()
    private var didRequestWeather = false

    init(interactor: HomeInteractorProtocol, router: HomeRouterProtocol) {
        self.interactor = interactor
        self.router = router
    }

    func onAppear() {
        observeStoreIfNeeded()
        refresh()
        refreshWeatherOnce()
    }

    /// Runs once per screen lifetime, so returning to Home does not re-request.
    private func refreshWeatherOnce() {
        guard !didRequestWeather else { return }
        didRequestWeather = true
        Task { [interactor] in await interactor.refreshTodayWeatherIfNeeded() }
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
        viewState = interactor.buildViewState(now: Date())
    }

    // MARK: Intents

    func didTapAddPiece() { router.openAddPiece() }
    func didTapBuildOutfit() { router.openBuildOutfit() }
    func didTapHowItWorks() { router.openHowItWorks() }
    func didTapProfile() { router.openSettings() }
    func didTapPlanner() { router.openPlanner() }
    func didTapLaundry() { router.openLaundry() }
    func didTapPiece(_ id: UUID) { router.openPieceDetails(id) }
    func didTapEvents() { router.openEvents() }

    func didTapSuggestedOutfit() {
        guard let outfit = viewState.suggestedOutfit else { return }
        router.openOutfitDetails(outfit.id)
    }

    func didTapEvent() {
        guard let id = viewState.nextEventID else { return }
        router.openEvent(id)
    }

    func didTapTrip() {
        guard let trip = viewState.trip else { return }
        if trip.isInProgress {
            router.openTripMode(trip.id)
        } else {
            router.openTrip(trip.id)
        }
    }

    func didTapSetWeather() { isWeatherSheetPresented = true }

    /// Fetches today's conditions for the weather sheet.
    func fetchWeatherForToday() async -> WeatherLookupOutcome {
        await interactor.weatherLookup().weather(on: Date())
    }

    var canFetchWeather: Bool { interactor.weatherLookup().isAvailable }
    var weatherFetchUnavailableReason: String? { interactor.weatherLookup().unavailableReason }

    func didTapKeepAnyway() { didDismissWeatherWarning = true }

    /// True only while the mismatch still stands and has not been waved through.
    var showsWeatherWarning: Bool {
        viewState.weatherMismatch != nil && !didDismissWeatherWarning
    }

    func didSaveWeather(_ weather: WeatherInput?) {
        interactor.saveWeather(weather, for: Date())
        didDismissWeatherWarning = false
        isWeatherSheetPresented = false
        toast = ToastMessage(text: weather == nil ? "Weather cleared" : "Weather saved", kind: .success)
    }

    func didTapMarkWorn() {
        guard viewState.suggestedOutfit != nil, !viewState.todayAlreadyWorn else { return }
        isMarkWornSheetPresented = true
    }

    func didConfirmMarkWorn(sendToWash: Bool) {
        guard let outfit = viewState.suggestedOutfit else { return }
        interactor.markWorn(outfitID: outfit.id, date: Date(), sendToWash: sendToWash)
        isMarkWornSheetPresented = false
        toast = ToastMessage(
            text: sendToWash ? "Marked as worn and sent to the wash" : "Marked as worn",
            kind: .success
        )
    }

    func didTapReturnLaundry() {
        let ids = viewState.readyToReturnIDs
        guard !ids.isEmpty else {
            router.openLaundry()
            return
        }
        interactor.returnFromWash(pieceIDs: ids)
        toast = ToastMessage(text: "\(Plural.count(ids.count, "piece")) back in rotation", kind: .success)
    }

    func didTapNextStep() {
        guard let step = viewState.nextStep else { return }
        switch step.action {
        case .addPiece: router.openAddPiece()
        case .buildOutfit: router.openBuildOutfit()
        case .assignEventOutfit(let id): router.openEvent(id)
        case .planTripDays(let id): router.openTripDayPlan(id)
        case .returnLaundry: router.openLaundry()
        case .fixRepairs: router.openRepairs()
        case .planTomorrow: router.openPlanner()
        case .completeSetup: router.openSettings()
        case .reviewTripWeight(let id): router.openWeightCheck(id)
        }
    }
}

// MARK: - Router

final class HomeRouter: HomeRouterProtocol {
    let coordinator: NavigationCoordinator

    init(coordinator: NavigationCoordinator) {
        self.coordinator = coordinator
    }

    func openAddPiece() { coordinator.jump(to: .wardrobe, then: .pieceForm(pieceID: nil)) }
    func openBuildOutfit() { coordinator.jump(to: .outfits, then: .outfitBuilder(outfitID: nil, prefillPieceID: nil)) }
    func openHowItWorks() { coordinator.push(.howItWorks) }
    func openSettings() { coordinator.push(.settings) }
    func openPlanner() { coordinator.push(.planner) }
    func openLaundry() { coordinator.push(.laundry) }
    func openPieceDetails(_ id: UUID) { coordinator.jump(to: .wardrobe, then: .pieceDetails(id)) }
    func openOutfitDetails(_ id: UUID) { coordinator.jump(to: .outfits, then: .outfitDetails(id)) }
    func openEvents() { coordinator.push(.events) }
    func openEvent(_ id: UUID) { coordinator.push(.eventForm(eventID: id)) }
    func openTrip(_ id: UUID) { coordinator.jump(to: .trips, then: .tripWorkspace(id)) }
    func openTripDayPlan(_ id: UUID) { coordinator.jump(to: .trips, then: .tripDayPlan(id)) }
    func openWeightCheck(_ id: UUID) { coordinator.jump(to: .trips, then: .weightCheck(id)) }
    func openRepairs() { coordinator.push(.repairs) }
    func openTripMode(_ id: UUID) { coordinator.present(.tripMode(id)) }
}

// MARK: - Builder

enum HomeBuilder {
    static func build(dependencies: AppDependencies) -> HomeView {
        let interactor = HomeInteractor(
            repository: dependencies.repository,
            weather: dependencies.weather,
            location: dependencies.location
        )
        let router = HomeRouter(coordinator: dependencies.coordinator)
        let presenter = HomePresenter(interactor: interactor, router: router)
        return HomeView(presenter: presenter)
    }
}
