//
//  TemplatesModule.swift
//  WearLoop
//
//  Packing sets kept from past trips. Applying one checks that the pieces still
//  exist and are usable, and says exactly what is missing.
//

import Combine
import SwiftUI

// MARK: - Contract

/// What a template looks like against the wardrobe as it is today.
struct TemplateAvailability: Equatable {
    var availableIDs: [UUID] = []
    var archivedIDs: [UUID] = []
    var needsRepairIDs: [UUID] = []
    var inWashIDs: [UUID] = []
    var deletedCount: Int = 0

    var missingCount: Int { archivedIDs.count + needsRepairIDs.count + deletedCount }
    var isFullyAvailable: Bool { missingCount == 0 && inWashIDs.isEmpty }

    /// The sentence shown before applying.
    func summary(total: Int) -> String {
        var parts: [String] = ["This template uses \(Plural.count(total, "piece"))."]
        var issues: [String] = []
        if !archivedIDs.isEmpty { issues.append("\(archivedIDs.count) archived") }
        if !needsRepairIDs.isEmpty { issues.append("\(needsRepairIDs.count) needing repair") }
        if deletedCount > 0 { issues.append("\(deletedCount) no longer in your wardrobe") }
        if !inWashIDs.isEmpty { issues.append("\(inWashIDs.count) in the wash") }
        if issues.isEmpty {
            parts.append("All of them are ready.")
        } else {
            parts.append("\(issues.joined(separator: ", ").capitalizedFirst).")
        }
        return parts.joined(separator: " ")
    }
}

struct TemplateItem: Identifiable, Equatable {
    var id: UUID
    var template: PackingTemplate
    var availability: TemplateAvailability
    var summary: String
    var pieces: [Piece]
}

struct TemplatesViewState {
    var items: [TemplateItem] = []
    var applicableTrips: [Trip] = []
    var showHalftone: Bool = true
    var summaryText: String = ""
}

protocol TemplatesInteractorProtocol: AnyObject {
    var repository: WardrobeRepositoryProtocol { get }
    func buildViewState() -> TemplatesViewState
    func rename(_ id: UUID, to name: String)
    func delete(_ id: UUID)
    /// Adds the template's still-usable pieces to a trip's packing list.
    func apply(templateID: UUID, to tripID: UUID, availableOnly: Bool) -> Int
}

protocol TemplatesRouterProtocol: ModuleRouterProtocol {
    func openTrip(_ id: UUID)
    func openPiece(_ id: UUID)
}

// MARK: - Interactor

final class TemplatesInteractor: TemplatesInteractorProtocol {
    let repository: WardrobeRepositoryProtocol

    init(repository: WardrobeRepositoryProtocol) {
        self.repository = repository
    }

    func buildViewState() -> TemplatesViewState {
        let state = repository.state
        var view = TemplatesViewState()
        view.showHalftone = state.appearance.showHalftoneMotif

        view.items = state.templates
            .sorted { $0.createdAt > $1.createdAt }
            .map { template in
                var availability = TemplateAvailability()
                for id in template.pieceIDs {
                    guard let piece = state.piece(id) else {
                        availability.deletedCount += 1
                        continue
                    }
                    switch piece.status {
                    case .archived: availability.archivedIDs.append(id)
                    case .needsRepair: availability.needsRepairIDs.append(id)
                    case .inWash:
                        availability.inWashIDs.append(id)
                        availability.availableIDs.append(id)
                    case .inRotation, .storedAway:
                        availability.availableIDs.append(id)
                    }
                }
                return TemplateItem(
                    id: template.id,
                    template: template,
                    availability: availability,
                    summary: availability.summary(total: template.pieceIDs.count),
                    pieces: template.pieceIDs.compactMap { state.piece($0) }
                )
            }

        // Trips a template can be applied to.
        view.applicableTrips = state.trips
            .filter { $0.phase != .completed }
            .sorted { $0.startDate < $1.startDate }

        view.summaryText = Plural.count(view.items.count, "template")
        return view
    }

    func rename(_ id: UUID, to name: String) {
        repository.mutate { state in
            guard let index = state.templates.firstIndex(where: { $0.id == id }) else { return }
            state.templates[index].name = name.wlTrimmed
        }
    }

    func delete(_ id: UUID) {
        repository.mutate { state in
            state.templates.removeAll { $0.id == id }
        }
    }

    @discardableResult
    func apply(templateID: UUID, to tripID: UUID, availableOnly: Bool) -> Int {
        var added = 0
        repository.mutate { state in
            guard let template = state.templates.first(where: { $0.id == templateID }),
                  let tripIndex = state.trips.firstIndex(where: { $0.id == tripID }) else { return }

            for pieceID in template.pieceIDs {
                guard let piece = state.piece(pieceID) else { continue }
                if availableOnly && (piece.status == .archived || piece.status == .needsRepair) { continue }
                // Never list the same piece twice.
                guard !state.trips[tripIndex].packing.contains(where: { $0.pieceID == pieceID }) else { continue }
                state.trips[tripIndex].packing.append(PackingEntry(source: .manual, pieceID: pieceID))
                added += 1
            }

            for name in template.manualItems {
                let exists = state.trips[tripIndex].packing.contains {
                    $0.pieceID == nil && $0.manualName == name
                }
                guard !exists else { continue }
                state.trips[tripIndex].packing.append(PackingEntry(source: .manual, manualName: name))
                added += 1
            }
            state.trips[tripIndex].updatedAt = Date()
        }
        return added
    }
}

// MARK: - Presenter

final class TemplatesPresenter: ObservableObject {
    @Published private(set) var viewState = TemplatesViewState()
    @Published var applyingTemplate: TemplateItem?
    @Published var renamingTemplate: TemplateItem?
    @Published var toast: ToastMessage?
    @Published var confirm: ConfirmRequest?

    private let interactor: TemplatesInteractorProtocol
    private let router: TemplatesRouterProtocol
    private var cancellables = Set<AnyCancellable>()

    init(interactor: TemplatesInteractorProtocol, router: TemplatesRouterProtocol) {
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
        viewState = interactor.buildViewState()
    }

    func didTapApply(_ item: TemplateItem) {
        guard !viewState.applicableTrips.isEmpty else {
            toast = ToastMessage(text: "Create a trip first, then apply a template to it.", kind: .failure)
            return
        }
        applyingTemplate = item
    }

    func didConfirmApply(templateID: UUID, tripID: UUID, availableOnly: Bool) {
        let added = interactor.apply(templateID: templateID, to: tripID, availableOnly: availableOnly)
        applyingTemplate = nil
        toast = ToastMessage(
            text: added == 0
                ? "Everything from this template was already on that trip"
                : "\(Plural.count(added, "item")) added to the trip",
            kind: added == 0 ? .info : .success
        )
    }

    func didTapRename(_ item: TemplateItem) { renamingTemplate = item }

    func didSubmitRename(_ id: UUID, name: String) {
        interactor.rename(id, to: name)
        renamingTemplate = nil
        toast = ToastMessage(text: "Template renamed", kind: .success)
    }

    func didTapDelete(_ item: TemplateItem) {
        confirm = ConfirmRequest(
            title: "Delete \(item.template.name)?",
            message: "The template is removed. Trips already built from it are unaffected.",
            confirmTitle: "Delete Template",
            cancelTitle: "Keep",
            isDestructive: true,
            onConfirm: { [weak self] in
                self?.interactor.delete(item.id)
                self?.toast = ToastMessage(text: "Template deleted", kind: .info)
            }
        )
    }

    func didTapPiece(_ id: UUID) { router.openPiece(id) }
    func didTapTrip(_ id: UUID) { router.openTrip(id) }
}

// MARK: - Router

final class TemplatesRouter: TemplatesRouterProtocol {
    let coordinator: NavigationCoordinator

    init(coordinator: NavigationCoordinator) {
        self.coordinator = coordinator
    }

    func openTrip(_ id: UUID) { coordinator.push(.tripWorkspace(id)) }
    func openPiece(_ id: UUID) { coordinator.jump(to: .wardrobe, then: .pieceDetails(id)) }
}

// MARK: - Builder

enum TemplatesBuilder {
    static func build(dependencies: AppDependencies) -> TemplatesView {
        let interactor = TemplatesInteractor(repository: dependencies.repository)
        let router = TemplatesRouter(coordinator: dependencies.coordinator)
        let presenter = TemplatesPresenter(interactor: interactor, router: router)
        return TemplatesView(presenter: presenter)
    }
}
