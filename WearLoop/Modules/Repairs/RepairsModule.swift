//
//  RepairsModule.swift
//  WearLoop
//
//  Pieces waiting to be mended. After sixty days the app suggests retiring a
//  piece — it never does it on its own.
//

import Combine
import SwiftUI

// MARK: - Contract

enum RepairsSection: String, CaseIterable, Identifiable, Hashable {
    case open
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open: return "Repair List"
        case .completed: return "Completed"
        }
    }
}

struct RepairRow: Identifiable, Equatable {
    var id: UUID
    var pieceID: UUID
    var name: String
    var issue: String
    var plannedAction: String
    var reportedText: String
    var daysOpen: Int
    var costText: String?
    var completedText: String?
    var piece: Piece?
    var suggestsRetiring: Bool
    var usedInOutfits: Int
}

struct RepairsViewState {
    var rows: [RepairRow] = []
    var sectionCounts: [RepairsSection: Int] = [:]
    var totalOpen: Int = 0
    var oldestDays: Int = 0
    var totalCostText: String?
    var summaryText: String = ""
    var showHalftone: Bool = true
    var repairablePieces: [Piece] = []
}

protocol RepairsInteractorProtocol: AnyObject {
    var repository: WardrobeRepositoryProtocol { get }
    func buildViewState(section: RepairsSection, now: Date) -> RepairsViewState
    func addIssue(pieceID: UUID, issue: String, plannedAction: String)
    func complete(_ id: UUID, cost: Double?)
    func retire(pieceID: UUID)
    func deleteIssue(_ id: UUID)
    func updateIssue(_ id: UUID, issue: String, plannedAction: String)
}

protocol RepairsRouterProtocol: ModuleRouterProtocol {
    func openPiece(_ id: UUID)
}

// MARK: - Interactor

final class RepairsInteractor: RepairsInteractorProtocol {
    let repository: WardrobeRepositoryProtocol

    /// The app suggests retiring after this long, but never acts by itself.
    private let retireSuggestionDays = 60

    init(repository: WardrobeRepositoryProtocol) {
        self.repository = repository
    }

    func buildViewState(section: RepairsSection, now: Date) -> RepairsViewState {
        let state = repository.state
        var view = RepairsViewState()
        view.showHalftone = state.appearance.showHalftoneMotif

        let all = state.repairs
            .sorted { $0.reportedOn < $1.reportedOn }
            .map { repair -> RepairRow in
                let piece = state.piece(repair.pieceID)
                let days = repair.daysOpen(now: now)
                return RepairRow(
                    id: repair.id,
                    pieceID: repair.pieceID,
                    name: piece?.name ?? repair.snapshot.name,
                    issue: repair.issue,
                    plannedAction: repair.plannedAction,
                    reportedText: DateFormatterCache.dayMonthYear.string(from: repair.reportedOn),
                    daysOpen: days,
                    costText: repair.cost.map { UnitFormatter.money($0) },
                    completedText: repair.completedOn.map { DateFormatterCache.dayMonthYear.string(from: $0) },
                    piece: piece,
                    suggestsRetiring: repair.isOpen && days >= retireSuggestionDays,
                    usedInOutfits: state.outfits(containing: repair.pieceID).count
                )
            }

        view.sectionCounts[.open] = all.filter { $0.completedText == nil }.count
        view.sectionCounts[.completed] = all.filter { $0.completedText != nil }.count

        switch section {
        case .open:
            view.rows = all.filter { $0.completedText == nil }
        case .completed:
            view.rows = all.filter { $0.completedText != nil }.reversed()
        }

        view.totalOpen = view.sectionCounts[.open] ?? 0
        view.oldestDays = all.filter { $0.completedText == nil }.map(\.daysOpen).max() ?? 0

        let totalCost = state.repairs.compactMap(\.cost).reduce(0, +)
        if totalCost > 0 {
            view.totalCostText = UnitFormatter.money(totalCost)
        }

        // Pieces that could have an issue reported against them.
        let openPieceIDs = Set(state.openRepairs.map(\.pieceID))
        view.repairablePieces = state.pieces
            .filter { $0.status != .archived && !openPieceIDs.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        view.summaryText = view.totalOpen == 0
            ? "Nothing waiting to be repaired"
            : "\(Plural.count(view.totalOpen, "piece")) waiting"

        return view
    }

    func addIssue(pieceID: UUID, issue: String, plannedAction: String) {
        repository.mutate { state in
            WardrobeActions.reportRepair(
                pieceID: pieceID,
                issue: issue,
                plannedAction: plannedAction,
                in: &state
            )
        }
    }

    func complete(_ id: UUID, cost: Double?) {
        repository.mutate { state in
            WardrobeActions.completeRepair(id, cost: cost, in: &state)
        }
    }

    func retire(pieceID: UUID) {
        repository.mutate { state in
            WardrobeActions.retirePiece(pieceID, in: &state)
        }
    }

    func deleteIssue(_ id: UUID) {
        repository.mutate { state in
            guard let repair = state.repairs.first(where: { $0.id == id }) else { return }
            let pieceID = repair.pieceID
            state.repairs.removeAll { $0.id == id }
            // Without an open issue the piece should not stay marked as broken.
            let stillOpen = state.repairs.contains { $0.pieceID == pieceID && $0.isOpen }
            if !stillOpen,
               let index = state.pieces.firstIndex(where: { $0.id == pieceID }),
               state.pieces[index].status == .needsRepair {
                WardrobeActions.setStatus(.inRotation, pieceID: pieceID, in: &state)
            }
        }
    }

    func updateIssue(_ id: UUID, issue: String, plannedAction: String) {
        repository.mutate { state in
            guard let index = state.repairs.firstIndex(where: { $0.id == id }) else { return }
            state.repairs[index].issue = issue.wlTrimmed
            state.repairs[index].plannedAction = plannedAction.wlTrimmed
        }
    }
}

// MARK: - Presenter

final class RepairsPresenter: ObservableObject {
    @Published private(set) var viewState = RepairsViewState()
    @Published var section: RepairsSection = .open { didSet { refresh() } }
    @Published var isAddPresented = false
    @Published var completingRow: RepairRow?
    @Published var editingRow: RepairRow?
    @Published var toast: ToastMessage?
    @Published var confirm: ConfirmRequest?
    /// Retire suggestions the user has waved away for now.
    @Published private(set) var dismissedRetireSuggestions: Set<UUID> = []

    private let interactor: RepairsInteractorProtocol
    private let router: RepairsRouterProtocol
    private var cancellables = Set<AnyCancellable>()

    init(interactor: RepairsInteractorProtocol, router: RepairsRouterProtocol) {
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

    func segmentItems() -> [SegmentItem<RepairsSection>] {
        RepairsSection.allCases.map {
            SegmentItem(value: $0, title: $0.title, badge: viewState.sectionCounts[$0])
        }
    }

    func didTapAdd() { isAddPresented = true }
    func didTapPiece(_ id: UUID) { router.openPiece(id) }
    func didTapComplete(_ row: RepairRow) { completingRow = row }
    func didTapEdit(_ row: RepairRow) { editingRow = row }

    func didAddIssue(pieceID: UUID, issue: String, plannedAction: String) {
        interactor.addIssue(pieceID: pieceID, issue: issue, plannedAction: plannedAction)
        isAddPresented = false
        toast = ToastMessage(text: "Added to the repair list", kind: .success)
    }

    func didCompleteRepair(_ id: UUID, cost: Double?) {
        interactor.complete(id, cost: cost)
        completingRow = nil
        toast = ToastMessage(text: "Marked as repaired and back in rotation", kind: .success)
    }

    func didUpdateIssue(_ id: UUID, issue: String, plannedAction: String) {
        interactor.updateIssue(id, issue: issue, plannedAction: plannedAction)
        editingRow = nil
        toast = ToastMessage(text: "Issue updated", kind: .success)
    }

    func didTapKeepWaiting(_ row: RepairRow) {
        dismissedRetireSuggestions.insert(row.id)
        toast = ToastMessage(text: "Kept on the repair list", kind: .info)
    }

    func showsRetireSuggestion(_ row: RepairRow) -> Bool {
        row.suggestsRetiring && !dismissedRetireSuggestions.contains(row.id)
    }

    func didTapRetire(_ row: RepairRow) {
        confirm = ConfirmRequest(
            title: "Retire \(row.name)?",
            message: row.usedInOutfits > 0
                ? "It is archived and removed from \(Plural.count(row.usedInOutfits, "outfit")) and every future plan. Its history and statistics are kept."
                : "It is archived and removed from every future plan. Its history and statistics are kept.",
            confirmTitle: "Retire Piece",
            cancelTitle: "Keep It",
            isDestructive: true,
            onConfirm: { [weak self] in
                self?.interactor.retire(pieceID: row.pieceID)
                self?.toast = ToastMessage(text: "\(row.name) retired", kind: .info)
            }
        )
    }

    func didTapDelete(_ row: RepairRow) {
        confirm = ConfirmRequest(
            title: "Remove This Issue?",
            message: "The issue is deleted and the piece goes back into rotation if nothing else is holding it back.",
            confirmTitle: "Remove Issue",
            cancelTitle: "Keep",
            isDestructive: true,
            onConfirm: { [weak self] in
                self?.interactor.deleteIssue(row.id)
                self?.toast = ToastMessage(text: "Issue removed", kind: .info)
            }
        )
    }
}

// MARK: - Router

final class RepairsRouter: RepairsRouterProtocol {
    let coordinator: NavigationCoordinator

    init(coordinator: NavigationCoordinator) {
        self.coordinator = coordinator
    }

    func openPiece(_ id: UUID) { coordinator.jump(to: .wardrobe, then: .pieceDetails(id)) }
}

// MARK: - Builder

enum RepairsBuilder {
    static func build(dependencies: AppDependencies) -> RepairsView {
        let interactor = RepairsInteractor(repository: dependencies.repository)
        let router = RepairsRouter(coordinator: dependencies.coordinator)
        let presenter = RepairsPresenter(interactor: interactor, router: router)
        return RepairsView(presenter: presenter)
    }
}
