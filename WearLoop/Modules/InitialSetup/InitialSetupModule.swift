//
//  InitialSetupModule.swift
//  WearLoop
//
//  Basic wardrobe parameters. The screen cannot be saved without at least one
//  season and one usual occasion.
//

import SwiftUI

// MARK: - Contract

protocol InitialSetupInteractorProtocol: AnyObject {
    func currentProfile() -> WardrobeProfile
    /// Saves and returns an error message if the write failed.
    func save(_ profile: WardrobeProfile) -> String?
    func seedEssentialsIfNeeded()
}

protocol InitialSetupRouterProtocol: ModuleRouterProtocol {
    func finish()
}

struct InitialSetupViewState {
    var displayName: String = ""
    var homeClimate: HomeClimate = .temperate
    var seasons: [Season] = []
    var occasions: [Occasion] = []
    var laundryCycle: LaundryCycle = .weekly
    var units: MeasurementUnits = .metric

    var seasonError: String?
    var occasionError: String?
    var saveError: String?
    var isSaving: Bool = false

    /// Editing an existing setup rather than the first run.
    var isEditing: Bool = false

    var canSave: Bool { !seasons.isEmpty && !occasions.isEmpty && !isSaving }
}

// MARK: - Interactor

final class InitialSetupInteractor: InitialSetupInteractorProtocol {
    private let repository: WardrobeRepositoryProtocol

    init(repository: WardrobeRepositoryProtocol) {
        self.repository = repository
    }

    func currentProfile() -> WardrobeProfile {
        repository.state.profile
    }

    func save(_ profile: WardrobeProfile) -> String? {
        var stored = profile
        stored.isComplete = true
        stored.displayName = profile.displayName.wlTrimmed
        return repository.mutateThrowing { state in
            state.profile = stored
        }
    }

    /// Offers a starting essentials list the first time only.
    func seedEssentialsIfNeeded() {
        guard repository.state.essentials.isEmpty else { return }
        repository.mutate { state in
            state.essentials = AppState.suggestedEssentials
        }
    }
}

// MARK: - Presenter

final class InitialSetupPresenter: ObservableObject {
    @Published var viewState = InitialSetupViewState()

    private let interactor: InitialSetupInteractorProtocol
    private let router: InitialSetupRouterProtocol

    init(interactor: InitialSetupInteractorProtocol, router: InitialSetupRouterProtocol, isEditing: Bool) {
        self.interactor = interactor
        self.router = router
        viewState.isEditing = isEditing
    }

    func onAppear() {
        let profile = interactor.currentProfile()
        viewState.displayName = profile.displayName
        viewState.homeClimate = profile.homeClimate
        viewState.seasons = profile.seasons
        viewState.occasions = profile.occasions
        viewState.laundryCycle = profile.laundryCycle
        viewState.units = profile.units
    }

    // MARK: Intents

    func toggleSeason(_ season: Season) {
        viewState.seasons.wlToggle(season)
        if !viewState.seasons.isEmpty { viewState.seasonError = nil }
    }

    func toggleOccasion(_ occasion: Occasion) {
        viewState.occasions.wlToggle(occasion)
        if !viewState.occasions.isEmpty { viewState.occasionError = nil }
    }

    func setClimate(_ climate: HomeClimate) { viewState.homeClimate = climate }
    func setCycle(_ cycle: LaundryCycle) { viewState.laundryCycle = cycle }
    func setUnits(_ units: MeasurementUnits) { viewState.units = units }

    func didTapSave() {
        guard !viewState.isSaving else { return }

        viewState.seasonError = viewState.seasons.isEmpty ? "Select at least one season." : nil
        viewState.occasionError = viewState.occasions.isEmpty ? "Select at least one occasion." : nil
        guard viewState.seasonError == nil, viewState.occasionError == nil else { return }

        viewState.isSaving = true
        viewState.saveError = nil

        let profile = WardrobeProfile(
            displayName: viewState.displayName,
            homeClimate: viewState.homeClimate,
            seasons: viewState.seasons,
            occasions: viewState.occasions,
            laundryCycle: viewState.laundryCycle,
            units: viewState.units,
            isComplete: true
        )

        if let error = interactor.save(profile) {
            viewState.isSaving = false
            viewState.saveError = error
            return
        }

        interactor.seedEssentialsIfNeeded()
        viewState.isSaving = false
        router.finish()
    }
}

// MARK: - Router

final class InitialSetupRouter: InitialSetupRouterProtocol {
    let coordinator: NavigationCoordinator
    private let isEditing: Bool

    init(coordinator: NavigationCoordinator, isEditing: Bool) {
        self.coordinator = coordinator
        self.isEditing = isEditing
    }

    func finish() {
        if isEditing {
            coordinator.pop()
        } else {
            // The root view swaps to the main app once the profile is complete.
            coordinator.popToRoot()
        }
    }
}

// MARK: - Builder

enum InitialSetupBuilder {
    static func build(dependencies: AppDependencies, isEditing: Bool = false) -> InitialSetupView {
        let interactor = InitialSetupInteractor(repository: dependencies.repository)
        let router = InitialSetupRouter(coordinator: dependencies.coordinator, isEditing: isEditing)
        let presenter = InitialSetupPresenter(interactor: interactor, router: router, isEditing: isEditing)
        return InitialSetupView(presenter: presenter)
    }
}
