//
//  OutfitDetailsModule.swift
//  WearLoop
//
//  One outfit, its check, its pieces and its history.
//

import Combine
import SwiftUI

// MARK: - Contract

protocol OutfitDetailsInteractorProtocol: AnyObject {
    var repository: WardrobeRepositoryProtocol { get }
    func buildViewState(outfitID: UUID, now: Date) -> OutfitDetailsViewState?
    func markWorn(outfitID: UUID, date: Date, sendToWash: Bool)
    func toggleFavorite(_ id: UUID)
    func setArchived(_ archived: Bool, outfitID: UUID)
    func delete(outfitID: UUID)
    func duplicate(outfitID: UUID) -> SaveOutcome
}

protocol OutfitDetailsRouterProtocol: ModuleRouterProtocol {
    func openEdit(_ id: UUID)
    func openPiece(_ id: UUID)
    func openPlanner()
    func openLaundry()
    func closeAfterDelete()
}

struct OutfitDetailsViewState {
    var outfit: Outfit
    var pieces: [(piece: Piece, layer: OutfitLayer)] = []
    var check: OutfitCheck
    var unavailableIDs: Set<UUID> = []
    var timesWorn: Int = 0
    var lastWornText: String = "Never worn"
    var wearHistory: [HistoryEntry] = []
    var plannedDates: [String] = []
    var usedInTrips: [String] = []
    var wornTodayAlready: Bool = false
    var units: MeasurementUnits = .metric
    var showHalftone: Bool = true
    var deleteImpactText: String = ""
}

// MARK: - Interactor

final class OutfitDetailsInteractor: OutfitDetailsInteractorProtocol {
    let repository: WardrobeRepositoryProtocol

    init(repository: WardrobeRepositoryProtocol) {
        self.repository = repository
    }

    func buildViewState(outfitID: UUID, now: Date) -> OutfitDetailsViewState? {
        let state = repository.state
        guard let outfit = state.outfit(outfitID) else { return nil }

        let check = AvailabilityEngine.check(outfit: outfit, state: state, referenceDate: now)
        var view = OutfitDetailsViewState(outfit: outfit, check: check)
        view.units = state.profile.units
        view.showHalftone = state.appearance.showHalftoneMotif
        view.unavailableIDs = Set(check.unavailablePieceIDs)

        view.pieces = outfit.items
            .compactMap { item -> (piece: Piece, layer: OutfitLayer)? in
                guard let piece = state.piece(item.pieceID) else { return nil }
                return (piece, item.layer)
            }
            .sorted { $0.layer.flatLayOrder < $1.layer.flatLayOrder }

        view.timesWorn = state.wearCount(forOutfit: outfitID)
        if let last = state.lastWorn(outfitID: outfitID) {
            view.lastWornText = "\(DateFormatterCache.dayMonthYear.string(from: last)) · \(Plural.count(Calendar.wl.dayCount(from: last, to: now), "day")) ago"
        }

        view.wearHistory = state.wearRecords
            .filter { $0.outfitID == outfitID }
            .sorted { $0.date > $1.date }
            .prefix(20)
            .map { record in
                HistoryEntry(
                    id: record.id,
                    title: record.context.title,
                    detail: record.wasUnplanned ? "Changed from the plan" : "As planned",
                    dateText: DateFormatterCache.dayMonthYear.string(from: record.date),
                    accent: Palette.amber
                )
            }

        // Where it is planned next.
        let today = now.wlStartOfDay
        view.plannedDates = state.dayPlans
            .filter { $0.outfitID == outfitID && $0.date.wlStartOfDay >= today && !$0.isWorn }
            .sorted { $0.date < $1.date }
            .map { DateFormatterCache.relativeDayText($0.date, now: now) }

        for event in state.events where event.outfitID == outfitID && !event.isWorn {
            view.plannedDates.append("\(event.name) on \(DateFormatterCache.dayMonth.string(from: event.date))")
        }

        view.usedInTrips = state.trips
            .filter { trip in trip.days.contains { $0.outfitID == outfitID } }
            .map { trip in
                let days = trip.days.filter { $0.outfitID == outfitID }.map(\.dayNumber)
                return "\(trip.name) · \(Plural.days(days))"
            }

        view.wornTodayAlready = state.wearRecords.contains {
            $0.outfitID == outfitID && Calendar.wl.isSameDay($0.date, now)
        }

        var impacts: [String] = []
        let plannedCount = state.dayPlans.filter { $0.outfitID == outfitID || $0.backupOutfitID == outfitID }.count
        let eventCount = state.events.filter { $0.outfitID == outfitID || $0.backupOutfitID == outfitID }.count
        let tripDayCount = state.trips.flatMap(\.days).filter { $0.outfitID == outfitID }.count
        if plannedCount > 0 { impacts.append(Plural.count(plannedCount, "planned day")) }
        if eventCount > 0 { impacts.append(Plural.count(eventCount, "event")) }
        if tripDayCount > 0 { impacts.append(Plural.count(tripDayCount, "trip day")) }

        view.deleteImpactText = impacts.isEmpty
            ? "This outfit is not assigned anywhere. The pieces themselves are not touched."
            : "This outfit is assigned to \(impacts.joined(separator: ", ")). Deleting it clears those assignments. The pieces themselves stay in your wardrobe, and past wear records keep the outfit's name."

        return view
    }

    func markWorn(outfitID: UUID, date: Date, sendToWash: Bool) {
        repository.mutate { state in
            let planID = WardrobeActions.ensureDayPlan(for: date, in: &state)
            guard let index = state.dayPlans.firstIndex(where: { $0.id == planID }) else { return }
            if state.dayPlans[index].outfitID == nil {
                state.dayPlans[index].outfitID = outfitID
            }
            let wasUnplanned = state.dayPlans[index].outfitID != outfitID
            if let existing = state.dayPlans[index].wearRecordID {
                WardrobeActions.deleteWearRecord(existing, in: &state)
            }
            let recordID = WardrobeActions.recordWear(
                outfitID: outfitID,
                pieceIDs: [],
                date: date,
                context: .day,
                wasUnplanned: wasUnplanned,
                in: &state
            )
            state.dayPlans[index].wearRecordID = recordID
            if sendToWash, let outfit = state.outfit(outfitID) {
                WardrobeActions.sendToWash(pieceIDs: outfit.pieceIDs, in: &state)
            }
        }
    }

    func toggleFavorite(_ id: UUID) {
        repository.mutate { state in
            guard let index = state.outfits.firstIndex(where: { $0.id == id }) else { return }
            state.outfits[index].isFavorite.toggle()
        }
    }

    func setArchived(_ archived: Bool, outfitID: UUID) {
        repository.mutate { state in
            guard let index = state.outfits.firstIndex(where: { $0.id == outfitID }) else { return }
            state.outfits[index].isArchived = archived
        }
    }

    func delete(outfitID: UUID) {
        repository.mutate { state in
            WardrobeActions.deleteOutfit(outfitID, in: &state)
        }
    }

    func duplicate(outfitID: UUID) -> SaveOutcome {
        guard let outfit = repository.state.outfit(outfitID) else {
            return .failed("This outfit no longer exists.")
        }
        var copy = outfit
        copy.id = UUID()
        copy.name = "\(outfit.name) copy"
        copy.createdAt = Date()
        copy.updatedAt = Date()
        copy.isFavorite = false
        copy.items = outfit.items.map { OutfitItem(pieceID: $0.pieceID, layer: $0.layer) }
        let error = repository.mutateThrowing { state in
            state.outfits.append(copy)
        }
        if let error { return .failed(error) }
        return .saved(copy.id)
    }
}

// MARK: - Presenter

final class OutfitDetailsPresenter: ObservableObject {
    @Published private(set) var viewState: OutfitDetailsViewState?
    @Published private(set) var isMissing = false
    @Published var toast: ToastMessage?
    @Published var confirm: ConfirmRequest?
    @Published var isMarkWornPresented = false

    private let interactor: OutfitDetailsInteractorProtocol
    private let router: OutfitDetailsRouterProtocol
    private let outfitID: UUID
    private var cancellables = Set<AnyCancellable>()
    private var isDeleting = false

    init(interactor: OutfitDetailsInteractorProtocol, router: OutfitDetailsRouterProtocol, outfitID: UUID) {
        self.interactor = interactor
        self.router = router
        self.outfitID = outfitID
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
        let built = interactor.buildViewState(outfitID: outfitID, now: Date())
        viewState = built
        isMissing = built == nil
    }

    func didTapEdit() { router.openEdit(outfitID) }
    func didTapPiece(_ id: UUID) { router.openPiece(id) }
    func didTapPlanner() { router.openPlanner() }
    func didTapLaundry() { router.openLaundry() }
    func didTapBack() { router.dismiss() }

    func didTapMarkWorn() { isMarkWornPresented = true }

    func didConfirmMarkWorn(sendToWash: Bool) {
        interactor.markWorn(outfitID: outfitID, date: Date(), sendToWash: sendToWash)
        isMarkWornPresented = false
        toast = ToastMessage(
            text: sendToWash ? "Marked as worn and sent to the wash" : "Marked as worn",
            kind: .success
        )
    }

    func didTapFavorite() {
        let wasFavorite = viewState?.outfit.isFavorite ?? false
        interactor.toggleFavorite(outfitID)
        toast = ToastMessage(
            text: wasFavorite ? "Removed from favourites" : "Added to favourites",
            kind: .info
        )
    }

    func didTapArchive() {
        guard let state = viewState else { return }
        let archived = state.outfit.isArchived
        if archived {
            interactor.setArchived(false, outfitID: outfitID)
            toast = ToastMessage(text: "Back in your outfits", kind: .success)
        } else {
            confirm = ConfirmRequest(
                title: "Archive This Outfit?",
                message: "It stays out of suggestions and plans but keeps its history. You can bring it back at any time.",
                confirmTitle: "Archive",
                isDestructive: false,
                onConfirm: { [weak self] in
                    guard let self else { return }
                    self.interactor.setArchived(true, outfitID: self.outfitID)
                    self.toast = ToastMessage(text: "Archived", kind: .success)
                }
            )
        }
    }

    func didTapDuplicate() {
        switch interactor.duplicate(outfitID: outfitID) {
        case .saved:
            toast = ToastMessage(text: "Outfit duplicated", kind: .success)
        case .failed(let message):
            toast = ToastMessage(text: message, kind: .failure)
        }
    }

    func didTapDelete() {
        guard let state = viewState else { return }
        confirm = ConfirmRequest(
            title: "Delete \(state.outfit.name)?",
            message: state.deleteImpactText,
            confirmTitle: "Remove Anyway",
            cancelTitle: "Keep Outfit",
            isDestructive: true,
            onConfirm: { [weak self] in
                guard let self else { return }
                self.isDeleting = true
                self.interactor.delete(outfitID: self.outfitID)
                self.router.closeAfterDelete()
            }
        )
    }
}

// MARK: - Router

final class OutfitDetailsRouter: OutfitDetailsRouterProtocol {
    let coordinator: NavigationCoordinator

    init(coordinator: NavigationCoordinator) {
        self.coordinator = coordinator
    }

    func openEdit(_ id: UUID) { coordinator.push(.outfitBuilder(outfitID: id, prefillPieceID: nil)) }
    func openPiece(_ id: UUID) { coordinator.jump(to: .wardrobe, then: .pieceDetails(id)) }
    func openPlanner() { coordinator.push(.planner) }
    func openLaundry() { coordinator.push(.laundry) }
    func closeAfterDelete() { coordinator.pop() }
}

// MARK: - Builder

enum OutfitDetailsBuilder {
    static func build(dependencies: AppDependencies, outfitID: UUID) -> OutfitDetailsView {
        let interactor = OutfitDetailsInteractor(repository: dependencies.repository)
        let router = OutfitDetailsRouter(coordinator: dependencies.coordinator)
        let presenter = OutfitDetailsPresenter(interactor: interactor, router: router, outfitID: outfitID)
        return OutfitDetailsView(presenter: presenter)
    }
}
