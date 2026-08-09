//
//  Navigation.swift
//  WearLoop
//
//  Routers push typed routes onto a coordinator; the root resolves each route to
//  a module built by its builder. Sections are switched by the top segment bar —
//  the app has no tab bar.
//

import SwiftUI

// MARK: - Sections

/// The five sections of the app, switched by the segments under the title.
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case home
    case wardrobe
    case outfits
    case trips
    case insights

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .wardrobe: return "Wardrobe"
        case .outfits: return "Outfits"
        case .trips: return "Trips"
        case .insights: return "Insights"
        }
    }
}

// MARK: - Routes

/// Every screen that can be pushed. Sub-screens open inside their section.
enum AppRoute: Hashable {
    case pieceForm(pieceID: UUID?)
    case pieceDetails(UUID)
    case outfitBuilder(outfitID: UUID?, prefillPieceID: UUID?)
    case outfitDetails(UUID)
    case planner
    case laundry
    case events
    case eventForm(eventID: UUID?)
    case repairs
    case templates
    case tripWizard(tripID: UUID?)
    case tripWorkspace(UUID)
    case tripDayPlan(UUID)
    case packingList(UUID)
    case weightCheck(UUID)
    case tripReadiness(UUID)
    case tripRecap(UUID)
    case insightDetail(InsightKind)
    case settings
    case howItWorks
    case wardrobeSetup
    case essentialsList
    case categoryWeights
    case notificationSettings
    case aboutApp
}

/// Screens presented on top of everything rather than pushed.
enum AppSheet: Identifiable, Hashable {
    case tripMode(UUID)

    var id: String {
        switch self {
        case .tripMode(let id): return "tripMode-\(id.uuidString)"
        }
    }
}

// MARK: - Coordinator

/// Owns the navigation stack. Routers hold a reference to it and never touch
/// SwiftUI views directly.
final class NavigationCoordinator: ObservableObject {
    @Published var path: [AppRoute] = []
    @Published var section: AppSection = .home
    @Published var sheet: AppSheet?

    init() {
        #if DEBUG
        // Seeded before the first render, so a development launch argument
        // never races the navigation stack's own setup.
        if let section = DebugLaunch.section { self.section = section }
        if let route = DebugLaunch.stateIndependentRoute { self.path = [route] }
        #endif
    }

    func push(_ route: AppRoute) {
        path.append(route)
    }

    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    /// Returns to the root of the current section.
    func popToRoot() {
        path.removeAll()
    }

    /// Drops back to a route already on the stack, if it is there.
    func popTo(_ route: AppRoute) {
        guard let index = path.lastIndex(of: route) else { return }
        path.removeSubrange((index + 1)...)
    }

    /// Switches section and clears whatever was pushed inside the old one.
    func select(_ newSection: AppSection) {
        guard newSection != section || !path.isEmpty else { return }
        path.removeAll()
        section = newSection
    }

    /// Switches section and then pushes, for cross-section jumps.
    func jump(to newSection: AppSection, then route: AppRoute? = nil) {
        path.removeAll()
        section = newSection
        if let route {
            // Let the section render before pushing on top of it.
            DispatchQueue.main.async { [weak self] in
                self?.path.append(route)
            }
        }
    }

    func present(_ sheet: AppSheet) {
        self.sheet = sheet
    }

    func dismissSheet() {
        sheet = nil
    }
}

// MARK: - Dependency container

/// Assembles modules. Holding it in one place keeps builders free of globals.
///
/// There is exactly one container for the life of the process. SwiftUI can build
/// a scene's state storage more than once, and a second container would mean a
/// second `WardrobeStore` with its own debounced writer pointed at the same file
/// — two writers racing over one document.
final class AppDependencies: ObservableObject {
    static let shared = AppDependencies()

    let store: WardrobeStore
    let notifications: NotificationServiceProtocol
    let weather: WeatherServiceProtocol
    let location: LocationProviderProtocol
    let coordinator: NavigationCoordinator

    init(
        store: WardrobeStore = WardrobeStore(),
        notifications: NotificationServiceProtocol = NotificationService(),
        weather: WeatherServiceProtocol = OpenWeatherMapService(),
        location: LocationProviderProtocol = LocationProvider(),
        coordinator: NavigationCoordinator = NavigationCoordinator()
    ) {
        self.store = store
        self.notifications = notifications
        self.weather = weather
        self.location = location
        self.coordinator = coordinator

        #if DEBUG
        startDevelopmentLaunchRouting()
        #endif
    }

    #if DEBUG
    /// Opens a screen named by a launch argument once the document has loaded.
    /// Started from here rather than from a view so that it cannot be cancelled
    /// by a view being rebuilt. Compiled out of release builds.
    private func startDevelopmentLaunchRouting() {
        guard DebugLaunch.hasArguments else { return }
        Task { @MainActor [store, coordinator] in

            for _ in 0 ..< 100 where !store.loadState.isLoaded {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            guard store.loadState.isLoaded,
                  store.state.hasSeenOnboarding,
                  store.state.profile.isComplete else { return }

            // Let the interface finish its first render: a path set before the
            // stack has registered its destinations is quietly discarded.
            try? await Task.sleep(nanoseconds: 1_200_000_000)

            if let section = DebugLaunch.section {
                coordinator.section = section
            }
            if DebugLaunch.stateIndependentRoute == nil,
               let route = DebugLaunch.route(in: store.state) {
                for _ in 0 ..< 6 where coordinator.path.isEmpty {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    coordinator.path = [route]
                }
            }
            if let sheet = DebugLaunch.sheet(in: store.state) {
                try? await Task.sleep(nanoseconds: 400_000_000)
                coordinator.present(sheet)
            }
        }
    }
    #endif

    var repository: WardrobeRepositoryProtocol { store }

    /// Refreshes local reminders after a change that affects them.
    func rescheduleNotifications() {
        let snapshot = store.state
        let service = notifications
        Task.detached { await service.reschedule(state: snapshot) }
    }
}

// MARK: - Base VIPER types

/// Common shape of a presenter: it owns view state and reacts to the store.
protocol ModulePresenterProtocol: ObservableObject {
    associatedtype ViewStateType
    var viewState: ViewStateType { get }
    func onAppear()
}

/// Common shape of a router: it can go back and open other modules.
protocol ModuleRouterProtocol: AnyObject {
    var coordinator: NavigationCoordinator { get }
    func dismiss()
}

extension ModuleRouterProtocol {
    func dismiss() { coordinator.pop() }
}
