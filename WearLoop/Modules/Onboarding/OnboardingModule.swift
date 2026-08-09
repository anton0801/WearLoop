//
//  OnboardingModule.swift
//  WearLoop
//
//  Four screens explaining what the app is for before any data is entered.
//

import SwiftUI

// MARK: - Contract

protocol OnboardingInteractorProtocol: AnyObject {
    var pages: [OnboardingPage] { get }
    func markOnboardingSeen()
}

protocol OnboardingRouterProtocol: ModuleRouterProtocol {
    func finish()
}

struct OnboardingPage: Identifiable, Hashable {
    var id: Int
    var title: String
    var body: String
    /// Three short lines that make the idea concrete.
    var points: [String]
}

struct OnboardingViewState {
    var pages: [OnboardingPage] = []
    var index: Int = 0

    var isLast: Bool { index >= pages.count - 1 }
    var current: OnboardingPage? { pages.indices.contains(index) ? pages[index] : nil }
    var progressText: String { "\(index + 1) of \(pages.count)" }
}

// MARK: - Interactor

final class OnboardingInteractor: OnboardingInteractorProtocol {
    private let repository: WardrobeRepositoryProtocol

    init(repository: WardrobeRepositoryProtocol) {
        self.repository = repository
    }

    let pages: [OnboardingPage] = [
        OnboardingPage(
            id: 0,
            title: "Build a Working Wardrobe",
            body: "Wear Loop is not a photo album. It answers what to wear tomorrow, what to put in the case, and what you have not worn all year.",
            points: [
                "Everything works offline, with no account",
                "You own the data and can export it whenever you like",
                "Nothing is guessed for you without saying why"
            ]
        ),
        OnboardingPage(
            id: 1,
            title: "Add Your First Pieces",
            body: "A piece is entered once: a photograph, a category, its colours, the seasons it suits and the occasions you wear it for.",
            points: [
                "Photograph from the camera or the gallery",
                "No photo means a coloured cover in the garment's own colour",
                "Weight and price are optional but make the packing and cost figures real"
            ]
        ),
        OnboardingPage(
            id: 2,
            title: "Turn Pieces Into Outfits",
            body: "Outfits are what the app plans with. One shirt can live in as many outfits as you like, and each one knows when it is unavailable.",
            points: [
                "Lay pieces out by layer, as if on a table",
                "Send a shirt to the wash and its outfits say so at once",
                "Each outfit carries its own temperature range"
            ]
        ),
        OnboardingPage(
            id: 3,
            title: "Plan a Day or a Trip",
            body: "Assign an outfit to a day or build a trip with a day plan, a packing list and a weight check before you leave.",
            points: [
                "Nothing counts as worn until you confirm it",
                "The luggage check names what to leave behind",
                "After a trip you see what you packed and never wore"
            ]
        )
    ]

    func markOnboardingSeen() {
        repository.mutate { state in
            state.hasSeenOnboarding = true
        }
    }
}

// MARK: - Presenter

final class OnboardingPresenter: ObservableObject {
    @Published private(set) var viewState = OnboardingViewState()

    private let interactor: OnboardingInteractorProtocol
    private let router: OnboardingRouterProtocol

    init(interactor: OnboardingInteractorProtocol, router: OnboardingRouterProtocol) {
        self.interactor = interactor
        self.router = router
        viewState.pages = interactor.pages
    }

    func onAppear() {}

    func didTapNext() {
        if viewState.isLast {
            finish()
        } else {
            viewState.index += 1
        }
    }

    func didTapBack() {
        guard viewState.index > 0 else { return }
        viewState.index -= 1
    }

    func didSelectPage(_ index: Int) {
        guard viewState.pages.indices.contains(index) else { return }
        viewState.index = index
    }

    func didTapSkip() {
        finish()
    }

    private func finish() {
        interactor.markOnboardingSeen()
        router.finish()
    }
}

// MARK: - Router

final class OnboardingRouter: OnboardingRouterProtocol {
    let coordinator: NavigationCoordinator

    init(coordinator: NavigationCoordinator) {
        self.coordinator = coordinator
    }

    func finish() {
        // The root view swaps itself once onboarding is marked as seen.
        coordinator.popToRoot()
    }
}

// MARK: - Builder

enum OnboardingBuilder {
    static func build(dependencies: AppDependencies) -> OnboardingView {
        let interactor = OnboardingInteractor(repository: dependencies.repository)
        let router = OnboardingRouter(coordinator: dependencies.coordinator)
        let presenter = OnboardingPresenter(interactor: interactor, router: router)
        return OnboardingView(presenter: presenter)
    }
}
