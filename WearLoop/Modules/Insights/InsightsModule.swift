//
//  InsightsModule.swift
//  WearLoop
//
//  Statistics built only from real records. Where there is not enough history
//  the screen explains what is missing rather than drawing an empty chart.
//

import Combine
import SwiftUI

// MARK: - Contract

protocol InsightsInteractorProtocol: AnyObject {
    var repository: WardrobeRepositoryProtocol { get }
    func buildViewState(now: Date) -> InsightsViewState
    func metric(_ kind: InsightKind, now: Date) -> InsightMetric
    func relatedRecords(for row: InsightRow, kind: InsightKind) -> [RelatedRecordItem]
}

protocol InsightsRouterProtocol: ModuleRouterProtocol {
    func openDetail(_ kind: InsightKind)
    func openPiece(_ id: UUID)
    func openPlanner()
    func openAddPiece()
}

struct RelatedRecordItem: Identifiable, Equatable {
    var id: UUID
    var title: String
    var detail: String
    var dateText: String
}

struct InsightsViewState {
    var isUnlocked: Bool = false
    var lockMessage: String = ""
    var wearDayCount: Int = 0
    var requiredDays: Int = 10
    var metrics: [InsightMetric] = []
    var headlineMetrics: [InsightMetric] = []
    var hasPieces: Bool = false
    var showHalftone: Bool = true
    var summaryText: String = ""
}

// MARK: - Interactor

final class InsightsInteractor: InsightsInteractorProtocol {
    let repository: WardrobeRepositoryProtocol

    init(repository: WardrobeRepositoryProtocol) {
        self.repository = repository
    }

    func buildViewState(now: Date) -> InsightsViewState {
        let state = repository.state
        var view = InsightsViewState()
        view.showHalftone = state.appearance.showHalftoneMotif
        view.hasPieces = !state.pieces.isEmpty
        view.wearDayCount = state.wearRecordDayCount
        view.requiredDays = InsightsEngine.requiredWearDays
        view.isUnlocked = InsightsEngine.isUnlocked(state: state)
        view.lockMessage = InsightsEngine.lockMessage(state: state)
        view.metrics = InsightsEngine.metrics(state: state, now: now)

        // A few figures are useful even before the patterns unlock.
        view.headlineMetrics = view.metrics.filter {
            $0.kind == .wardrobeInRotation || $0.kind == .neverWorn || $0.kind == .repairBacklog
        }

        view.summaryText = view.isUnlocked
            ? "\(Plural.count(view.wearDayCount, "day")) of wear history"
            : "\(view.wearDayCount) of \(view.requiredDays) days recorded"

        return view
    }

    func metric(_ kind: InsightKind, now: Date) -> InsightMetric {
        InsightsEngine.metric(kind, state: repository.state, now: now)
    }

    func relatedRecords(for row: InsightRow, kind: InsightKind) -> [RelatedRecordItem] {
        let state = repository.state
        return InsightsEngine.relatedRecords(for: row, kind: kind, state: state)
            .prefix(40)
            .map { record in
                var detail = record.context.title
                if let tripID = record.tripID, let trip = state.trip(tripID) {
                    detail += " · \(trip.name)"
                } else if let eventID = record.eventID, let event = state.event(eventID) {
                    detail += " · \(event.name)"
                }
                if record.wasUnplanned { detail += " · changed from the plan" }
                return RelatedRecordItem(
                    id: record.id,
                    title: record.outfitName ?? Plural.count(record.pieceSnapshots.count, "piece"),
                    detail: detail,
                    dateText: DateFormatterCache.dayMonthYear.string(from: record.date)
                )
            }
    }
}

// MARK: - Presenter

final class InsightsPresenter: ObservableObject {
    @Published private(set) var viewState = InsightsViewState()

    private let interactor: InsightsInteractorProtocol
    private let router: InsightsRouterProtocol
    private var cancellables = Set<AnyCancellable>()

    init(interactor: InsightsInteractorProtocol, router: InsightsRouterProtocol) {
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
        viewState = interactor.buildViewState(now: Date())
    }

    func didTapMetric(_ kind: InsightKind) { router.openDetail(kind) }
    func didTapPlanner() { router.openPlanner() }
    func didTapAddPiece() { router.openAddPiece() }
}

// MARK: - Detail presenter

final class InsightDetailPresenter: ObservableObject {
    @Published private(set) var metric: InsightMetric?
    @Published var expandedRow: InsightRow?
    @Published private(set) var relatedRecords: [RelatedRecordItem] = []

    let kind: InsightKind

    private let interactor: InsightsInteractorProtocol
    private let router: InsightsRouterProtocol
    private var cancellables = Set<AnyCancellable>()

    init(interactor: InsightsInteractorProtocol, router: InsightsRouterProtocol, kind: InsightKind) {
        self.interactor = interactor
        self.router = router
        self.kind = kind
    }

    func onAppear() { refresh() }

    private func refresh() {
        metric = interactor.metric(kind, now: Date())
        if let expandedRow {
            relatedRecords = interactor.relatedRecords(for: expandedRow, kind: kind)
        }
    }

    func didTapRow(_ row: InsightRow) {
        if expandedRow?.id == row.id {
            expandedRow = nil
            relatedRecords = []
        } else {
            expandedRow = row
            relatedRecords = interactor.relatedRecords(for: row, kind: kind)
        }
    }

    func didTapPiece(_ id: UUID) { router.openPiece(id) }
}

// MARK: - Router

final class InsightsRouter: InsightsRouterProtocol {
    let coordinator: NavigationCoordinator

    init(coordinator: NavigationCoordinator) {
        self.coordinator = coordinator
    }

    func openDetail(_ kind: InsightKind) { coordinator.push(.insightDetail(kind)) }
    func openPiece(_ id: UUID) { coordinator.jump(to: .wardrobe, then: .pieceDetails(id)) }
    func openPlanner() { coordinator.jump(to: .home, then: .planner) }
    func openAddPiece() { coordinator.jump(to: .wardrobe, then: .pieceForm(pieceID: nil)) }
}

// MARK: - Builders

enum InsightsBuilder {
    static func build(dependencies: AppDependencies) -> InsightsView {
        let interactor = InsightsInteractor(repository: dependencies.repository)
        let router = InsightsRouter(coordinator: dependencies.coordinator)
        let presenter = InsightsPresenter(interactor: interactor, router: router)
        return InsightsView(presenter: presenter)
    }
}

enum InsightDetailBuilder {
    static func build(dependencies: AppDependencies, kind: InsightKind) -> InsightDetailView {
        let interactor = InsightsInteractor(repository: dependencies.repository)
        let router = InsightsRouter(coordinator: dependencies.coordinator)
        let presenter = InsightDetailPresenter(interactor: interactor, router: router, kind: kind)
        return InsightDetailView(presenter: presenter)
    }
}
