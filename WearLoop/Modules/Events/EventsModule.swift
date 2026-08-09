//
//  EventsModule.swift
//  WearLoop
//
//  One-off events outside a trip: a wedding, an interview, a shoot. The app
//  checks the outfit against the dress code and remembers what was worn before.
//

import Combine
import SwiftUI

// MARK: - Contract

enum EventsSection: String, CaseIterable, Identifiable, Hashable {
    case upcoming
    case past
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .upcoming: return "Upcoming"
        case .past: return "Past"
        case .all: return "All Events"
        }
    }
}

struct EventListItem: Identifiable, Equatable {
    var id: UUID
    var name: String
    var dateText: String
    var relativeText: String
    var dressCode: DressCode
    var outfitName: String?
    var outfitPieces: [Piece]
    var hasOutfit: Bool
    var isWorn: Bool
    var isPast: Bool
    var warning: String?
}

struct EventsViewState {
    var items: [EventListItem] = []
    var sectionCounts: [EventsSection: Int] = [:]
    var totalEvents: Int = 0
    var hasOutfits: Bool = false
    var summaryText: String = ""
    var showHalftone: Bool = true
}

protocol EventsInteractorProtocol: AnyObject {
    var repository: WardrobeRepositoryProtocol { get }
    func buildViewState(section: EventsSection, now: Date) -> EventsViewState
    func delete(_ id: UUID)
}

protocol EventsRouterProtocol: ModuleRouterProtocol {
    func openEvent(_ id: UUID?)
    func openBuildOutfit()
}

// MARK: - Interactor

final class EventsInteractor: EventsInteractorProtocol {
    let repository: WardrobeRepositoryProtocol

    init(repository: WardrobeRepositoryProtocol) {
        self.repository = repository
    }

    func buildViewState(section: EventsSection, now: Date) -> EventsViewState {
        let state = repository.state
        var view = EventsViewState()
        view.showHalftone = state.appearance.showHalftoneMotif
        view.totalEvents = state.events.count
        view.hasOutfits = !state.activeOutfits.isEmpty

        let all = state.events
            .sorted { $0.date > $1.date }
            .map { event -> EventListItem in
                let outfit = event.outfitID.flatMap { state.outfit($0) }
                var warning: String?

                if let outfit {
                    if let required = event.dressCode.expectedFormality,
                       let mismatch = AvailabilityEngine.formalityMismatch(
                        outfit: outfit,
                        required: required,
                        requiredLabel: "event"
                       ) {
                        warning = mismatch
                    }
                    let check = AvailabilityEngine.check(outfit: outfit, state: state, referenceDate: event.date)
                    if !check.isAvailable {
                        let text = check.earliestReturn.map {
                            "\(Plural.count(check.unavailablePieceIDs.count, "piece")) unavailable until \(DateFormatterCache.relativeDayText($0, now: now))."
                        } ?? "\(Plural.count(check.unavailablePieceIDs.count, "piece")) unavailable."
                        warning = warning.map { "\($0) \(text)" } ?? text
                    }
                    if let weather = event.weather,
                       let mismatch = AvailabilityEngine.weatherMismatch(
                        outfit: outfit,
                        weather: weather,
                        units: state.profile.units,
                        dayLabel: "This event"
                       ) {
                        warning = warning.map { "\($0) \(mismatch)" } ?? mismatch
                    }
                }

                return EventListItem(
                    id: event.id,
                    name: event.name,
                    dateText: DateFormatterCache.dayMonthYear.string(from: event.date),
                    relativeText: DateFormatterCache.relativeDayText(event.date, now: now).capitalizedFirst,
                    dressCode: event.dressCode,
                    outfitName: outfit?.name,
                    outfitPieces: outfit?.items.compactMap { state.piece($0.pieceID) } ?? [],
                    hasOutfit: event.outfitID != nil,
                    isWorn: event.isWorn,
                    isPast: event.isPast,
                    warning: warning
                )
            }

        view.sectionCounts[.all] = all.count
        view.sectionCounts[.upcoming] = all.filter { !$0.isPast && !$0.isWorn }.count
        view.sectionCounts[.past] = all.filter { $0.isPast || $0.isWorn }.count

        switch section {
        case .all: view.items = all
        case .upcoming: view.items = all.filter { !$0.isPast && !$0.isWorn }.sorted { $0.dateText < $1.dateText }
        case .past: view.items = all.filter { $0.isPast || $0.isWorn }
        }

        // Upcoming reads better oldest first.
        if section == .upcoming {
            let ids = view.items.map(\.id)
            view.items = state.events
                .filter { ids.contains($0.id) }
                .sorted { $0.date < $1.date }
                .compactMap { event in view.items.first { $0.id == event.id } }
        }

        view.summaryText = Plural.count(view.items.count, "event")
        return view
    }

    func delete(_ id: UUID) {
        repository.mutate { state in
            WardrobeActions.deleteEvent(id, in: &state)
        }
    }
}

// MARK: - Presenter

final class EventsPresenter: ObservableObject {
    @Published private(set) var viewState = EventsViewState()
    @Published var section: EventsSection = .upcoming { didSet { refresh() } }
    @Published var toast: ToastMessage?
    @Published var confirm: ConfirmRequest?

    private let interactor: EventsInteractorProtocol
    private let router: EventsRouterProtocol
    private var cancellables = Set<AnyCancellable>()

    init(interactor: EventsInteractorProtocol, router: EventsRouterProtocol) {
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
        viewState = interactor.buildViewState(section: section, now: Date())
    }

    func segmentItems() -> [SegmentItem<EventsSection>] {
        EventsSection.allCases.map {
            SegmentItem(value: $0, title: $0.title, badge: $0 == .all ? nil : viewState.sectionCounts[$0])
        }
    }

    func didTapCreate() { router.openEvent(nil) }
    func didTapEvent(_ id: UUID) { router.openEvent(id) }
    func didTapBuildOutfit() { router.openBuildOutfit() }

    func didTapDelete(_ item: EventListItem) {
        confirm = ConfirmRequest(
            title: "Delete \(item.name)?",
            message: item.isWorn
                ? "The event is removed. The wear record made for it stays, because it describes what you actually wore."
                : "The event and its outfit assignment are removed.",
            confirmTitle: "Delete Event",
            cancelTitle: "Keep",
            isDestructive: true,
            onConfirm: { [weak self] in
                self?.interactor.delete(item.id)
                self?.toast = ToastMessage(text: "Event deleted", kind: .info)
            }
        )
    }
}

// MARK: - Router

final class EventsRouter: EventsRouterProtocol {
    let coordinator: NavigationCoordinator

    init(coordinator: NavigationCoordinator) {
        self.coordinator = coordinator
    }

    func openEvent(_ id: UUID?) { coordinator.push(.eventForm(eventID: id)) }
    func openBuildOutfit() { coordinator.jump(to: .outfits, then: .outfitBuilder(outfitID: nil, prefillPieceID: nil)) }
}

// MARK: - Builder

enum EventsBuilder {
    static func build(dependencies: AppDependencies) -> EventsView {
        let interactor = EventsInteractor(repository: dependencies.repository)
        let router = EventsRouter(coordinator: dependencies.coordinator)
        let presenter = EventsPresenter(interactor: interactor, router: router)
        return EventsView(presenter: presenter)
    }
}
