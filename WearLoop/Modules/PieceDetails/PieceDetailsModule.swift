//
//  PieceDetailsModule.swift
//  WearLoop
//
//  Everything known about one garment, and every action in its life cycle.
//

import Combine
import SwiftUI

// MARK: - Contract

protocol PieceDetailsInteractorProtocol: AnyObject {
    var repository: WardrobeRepositoryProtocol { get }
    func buildViewState(pieceID: UUID, now: Date) -> PieceDetailsViewState?
    func markWorn(pieceID: UUID, date: Date, sendToWash: Bool)
    func sendToWash(pieceID: UUID)
    func returnFromWash(pieceID: UUID)
    func reportRepair(pieceID: UUID, issue: String, plannedAction: String)
    func setStatus(_ status: PieceStatus, pieceID: UUID)
    func delete(pieceID: UUID)
}

protocol PieceDetailsRouterProtocol: ModuleRouterProtocol {
    func openEdit(_ id: UUID)
    func openOutfit(_ id: UUID)
    func openBuildOutfit(withPiece id: UUID)
    func openRepairs()
    func openLaundry()
    func closeAfterDelete()
}

/// A row in the wear or laundry history.
struct HistoryEntry: Identifiable, Hashable {
    var id: UUID
    var title: String
    var detail: String
    var dateText: String
    var accent: Color
}

struct PieceDetailsViewState {
    var piece: Piece
    var timesWorn: Int = 0
    var lastWornText: String = "Never worn"
    var costPerWearText: String?
    var priceText: String?
    var weightText: String = ""
    var isWeightEstimated: Bool = true
    var statusDetail: String = ""

    var outfits: [Outfit] = []
    var outfitPieces: [UUID: [Piece]] = [:]
    var wearHistory: [HistoryEntry] = []
    var laundryHistory: [HistoryEntry] = []
    var openRepair: RepairIssue?
    var upcomingTripNames: [String] = []

    /// Wear calendar of the last five weeks.
    var calendarDays: [WearCalendarDay] = []

    var units: MeasurementUnits = .metric
    var showHalftone: Bool = true

    /// The exact consequence sentence for the delete confirmation.
    var deleteImpactText: String = ""
}

// MARK: - Interactor

final class PieceDetailsInteractor: PieceDetailsInteractorProtocol {
    let repository: WardrobeRepositoryProtocol

    init(repository: WardrobeRepositoryProtocol) {
        self.repository = repository
    }

    func buildViewState(pieceID: UUID, now: Date) -> PieceDetailsViewState? {
        let state = repository.state
        guard let piece = state.piece(pieceID) else { return nil }

        var view = PieceDetailsViewState(piece: piece)
        view.units = state.profile.units
        view.showHalftone = state.appearance.showHalftoneMotif

        view.timesWorn = state.wearCount(forPiece: pieceID)
        if let last = state.lastWorn(pieceID: pieceID) {
            view.lastWornText = "\(DateFormatterCache.dayMonthYear.string(from: last)) · \(Plural.count(Calendar.wl.dayCount(from: last, to: now), "day")) ago"
        }
        if let price = piece.purchasePrice {
            view.priceText = UnitFormatter.money(price)
        }
        if let cost = state.costPerWear(pieceID: pieceID) {
            view.costPerWearText = UnitFormatter.money(cost)
        }

        let weight = piece.estimatedWeight(categoryWeights: state.categoryWeights)
        view.isWeightEstimated = weight.isEstimate
        view.weightText = UnitFormatter.weight(grams: weight.grams, units: state.profile.units)
            + (weight.isEstimate ? " (category average)" : "")

        // Status detail
        switch piece.status {
        case .inWash:
            if let back = piece.expectedBackDate {
                let overdue = back.wlStartOfDay < now.wlStartOfDay
                view.statusDetail = overdue
                    ? "Due back \(DateFormatterCache.relativeDayText(back, now: now)) — overdue"
                    : "Expected back \(DateFormatterCache.relativeDayText(back, now: now))"
            } else {
                view.statusDetail = "In the wash"
            }
            if let load = state.laundryLoad(containing: pieceID) {
                view.statusDetail += " · \(load.name)"
            }
        case .needsRepair:
            view.statusDetail = state.openRepair(forPiece: pieceID)?.issue ?? "Waiting for repair"
        case .storedAway:
            view.statusDetail = piece.storagePlace.wlIsBlank ? "Stored away" : "Stored in \(piece.storagePlace)"
        case .archived:
            view.statusDetail = "Archived, kept only for history"
        case .inRotation:
            view.statusDetail = "Ready to wear"
        }

        // Outfits using the piece
        view.outfits = state.outfits(containing: pieceID)
        for outfit in view.outfits {
            view.outfitPieces[outfit.id] = outfit.items.compactMap { state.piece($0.pieceID) }
        }

        // Histories
        view.wearHistory = state.wearRecords(forPiece: pieceID).prefix(20).map { record in
            HistoryEntry(
                id: record.id,
                title: record.outfitName ?? "Worn on its own",
                detail: record.context.title + (record.wasUnplanned ? " · changed from the plan" : ""),
                dateText: DateFormatterCache.dayMonthYear.string(from: record.date),
                accent: Palette.amber
            )
        }

        view.laundryHistory = state.laundryRecords(forPiece: pieceID).prefix(20).map { record in
            let detail: String
            if let returned = record.returnedAt {
                detail = "Returned \(DateFormatterCache.dayMonth.string(from: returned))"
            } else {
                detail = "Still in the wash"
            }
            return HistoryEntry(
                id: record.id,
                title: record.loadName,
                detail: record.temperatureC.map { "\(detail) · \($0) °C" } ?? detail,
                dateText: DateFormatterCache.dayMonthYear.string(from: record.sentAt),
                accent: Palette.berry
            )
        }

        view.openRepair = state.openRepair(forPiece: pieceID)
        view.upcomingTripNames = state.upcomingTrips(using: pieceID).map(\.name)

        // Calendar of the last five weeks
        let start = Calendar.wl.addingDays(-34, to: now.wlStartOfDay)
        let wornDays = Set(state.wearRecords(forPiece: pieceID).map { $0.date.wlStartOfDay })
        let plannedDays = Set(
            state.dayPlans
                .filter { plan in
                    guard let outfitID = plan.outfitID, let outfit = state.outfit(outfitID) else { return false }
                    return outfit.contains(pieceID: pieceID) && !plan.isWorn
                }
                .map { $0.date.wlStartOfDay }
        )
        view.calendarDays = start.wlDays(through: Calendar.wl.addingDays(7, to: now)).map { day in
            WearCalendarDay(
                date: day,
                isWorn: wornDays.contains(day),
                isPlanned: plannedDays.contains(day),
                isToday: Calendar.wl.isSameDay(day, now)
            )
        }

        // Delete impact
        var impacts: [String] = []
        if !view.outfits.isEmpty {
            impacts.append(Plural.count(view.outfits.count, "outfit"))
        }
        if !view.upcomingTripNames.isEmpty {
            impacts.append(Plural.count(view.upcomingTripNames.count, "upcoming trip"))
        }
        if impacts.isEmpty {
            view.deleteImpactText = "This piece is not used anywhere. Its wear history will be kept as a record."
        } else {
            view.deleteImpactText = "This piece is used in \(impacts.joined(separator: " and ")). Deleting it will remove it from them. Past wear records keep their own copy of the name and photo."
        }

        return view
    }

    func markWorn(pieceID: UUID, date: Date, sendToWash: Bool) {
        repository.mutate { state in
            WardrobeActions.recordWear(
                outfitID: nil,
                pieceIDs: [pieceID],
                date: date,
                context: .day,
                in: &state
            )
            if sendToWash {
                WardrobeActions.sendToWash(pieceIDs: [pieceID], in: &state)
            }
        }
    }

    func sendToWash(pieceID: UUID) {
        repository.mutate { state in
            WardrobeActions.sendToWash(pieceIDs: [pieceID], in: &state)
        }
    }

    func returnFromWash(pieceID: UUID) {
        repository.mutate { state in
            WardrobeActions.returnFromWash(pieceIDs: [pieceID], in: &state)
        }
    }

    func reportRepair(pieceID: UUID, issue: String, plannedAction: String) {
        repository.mutate { state in
            WardrobeActions.reportRepair(
                pieceID: pieceID,
                issue: issue,
                plannedAction: plannedAction,
                in: &state
            )
        }
    }

    func setStatus(_ status: PieceStatus, pieceID: UUID) {
        repository.mutate { state in
            WardrobeActions.setStatus(status, pieceID: pieceID, in: &state)
        }
    }

    func delete(pieceID: UUID) {
        repository.mutate { state in
            WardrobeActions.deletePiece(pieceID, in: &state)
        }
    }
}

// MARK: - Presenter

final class PieceDetailsPresenter: ObservableObject {
    @Published private(set) var viewState: PieceDetailsViewState?
    /// Set when the piece has gone, so the screen explains itself before closing.
    @Published private(set) var isMissing = false
    @Published var toast: ToastMessage?
    @Published var confirm: ConfirmRequest?
    @Published var isMarkWornPresented = false
    @Published var isRepairSheetPresented = false

    private let interactor: PieceDetailsInteractorProtocol
    private let router: PieceDetailsRouterProtocol
    private let pieceID: UUID
    private var cancellables = Set<AnyCancellable>()
    private var isDeleting = false

    init(interactor: PieceDetailsInteractorProtocol, router: PieceDetailsRouterProtocol, pieceID: UUID) {
        self.interactor = interactor
        self.router = router
        self.pieceID = pieceID
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
        guard !isDeleting else { return }
        let built = interactor.buildViewState(pieceID: pieceID, now: Date())
        viewState = built
        isMissing = built == nil
    }

    // MARK: Intents

    func didTapEdit() { router.openEdit(pieceID) }
    func didTapOutfit(_ id: UUID) { router.openOutfit(id) }
    func didTapBuildOutfit() { router.openBuildOutfit(withPiece: pieceID) }
    func didTapRepairs() { router.openRepairs() }
    func didTapLaundry() { router.openLaundry() }
    func didTapBack() { router.dismiss() }

    func didTapMarkWorn() { isMarkWornPresented = true }

    func didConfirmMarkWorn(sendToWash: Bool) {
        interactor.markWorn(pieceID: pieceID, date: Date(), sendToWash: sendToWash)
        isMarkWornPresented = false
        toast = ToastMessage(
            text: sendToWash ? "Marked as worn and sent to the wash" : "Marked as worn",
            kind: .success
        )
    }

    func didTapSendToWash() {
        interactor.sendToWash(pieceID: pieceID)
        toast = ToastMessage(
            text: "Sent to the wash",
            kind: .success,
            actionTitle: "Undo",
            action: { [weak self] in
                guard let self else { return }
                self.interactor.returnFromWash(pieceID: self.pieceID)
            }
        )
    }

    func didTapReturnFromWash() {
        interactor.returnFromWash(pieceID: pieceID)
        toast = ToastMessage(text: "Back in rotation", kind: .success)
    }

    func didTapReportRepair() { isRepairSheetPresented = true }

    func didSubmitRepair(issue: String, plannedAction: String) {
        interactor.reportRepair(pieceID: pieceID, issue: issue, plannedAction: plannedAction)
        isRepairSheetPresented = false
        toast = ToastMessage(text: "Added to the repair list", kind: .success)
    }

    func didTapStoreAway() {
        interactor.setStatus(.storedAway, pieceID: pieceID)
        toast = ToastMessage(text: "Stored away", kind: .success)
    }

    func didTapReturnToRotation() {
        interactor.setStatus(.inRotation, pieceID: pieceID)
        toast = ToastMessage(text: "Back in rotation", kind: .success)
    }

    func didTapArchive() {
        guard let state = viewState else { return }
        confirm = ConfirmRequest(
            title: "Archive This Piece?",
            message: "It leaves the wardrobe and every plan, but its history and statistics are kept. \(state.outfits.isEmpty ? "" : "It is used in \(Plural.count(state.outfits.count, "outfit")).")",
            confirmTitle: "Archive",
            isDestructive: false,
            onConfirm: { [weak self] in
                guard let self else { return }
                self.interactor.setStatus(.archived, pieceID: self.pieceID)
                self.toast = ToastMessage(text: "Archived", kind: .success)
            }
        )
    }

    func didTapDelete() {
        guard let state = viewState else { return }
        confirm = ConfirmRequest(
            title: "Delete \(state.piece.name)?",
            message: state.deleteImpactText,
            confirmTitle: "Remove Anyway",
            cancelTitle: "Keep Piece",
            isDestructive: true,
            onConfirm: { [weak self] in
                guard let self else { return }
                self.isDeleting = true
                self.interactor.delete(pieceID: self.pieceID)
                self.router.closeAfterDelete()
            }
        )
    }
}

// MARK: - Router

final class PieceDetailsRouter: PieceDetailsRouterProtocol {
    let coordinator: NavigationCoordinator

    init(coordinator: NavigationCoordinator) {
        self.coordinator = coordinator
    }

    func openEdit(_ id: UUID) { coordinator.push(.pieceForm(pieceID: id)) }
    func openOutfit(_ id: UUID) { coordinator.push(.outfitDetails(id)) }
    func openBuildOutfit(withPiece id: UUID) {
        coordinator.push(.outfitBuilder(outfitID: nil, prefillPieceID: id))
    }
    func openRepairs() { coordinator.push(.repairs) }
    func openLaundry() { coordinator.push(.laundry) }
    func closeAfterDelete() { coordinator.pop() }
}

// MARK: - Builder

enum PieceDetailsBuilder {
    static func build(dependencies: AppDependencies, pieceID: UUID) -> PieceDetailsView {
        let interactor = PieceDetailsInteractor(repository: dependencies.repository)
        let router = PieceDetailsRouter(coordinator: dependencies.coordinator)
        let presenter = PieceDetailsPresenter(interactor: interactor, router: router, pieceID: pieceID)
        return PieceDetailsView(presenter: presenter)
    }
}
