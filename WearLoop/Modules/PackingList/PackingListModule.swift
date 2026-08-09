//
//  PackingListModule.swift
//  WearLoop
//
//  Built automatically from the day outfits and extended by hand. Every line
//  says why it is there.
//

import Combine
import SwiftUI

// MARK: - Contract

enum PackingSection: String, CaseIterable, Identifiable, Hashable {
    case fromOutfits
    case manual
    case essentials
    case notPacking

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fromOutfits: return "From Outfits"
        case .manual: return "Added Manually"
        case .essentials: return "Essentials"
        case .notPacking: return "Not Packing"
        }
    }
}

struct PackingRow: Identifiable, Equatable {
    var id: UUID
    var name: String
    var reason: String
    var isPacked: Bool
    var isNotPacking: Bool
    var pieceID: UUID?
    var piece: Piece?
    var weightText: String
    var isWeightEstimated: Bool
    var isUnavailable: Bool
    var unavailableText: String?
    var source: PackingSource
}

struct PackingListViewState {
    var tripName: String = ""
    var rows: [PackingRow] = []
    var sectionCounts: [PackingSection: Int] = [:]
    var packedCount: Int = 0
    var totalCount: Int = 0
    var weightText: String = ""
    var isOverLimit: Bool = false
    var dayNumbers: [Int] = []
    var hasEssentialsList: Bool = true
    var units: MeasurementUnits = .metric
    var showHalftone: Bool = true
    var canContinue: Bool = false
}

protocol PackingListInteractorProtocol: AnyObject {
    var repository: WardrobeRepositoryProtocol { get }
    func buildViewState(tripID: UUID, section: PackingSection, now: Date) -> PackingListViewState?
    func setPacked(_ packed: Bool, entryID: UUID, tripID: UUID)
    func setNotPacking(_ notPacking: Bool, entryID: UUID, tripID: UUID)
    func removeEntry(_ entryID: UUID, tripID: UUID)
    func addManual(name: String, weightGrams: Double?, tripID: UUID)
    func addPieces(_ ids: [UUID], tripID: UUID)
    func packAllFromDay(_ dayNumber: Int, tripID: UUID)
    func syncEssentials(tripID: UUID)
    func availablePieces(tripID: UUID) -> [Piece]
    func advanceStage(tripID: UUID)
}

protocol PackingListRouterProtocol: ModuleRouterProtocol {
    func openWeightCheck(_ id: UUID)
    func openPiece(_ id: UUID)
    func openEssentialsList()
}

// MARK: - Interactor

final class PackingListInteractor: PackingListInteractorProtocol {
    let repository: WardrobeRepositoryProtocol

    init(repository: WardrobeRepositoryProtocol) {
        self.repository = repository
    }

    func buildViewState(tripID: UUID, section: PackingSection, now: Date) -> PackingListViewState? {
        let state = repository.state
        guard let trip = state.trip(tripID) else { return nil }

        var view = PackingListViewState()
        view.tripName = trip.name
        view.units = state.profile.units
        view.showHalftone = state.appearance.showHalftoneMotif
        view.hasEssentialsList = !state.essentials.filter(\.isEnabled).isEmpty
        view.dayNumbers = trip.days.map(\.dayNumber)

        let estimate = LuggageEngine.estimate(trip: trip, state: state)
        view.weightText = UnitFormatter.bagWeight(grams: estimate.totalGrams, units: state.profile.units)
        view.isOverLimit = estimate.isOverLimit
        view.packedCount = trip.packedCount
        view.totalCount = trip.activePacking.count

        let allRows = trip.packing.map { entry in row(for: entry, trip: trip, state: state, now: now) }

        view.sectionCounts[.fromOutfits] = allRows.filter { $0.source == .fromOutfits && !$0.isNotPacking }.count
        view.sectionCounts[.manual] = allRows.filter { $0.source == .manual && !$0.isNotPacking }.count
        view.sectionCounts[.essentials] = allRows.filter { $0.source == .essential && !$0.isNotPacking }.count
        view.sectionCounts[.notPacking] = allRows.filter(\.isNotPacking).count

        switch section {
        case .fromOutfits:
            view.rows = allRows.filter { $0.source == .fromOutfits && !$0.isNotPacking }
        case .manual:
            view.rows = allRows.filter { $0.source == .manual && !$0.isNotPacking }
        case .essentials:
            view.rows = allRows.filter { $0.source == .essential && !$0.isNotPacking }
        case .notPacking:
            view.rows = allRows.filter(\.isNotPacking)
        }

        view.rows.sort { a, b in
            if a.isPacked != b.isPacked { return !a.isPacked }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }

        view.canContinue = !trip.activePacking.isEmpty
        return view
    }

    private func row(for entry: PackingEntry, trip: Trip, state: AppState, now: Date) -> PackingRow {
        if let pieceID = entry.pieceID, let piece = state.piece(pieceID) {
            let weight = piece.estimatedWeight(categoryWeights: state.categoryWeights)
            var unavailableText: String?
            if !piece.status.isAvailable {
                if piece.status == .inWash, let back = piece.expectedBackDate {
                    unavailableText = "In the wash until \(DateFormatterCache.relativeDayText(back, now: now))"
                } else {
                    unavailableText = piece.status.title
                }
            }
            return PackingRow(
                id: entry.id,
                name: piece.name,
                reason: reasonText(entry: entry),
                isPacked: entry.isPacked,
                isNotPacking: entry.isNotPacking,
                pieceID: pieceID,
                piece: piece,
                weightText: UnitFormatter.weight(grams: weight.grams, units: state.profile.units),
                isWeightEstimated: weight.isEstimate,
                isUnavailable: !piece.status.isAvailable,
                unavailableText: unavailableText,
                source: entry.source
            )
        }

        let grams = entry.manualWeightGrams
        return PackingRow(
            id: entry.id,
            name: entry.manualName ?? "Item",
            reason: reasonText(entry: entry),
            isPacked: entry.isPacked,
            isNotPacking: entry.isNotPacking,
            pieceID: nil,
            piece: nil,
            weightText: grams.map { UnitFormatter.weight(grams: $0, units: state.profile.units) } ?? "No weight",
            isWeightEstimated: grams == nil,
            isUnavailable: false,
            unavailableText: nil,
            source: entry.source
        )
    }

    private func reasonText(entry: PackingEntry) -> String {
        switch entry.source {
        case .fromOutfits:
            return entry.dayNumbers.isEmpty
                ? "No day needs this any more."
                : "Needed for \(Plural.days(entry.dayNumbers))."
        case .manual:
            return "Added manually."
        case .essential:
            return "Essential, always packed."
        }
    }

    // MARK: Mutations

    private func withTrip(_ tripID: UUID, _ block: @escaping (inout Trip) -> Void) {
        repository.mutate { state in
            guard let index = state.trips.firstIndex(where: { $0.id == tripID }) else { return }
            block(&state.trips[index])
            state.trips[index].updatedAt = Date()
        }
    }

    func setPacked(_ packed: Bool, entryID: UUID, tripID: UUID) {
        withTrip(tripID) { trip in
            guard let index = trip.packing.firstIndex(where: { $0.id == entryID }) else { return }
            trip.packing[index].isPacked = packed
        }
    }

    func setNotPacking(_ notPacking: Bool, entryID: UUID, tripID: UUID) {
        withTrip(tripID) { trip in
            guard let index = trip.packing.firstIndex(where: { $0.id == entryID }) else { return }
            trip.packing[index].isNotPacking = notPacking
            if notPacking { trip.packing[index].isPacked = false }
        }
    }

    func removeEntry(_ entryID: UUID, tripID: UUID) {
        withTrip(tripID) { trip in
            trip.packing.removeAll { $0.id == entryID }
        }
    }

    func addManual(name: String, weightGrams: Double?, tripID: UUID) {
        withTrip(tripID) { trip in
            trip.packing.append(
                PackingEntry(source: .manual, manualName: name.wlTrimmed, manualWeightGrams: weightGrams)
            )
        }
    }

    func addPieces(_ ids: [UUID], tripID: UUID) {
        withTrip(tripID) { trip in
            for id in ids {
                // A piece already required by an outfit is not listed twice.
                guard !trip.packing.contains(where: { $0.pieceID == id }) else { continue }
                trip.packing.append(
                    PackingEntry(source: .manual, pieceID: id, wasAddedManually: true)
                )
            }
        }
    }

    func packAllFromDay(_ dayNumber: Int, tripID: UUID) {
        withTrip(tripID) { trip in
            for index in trip.packing.indices
            where trip.packing[index].dayNumbers.contains(dayNumber) && !trip.packing[index].isNotPacking {
                trip.packing[index].isPacked = true
            }
        }
    }

    func syncEssentials(tripID: UUID) {
        repository.mutate { state in
            WardrobeActions.syncEssentials(tripID: tripID, in: &state)
        }
    }

    func availablePieces(tripID: UUID) -> [Piece] {
        let state = repository.state
        let alreadyThere = Set(state.trip(tripID)?.packing.compactMap(\.pieceID) ?? [])
        return state.pieces
            .filter { $0.status != .archived && !alreadyThere.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func advanceStage(tripID: UUID) {
        repository.mutate { state in
            guard let index = state.trips.firstIndex(where: { $0.id == tripID }) else { return }
            if state.trips[index].stage.order < TripStage.weightCheck.order {
                state.trips[index].stage = .weightCheck
            }
        }
    }
}

// MARK: - Presenter

final class PackingListPresenter: ObservableObject {
    @Published private(set) var viewState: PackingListViewState?
    @Published private(set) var isMissing = false
    @Published var section: PackingSection = .fromOutfits { didSet { refresh() } }
    @Published var isAddManualPresented = false
    @Published var isAddPiecePresented = false
    @Published var isDayPickerPresented = false
    @Published var whyRow: PackingRow?
    @Published var toast: ToastMessage?

    private let interactor: PackingListInteractorProtocol
    private let router: PackingListRouterProtocol
    private let tripID: UUID
    private var cancellables = Set<AnyCancellable>()

    init(interactor: PackingListInteractorProtocol, router: PackingListRouterProtocol, tripID: UUID) {
        self.interactor = interactor
        self.router = router
        self.tripID = tripID
    }

    func onAppear() {
        observeStoreIfNeeded()
        interactor.syncEssentials(tripID: tripID)
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
        let built = interactor.buildViewState(tripID: tripID, section: section, now: Date())
        viewState = built
        isMissing = built == nil
    }

    func segmentItems() -> [SegmentItem<PackingSection>] {
        PackingSection.allCases.map {
            SegmentItem(value: $0, title: $0.title, badge: viewState?.sectionCounts[$0])
        }
    }

    var availablePieces: [Piece] { interactor.availablePieces(tripID: tripID) }

    // MARK: Intents

    func didTogglePacked(_ row: PackingRow) {
        interactor.setPacked(!row.isPacked, entryID: row.id, tripID: tripID)
    }

    func didTapNotPacking(_ row: PackingRow) {
        interactor.setNotPacking(!row.isNotPacking, entryID: row.id, tripID: tripID)
        toast = ToastMessage(
            text: row.isNotPacking ? "\(row.name) is back on the list" : "\(row.name) will not be packed",
            kind: .info
        )
    }

    func didTapRemove(_ row: PackingRow) {
        interactor.removeEntry(row.id, tripID: tripID)
        toast = ToastMessage(text: "\(row.name) removed from this trip", kind: .info)
    }

    func didTapWhy(_ row: PackingRow) { whyRow = row }
    func didTapPiece(_ id: UUID) { router.openPiece(id) }
    func didTapAddManual() { isAddManualPresented = true }
    func didTapAddPiece() { isAddPiecePresented = true }
    func didTapPackFromDay() { isDayPickerPresented = true }
    func didTapEssentialsList() { router.openEssentialsList() }

    func didAddManual(name: String, weightGrams: Double?) {
        guard !name.wlIsBlank else { return }
        interactor.addManual(name: name, weightGrams: weightGrams, tripID: tripID)
        isAddManualPresented = false
        section = .manual
        toast = ToastMessage(text: "\(name.wlTrimmed) added", kind: .success)
    }

    func didAddPieces(_ ids: [UUID]) {
        guard !ids.isEmpty else {
            isAddPiecePresented = false
            return
        }
        interactor.addPieces(ids, tripID: tripID)
        isAddPiecePresented = false
        section = .manual
        toast = ToastMessage(text: "\(Plural.count(ids.count, "piece")) added", kind: .success)
    }

    func didPackAllFromDay(_ dayNumber: Int) {
        interactor.packAllFromDay(dayNumber, tripID: tripID)
        isDayPickerPresented = false
        toast = ToastMessage(text: "Everything for day \(dayNumber) is ticked off", kind: .success)
    }

    func didTapContinue() {
        interactor.advanceStage(tripID: tripID)
        router.openWeightCheck(tripID)
    }
}

// MARK: - Router

final class PackingListRouter: PackingListRouterProtocol {
    let coordinator: NavigationCoordinator

    init(coordinator: NavigationCoordinator) {
        self.coordinator = coordinator
    }

    func openWeightCheck(_ id: UUID) { coordinator.push(.weightCheck(id)) }
    func openPiece(_ id: UUID) { coordinator.jump(to: .wardrobe, then: .pieceDetails(id)) }
    func openEssentialsList() { coordinator.push(.essentialsList) }
}

// MARK: - Builder

enum PackingListBuilder {
    static func build(dependencies: AppDependencies, tripID: UUID) -> PackingListView {
        let interactor = PackingListInteractor(repository: dependencies.repository)
        let router = PackingListRouter(coordinator: dependencies.coordinator)
        let presenter = PackingListPresenter(interactor: interactor, router: router, tripID: tripID)
        return PackingListView(presenter: presenter)
    }
}
