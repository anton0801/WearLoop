//
//  LaundryModule.swift
//  WearLoop
//
//  The wash cycle controls availability. A piece in the wash cannot be planned
//  or packed, but stays visible with the date it comes back.
//

import Combine
import SwiftUI

// MARK: - Contract

protocol LaundryInteractorProtocol: AnyObject {
    var repository: WardrobeRepositoryProtocol { get }
    func buildViewState(section: LaundryStage, now: Date) -> LaundryViewState
    func startLoad(name: String, pieceIDs: [UUID], temperature: Int, notes: String)
    func advance(loadID: UUID, to stage: LaundryStage)
    func returnPieces(_ ids: [UUID])
    func sendToWash(_ ids: [UUID])
    /// Warns when a load mixes different care instructions.
    func careConflict(for pieceIDs: [UUID]) -> String?
}

protocol LaundryRouterProtocol: ModuleRouterProtocol {
    func openPiece(_ id: UUID)
    func openWardrobe()
}

struct LaundryLoadItem: Identifiable, Equatable {
    var id: UUID
    var name: String
    var stage: LaundryStage
    var pieces: [Piece]
    var detail: String
    var expectedText: String?
    var isOverdue: Bool
    var notes: String
    var careWarning: String?
}

struct LaundryViewState {
    var basket: [Piece] = []
    var loads: [LaundryLoadItem] = []
    var stageCounts: [LaundryStage: Int] = [:]
    var readyPieceIDs: [UUID] = []
    var availableToWash: [Piece] = []
    var totalInWash: Int = 0
    var summaryText: String = ""
    var cycleText: String = ""
    var showHalftone: Bool = true
}

// MARK: - Interactor

final class LaundryInteractor: LaundryInteractorProtocol {
    let repository: WardrobeRepositoryProtocol

    init(repository: WardrobeRepositoryProtocol) {
        self.repository = repository
    }

    func buildViewState(section: LaundryStage, now: Date) -> LaundryViewState {
        let state = repository.state
        var view = LaundryViewState()
        view.showHalftone = state.appearance.showHalftoneMotif
        view.cycleText = "Your cycle is \(state.profile.laundryCycle.title.lowercased())."

        view.basket = state.washBasket.compactMap { state.piece($0) }
        view.availableToWash = state.pieces
            .filter { $0.status == .inRotation }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let allLoads = state.laundryLoads.map { load -> LaundryLoadItem in
            let pieces = load.pieceIDs.compactMap { state.piece($0) }
            let overdue = load.expectedReady.map { $0.wlStartOfDay < now.wlStartOfDay } ?? false
            var detail = Plural.count(pieces.count, "piece")
            detail += " · \(load.temperatureC) °C"
            return LaundryLoadItem(
                id: load.id,
                name: load.name,
                stage: load.stage,
                pieces: pieces,
                detail: detail,
                expectedText: load.expectedReady.map {
                    overdue
                        ? "Due back \(DateFormatterCache.relativeDayText($0, now: now)) — overdue"
                        : "Expected \(DateFormatterCache.relativeDayText($0, now: now))"
                },
                isOverdue: overdue,
                notes: load.notes,
                careWarning: careConflict(for: load.pieceIDs)
            )
        }

        view.stageCounts[.toWash] = view.basket.count
        view.stageCounts[.washingNow] = allLoads.filter { $0.stage == .washingNow }.count
        view.stageCounts[.drying] = allLoads.filter { $0.stage == .drying }.count
        view.stageCounts[.readyToReturn] = allLoads.filter { $0.stage == .readyToReturn }.count

        view.loads = allLoads.filter { $0.stage == section }
        view.readyPieceIDs = allLoads.filter { $0.stage == .readyToReturn }.flatMap { $0.pieces.map(\.id) }
        view.totalInWash = state.piecesInWash.count

        view.summaryText = view.totalInWash == 0
            ? "Nothing is in the wash"
            : "\(Plural.count(view.totalInWash, "piece")) in the wash"

        return view
    }

    /// Compares the care notes and materials of the pieces going into one load.
    func careConflict(for pieceIDs: [UUID]) -> String? {
        let state = repository.state
        let pieces = pieceIDs.compactMap { state.piece($0) }
        guard pieces.count > 1 else { return nil }

        let notes = pieces
            .map { $0.careNotes.wlTrimmed.lowercased() }
            .filter { !$0.isEmpty }
            .wlUnique
        if notes.count > 1 {
            return "\(Plural.count(notes.count, "piece")) in this load have different care notes."
        }

        // Delicate materials mixed with anything else is worth flagging.
        let delicateWords = ["silk", "wool", "cashmere", "linen", "lace", "viscose"]
        let delicate = pieces.filter { piece in
            let material = piece.material.lowercased()
            return delicateWords.contains { material.contains($0) }
        }
        if !delicate.isEmpty && delicate.count < pieces.count {
            let names = delicate.prefix(2).map(\.name).joined(separator: " and ")
            return "\(names) \(delicate.count == 1 ? "is" : "are") delicate and the rest of this load is not."
        }
        return nil
    }

    func startLoad(name: String, pieceIDs: [UUID], temperature: Int, notes: String) {
        repository.mutate { state in
            WardrobeActions.startLoad(
                name: name,
                pieceIDs: pieceIDs,
                temperatureC: temperature,
                notes: notes,
                in: &state
            )
        }
    }

    func advance(loadID: UUID, to stage: LaundryStage) {
        repository.mutate { state in
            WardrobeActions.advanceLoad(loadID, to: stage, in: &state)
        }
    }

    func returnPieces(_ ids: [UUID]) {
        repository.mutate { state in
            WardrobeActions.returnFromWash(pieceIDs: ids, in: &state)
        }
    }

    func sendToWash(_ ids: [UUID]) {
        repository.mutate { state in
            WardrobeActions.sendToWash(pieceIDs: ids, in: &state)
        }
    }
}

// MARK: - Presenter

final class LaundryPresenter: ObservableObject {
    @Published private(set) var viewState = LaundryViewState()
    @Published var section: LaundryStage = .toWash { didSet { refresh() } }
    @Published var isStartLoadPresented = false
    @Published var isAddToBasketPresented = false
    @Published var toast: ToastMessage?
    @Published var confirm: ConfirmRequest?

    private let interactor: LaundryInteractorProtocol
    private let router: LaundryRouterProtocol
    private var cancellables = Set<AnyCancellable>()

    init(interactor: LaundryInteractorProtocol, router: LaundryRouterProtocol) {
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

    func segmentItems() -> [SegmentItem<LaundryStage>] {
        LaundryStage.allCases.map {
            SegmentItem(value: $0, title: $0.title, badge: viewState.stageCounts[$0])
        }
    }

    func careWarningForBasket() -> String? {
        interactor.careConflict(for: viewState.basket.map(\.id))
    }

    // MARK: Intents

    func didTapPiece(_ id: UUID) { router.openPiece(id) }
    func didTapWardrobe() { router.openWardrobe() }
    func didTapStartLoad() { isStartLoadPresented = true }
    func didTapAddToBasket() { isAddToBasketPresented = true }

    func didSelectPiecesToWash(_ ids: [UUID]) {
        guard !ids.isEmpty else {
            isAddToBasketPresented = false
            return
        }
        interactor.sendToWash(ids)
        isAddToBasketPresented = false
        toast = ToastMessage(text: "\(Plural.count(ids.count, "piece")) sent to the wash", kind: .success)
    }

    func didStartLoad(name: String, pieceIDs: [UUID], temperature: Int, notes: String) {
        interactor.startLoad(name: name, pieceIDs: pieceIDs, temperature: temperature, notes: notes)
        isStartLoadPresented = false
        section = .washingNow
        toast = ToastMessage(text: "Load started", kind: .success)
    }

    func didTapAdvance(_ item: LaundryLoadItem) {
        switch item.stage {
        case .toWash:
            interactor.advance(loadID: item.id, to: .washingNow)
        case .washingNow:
            interactor.advance(loadID: item.id, to: .drying)
            toast = ToastMessage(text: "\(item.name) is drying", kind: .success)
        case .drying:
            interactor.advance(loadID: item.id, to: .readyToReturn)
            toast = ToastMessage(text: "\(item.name) is ready to return", kind: .success)
        case .readyToReturn:
            let ids = item.pieces.map(\.id)
            interactor.returnPieces(ids)
            toast = ToastMessage(text: "\(Plural.count(ids.count, "piece")) back in rotation", kind: .success)
        }
    }

    func didTapReturnPiece(_ id: UUID, name: String) {
        interactor.returnPieces([id])
        toast = ToastMessage(text: "\(name) is back in rotation", kind: .success)
    }

    func didTapReturnAll() {
        let ids = viewState.readyPieceIDs
        guard !ids.isEmpty else { return }
        interactor.returnPieces(ids)
        toast = ToastMessage(text: "\(Plural.count(ids.count, "piece")) back in rotation", kind: .success)
    }

    func didTapEmptyBasket() {
        let ids = viewState.basket.map(\.id)
        guard !ids.isEmpty else { return }
        confirm = ConfirmRequest(
            title: "Put Everything Back?",
            message: "\(Plural.count(ids.count, "piece")) go straight back into rotation without being washed.",
            confirmTitle: "Put Back",
            isDestructive: false,
            onConfirm: { [weak self] in
                self?.interactor.returnPieces(ids)
                self?.toast = ToastMessage(text: "Basket emptied", kind: .info)
            }
        )
    }
}

// MARK: - Router

final class LaundryRouter: LaundryRouterProtocol {
    let coordinator: NavigationCoordinator

    init(coordinator: NavigationCoordinator) {
        self.coordinator = coordinator
    }

    func openPiece(_ id: UUID) { coordinator.jump(to: .wardrobe, then: .pieceDetails(id)) }
    func openWardrobe() { coordinator.select(.wardrobe) }
}

// MARK: - Builder

enum LaundryBuilder {
    static func build(dependencies: AppDependencies) -> LaundryView {
        let interactor = LaundryInteractor(repository: dependencies.repository)
        let router = LaundryRouter(coordinator: dependencies.coordinator)
        let presenter = LaundryPresenter(interactor: interactor, router: router)
        return LaundryView(presenter: presenter)
    }
}
