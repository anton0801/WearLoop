//
//  TripsModule.swift
//  WearLoop
//
//  The trips list. Each trip is a project with its own days, outfits and bag.
//

import Combine
import SwiftUI

// MARK: - Contract

enum TripsSection: String, CaseIterable, Identifiable, Hashable {
    case all
    case upcoming
    case inProgress
    case completed
    case drafts
    case templates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "My Trips"
        case .upcoming: return "Upcoming"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .drafts: return "Drafts"
        case .templates: return "Templates"
        }
    }
}

struct TripListItem: Identifiable, Equatable {
    var id: UUID
    var name: String
    var destination: String
    var dateText: String
    var dayCount: Int
    var stage: TripStage
    var phase: TripPhase
    var isDraft: Bool
    var readinessPassed: Int
    var readinessTotal: Int
    var weightText: String?
    var isOverWeight: Bool
    var statusLine: String
}

struct TripsViewState {
    var items: [TripListItem] = []
    var sectionCounts: [TripsSection: Int] = [:]
    var templates: [PackingTemplate] = []
    var totalTrips: Int = 0
    var hasOutfits: Bool = false
    var summaryText: String = ""
    var showHalftone: Bool = true
}

protocol TripsInteractorProtocol: AnyObject {
    var repository: WardrobeRepositoryProtocol { get }
    func buildViewState(section: TripsSection, now: Date) -> TripsViewState
    func deleteTrip(_ id: UUID)
    func deleteTemplate(_ id: UUID)
}

protocol TripsRouterProtocol: ModuleRouterProtocol {
    func openWizard(tripID: UUID?)
    func openWorkspace(_ id: UUID)
    func openTripMode(_ id: UUID)
    func openRecap(_ id: UUID)
    func openTemplates()
    func openBuildOutfit()
}

// MARK: - Interactor

final class TripsInteractor: TripsInteractorProtocol {
    let repository: WardrobeRepositoryProtocol

    init(repository: WardrobeRepositoryProtocol) {
        self.repository = repository
    }

    func buildViewState(section: TripsSection, now: Date) -> TripsViewState {
        let state = repository.state
        var view = TripsViewState()
        view.showHalftone = state.appearance.showHalftoneMotif
        view.totalTrips = state.trips.count
        view.hasOutfits = !state.activeOutfits.isEmpty
        view.templates = state.templates.sorted { $0.createdAt > $1.createdAt }

        let all = state.trips.map { trip -> TripListItem in
            let readiness = TripReadinessEngine.readiness(trip: trip, state: state, now: now)
            let estimate = LuggageEngine.estimate(trip: trip, state: state)
            return TripListItem(
                id: trip.id,
                name: trip.name.wlIsBlank ? "Untitled trip" : trip.name,
                destination: trip.destination,
                dateText: trip.dateRangeText,
                dayCount: trip.dayCount,
                stage: trip.stage,
                phase: trip.phase,
                isDraft: trip.isDraft,
                readinessPassed: readiness.passedCount,
                readinessTotal: readiness.totalCount,
                weightText: trip.activePacking.isEmpty
                    ? nil
                    : UnitFormatter.bagWeight(grams: estimate.totalGrams, units: state.profile.units),
                isOverWeight: estimate.isOverLimit,
                statusLine: statusLine(trip: trip, readiness: readiness, now: now)
            )
        }

        view.sectionCounts[.all] = all.filter { !$0.isDraft }.count
        view.sectionCounts[.upcoming] = all.filter { !$0.isDraft && $0.phase == .upcoming }.count
        view.sectionCounts[.inProgress] = all.filter { $0.phase == .inProgress }.count
        view.sectionCounts[.completed] = all.filter { $0.phase == .completed }.count
        view.sectionCounts[.drafts] = all.filter { $0.isDraft }.count
        view.sectionCounts[.templates] = state.templates.count

        switch section {
        case .all:
            view.items = all.filter { !$0.isDraft }
        case .upcoming:
            view.items = all.filter { !$0.isDraft && $0.phase == .upcoming }
        case .inProgress:
            view.items = all.filter { $0.phase == .inProgress }
        case .completed:
            view.items = all.filter { $0.phase == .completed }
        case .drafts:
            view.items = all.filter { $0.isDraft }
        case .templates:
            view.items = []
        }

        // Trips in progress first, then by start date.
        view.items.sort { a, b in
            if a.phase != b.phase {
                return phaseOrder(a.phase) < phaseOrder(b.phase)
            }
            return a.dateText < b.dateText
        }

        view.summaryText = section == .templates
            ? Plural.count(state.templates.count, "template")
            : Plural.count(view.items.count, "trip")

        return view
    }

    private func phaseOrder(_ phase: TripPhase) -> Int {
        switch phase {
        case .inProgress: return 0
        case .upcoming: return 1
        case .completed: return 2
        }
    }

    private func statusLine(trip: Trip, readiness: TripReadiness, now: Date) -> String {
        if trip.isDraft {
            return "Draft · step \(trip.draftStep) of 5"
        }
        switch trip.phase {
        case .inProgress:
            if let day = trip.currentDay(now: now) {
                return "Day \(day.dayNumber) of \(trip.dayCount)"
            }
            return "In progress"
        case .completed:
            if let recap = trip.recap {
                return "Packed \(recap.packedCount), wore \(recap.wornCount)"
            }
            return "Completed"
        case .upcoming:
            let days = Calendar.wl.dayCount(from: now, to: trip.startDate)
            let when = days <= 0 ? "starting now" : "in \(Plural.count(days, "day"))"
            return "\(readiness.passedCount) of \(readiness.totalCount) checks · \(when)"
        }
    }

    func deleteTrip(_ id: UUID) {
        repository.mutate { state in
            WardrobeActions.deleteTrip(id, in: &state)
        }
    }

    func deleteTemplate(_ id: UUID) {
        repository.mutate { state in
            state.templates.removeAll { $0.id == id }
        }
    }
}

// MARK: - Presenter

final class TripsPresenter: ObservableObject {
    @Published private(set) var viewState = TripsViewState()
    @Published var section: TripsSection = .all { didSet { refresh() } }
    @Published var toast: ToastMessage?
    @Published var confirm: ConfirmRequest?

    private let interactor: TripsInteractorProtocol
    private let router: TripsRouterProtocol
    private var cancellables = Set<AnyCancellable>()

    init(interactor: TripsInteractorProtocol, router: TripsRouterProtocol) {
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

    func segmentItems() -> [SegmentItem<TripsSection>] {
        TripsSection.allCases.map {
            SegmentItem(value: $0, title: $0.title, badge: $0 == .all ? nil : viewState.sectionCounts[$0])
        }
    }

    func didTapCreate() { router.openWizard(tripID: nil) }
    func didTapTemplates() { router.openTemplates() }
    func didTapBuildOutfit() { router.openBuildOutfit() }

    func didTapTrip(_ item: TripListItem) {
        if item.isDraft {
            router.openWizard(tripID: item.id)
        } else if item.phase == .inProgress {
            router.openTripMode(item.id)
        } else if item.phase == .completed {
            router.openRecap(item.id)
        } else {
            router.openWorkspace(item.id)
        }
    }

    func didTapOpenWorkspace(_ id: UUID) { router.openWorkspace(id) }

    func didTapDelete(_ item: TripListItem) {
        confirm = ConfirmRequest(
            title: "Delete \(item.name)?",
            message: item.phase == .completed
                ? "The trip and its recap are removed. Wear records made during it stay, because they describe what actually happened."
                : "The trip, its day plan and its packing list are removed. Your wardrobe is not touched.",
            confirmTitle: "Delete Trip",
            cancelTitle: "Keep Trip",
            isDestructive: true,
            onConfirm: { [weak self] in
                self?.interactor.deleteTrip(item.id)
                self?.toast = ToastMessage(text: "Trip deleted", kind: .info)
            }
        )
    }

    func didTapDeleteTemplate(_ template: PackingTemplate) {
        confirm = ConfirmRequest(
            title: "Delete \(template.name)?",
            message: "The template is removed. Trips already built from it are unaffected.",
            confirmTitle: "Delete Template",
            cancelTitle: "Keep",
            isDestructive: true,
            onConfirm: { [weak self] in
                self?.interactor.deleteTemplate(template.id)
                self?.toast = ToastMessage(text: "Template deleted", kind: .info)
            }
        )
    }
}

// MARK: - Router

final class TripsRouter: TripsRouterProtocol {
    let coordinator: NavigationCoordinator

    init(coordinator: NavigationCoordinator) {
        self.coordinator = coordinator
    }

    func openWizard(tripID: UUID?) { coordinator.push(.tripWizard(tripID: tripID)) }
    func openWorkspace(_ id: UUID) { coordinator.push(.tripWorkspace(id)) }
    func openTripMode(_ id: UUID) { coordinator.present(.tripMode(id)) }
    func openRecap(_ id: UUID) { coordinator.push(.tripRecap(id)) }
    func openTemplates() { coordinator.push(.templates) }
    func openBuildOutfit() { coordinator.jump(to: .outfits, then: .outfitBuilder(outfitID: nil, prefillPieceID: nil)) }
}

// MARK: - Builder

enum TripsBuilder {
    static func build(dependencies: AppDependencies) -> TripsView {
        let interactor = TripsInteractor(repository: dependencies.repository)
        let router = TripsRouter(coordinator: dependencies.coordinator)
        let presenter = TripsPresenter(interactor: interactor, router: router)
        return TripsView(presenter: presenter)
    }
}
