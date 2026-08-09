//
//  SettingsModule.swift
//  WearLoop
//
//  Profile, data management and the smaller lists. Every destructive action is
//  confirmed, and deleting everything asks twice.
//

import Combine
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Contract

/// Outcome of writing the backup file.
enum ExportOutcome {
    case exported(URL)
    case failed(String)
}

protocol SettingsInteractorProtocol: AnyObject {
    var repository: WardrobeRepositoryProtocol { get }
    func buildViewState() -> SettingsViewState
    func setAppearance(_ appearance: AppearanceSettings)
    func setWeatherSettings(_ settings: WeatherSettings)
    var isWeatherKeyConfigured: Bool { get }
    func exportData() -> ExportOutcome
    func importBackup(from url: URL) -> String?
    func clearWearHistory()
    func deleteAllData() -> String?
    func unusedPhotoCount() -> Int
    func cleanUpUnusedPhotos() -> Int
    // Essentials
    func addEssential(name: String, weight: Double?)
    func updateEssential(_ item: EssentialItem)
    func deleteEssential(_ id: UUID)
    func restoreSuggestedEssentials()
    // Category weights
    func setCategoryWeight(_ grams: Double, for category: PieceCategory)
    func resetCategoryWeights()
    // Notifications
    func setNotificationSettings(_ settings: NotificationSettings)
    func requestNotificationPermission() async -> Bool
    func rescheduleNotifications()
}

protocol SettingsRouterProtocol: ModuleRouterProtocol {
    func openWardrobeSetup()
    func openEssentials()
    func openCategoryWeights()
    func openNotifications()
    func openAbout()
    func openHowItWorks()
}

struct SettingsViewState {
    var profile: WardrobeProfile = WardrobeProfile()
    var appearance: AppearanceSettings = AppearanceSettings()
    var notifications: NotificationSettings = NotificationSettings()
    var weather: WeatherSettings = WeatherSettings()
    var isWeatherKeyConfigured: Bool = false
    var essentials: [EssentialItem] = []
    var categoryWeights: [PieceCategory: Double] = [:]

    var pieceCount: Int = 0
    var outfitCount: Int = 0
    var tripCount: Int = 0
    var wearRecordCount: Int = 0
    var photoCount: Int = 0
    var unusedPhotoCount: Int = 0
    var storageText: String = ""
    var units: MeasurementUnits = .metric
}

// MARK: - Interactor

final class SettingsInteractor: SettingsInteractorProtocol {
    let repository: WardrobeRepositoryProtocol
    private let store: WardrobeStore
    private let notificationService: NotificationServiceProtocol

    init(store: WardrobeStore, notificationService: NotificationServiceProtocol) {
        self.store = store
        self.repository = store
        self.notificationService = notificationService
    }

    func buildViewState() -> SettingsViewState {
        let state = repository.state
        var view = SettingsViewState()
        view.profile = state.profile
        view.appearance = state.appearance
        view.notifications = state.notificationSettings
        view.weather = state.weatherSettings
        view.isWeatherKeyConfigured = WeatherAPIKey.isConfigured
        view.essentials = state.essentials
        view.categoryWeights = state.categoryWeights
        view.units = state.profile.units

        view.pieceCount = state.pieces.count
        view.outfitCount = state.outfits.count
        view.tripCount = state.trips.count
        view.wearRecordCount = state.wearRecords.count
        view.photoCount = WardrobeActions.referencedPhotoIDs(in: state).count
        view.unusedPhotoCount = store.unusedPhotoCount()

        if let data = try? store.exportData() {
            let kb = Double(data.count) / 1024
            view.storageText = kb < 1024
                ? String(format: "%.0f KB", kb)
                : String(format: "%.1f MB", kb / 1024)
        } else {
            view.storageText = "unknown"
        }

        return view
    }

    func setAppearance(_ appearance: AppearanceSettings) {
        repository.mutate { $0.appearance = appearance }
    }

    func setWeatherSettings(_ settings: WeatherSettings) {
        repository.mutate { $0.weatherSettings = settings }
    }

    var isWeatherKeyConfigured: Bool { WeatherAPIKey.isConfigured }

    // MARK: Data

    func exportData() -> ExportOutcome {
        do {
            let data = try store.exportData()
            let stamp = DateFormatterCache.fileStamp.string(from: Date())
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("wearloop-backup-\(stamp).json")
            try data.write(to: url, options: .atomic)
            return .exported(url)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return .failed(message)
        }
    }

    func importBackup(from url: URL) -> String? {
        // A file picked outside the sandbox needs explicit access.
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            try store.importBackup(data)
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func clearWearHistory() {
        repository.mutate { state in
            WardrobeActions.clearWearHistory(in: &state)
        }
    }

    func unusedPhotoCount() -> Int { store.unusedPhotoCount() }

    @discardableResult
    func cleanUpUnusedPhotos() -> Int { store.cleanUpUnusedPhotos() }

    func deleteAllData() -> String? {
        do {
            try store.deleteAllData()
            notificationService.cancelAll()
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: Essentials

    func addEssential(name: String, weight: Double?) {
        repository.mutate { state in
            state.essentials.append(EssentialItem(name: name.wlTrimmed, weightGrams: weight))
        }
    }

    func updateEssential(_ item: EssentialItem) {
        repository.mutate { state in
            guard let index = state.essentials.firstIndex(where: { $0.id == item.id }) else { return }
            state.essentials[index] = item
        }
    }

    func deleteEssential(_ id: UUID) {
        repository.mutate { state in
            guard let removed = state.essentials.first(where: { $0.id == id }) else { return }
            state.essentials.removeAll { $0.id == id }
            // Take it off trips that have not finished, leaving history alone.
            for tripIndex in state.trips.indices where state.trips[tripIndex].phase != .completed {
                state.trips[tripIndex].packing.removeAll {
                    $0.source == .essential && $0.manualName == removed.name
                }
            }
        }
    }

    func restoreSuggestedEssentials() {
        repository.mutate { state in
            for suggested in AppState.suggestedEssentials
            where !state.essentials.contains(where: { $0.name == suggested.name }) {
                state.essentials.append(suggested)
            }
        }
    }

    // MARK: Category weights

    func setCategoryWeight(_ grams: Double, for category: PieceCategory) {
        repository.mutate { state in
            state.categoryWeights[category] = max(grams, 0)
        }
    }

    func resetCategoryWeights() {
        repository.mutate { state in
            state.categoryWeights = AppState.defaultCategoryWeights
        }
    }

    // MARK: Notifications

    func setNotificationSettings(_ settings: NotificationSettings) {
        repository.mutate { $0.notificationSettings = settings }
        rescheduleNotifications()
    }

    func requestNotificationPermission() async -> Bool {
        await notificationService.requestAuthorization()
    }

    func rescheduleNotifications() {
        let snapshot = repository.state
        let service = notificationService
        Task.detached { await service.reschedule(state: snapshot) }
    }
}

// MARK: - Presenter

final class SettingsPresenter: ObservableObject {
    @Published private(set) var viewState = SettingsViewState()
    @Published var toast: ToastMessage?
    @Published var confirm: ConfirmRequest?
    @Published var exportedFile: ExportedFile?
    @Published var isImportPresented = false

    private let interactor: SettingsInteractorProtocol
    private let router: SettingsRouterProtocol
    private var cancellables = Set<AnyCancellable>()

    init(interactor: SettingsInteractorProtocol, router: SettingsRouterProtocol) {
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

    fileprivate func refresh() {
        viewState = interactor.buildViewState()
    }

    // MARK: Navigation

    func didTapWardrobeSetup() { router.openWardrobeSetup() }
    func didTapEssentials() { router.openEssentials() }
    func didTapCategoryWeights() { router.openCategoryWeights() }
    func didTapNotifications() { router.openNotifications() }
    func didTapAbout() { router.openAbout() }
    func didTapHowItWorks() { router.openHowItWorks() }

    // MARK: Weather

    func setWeatherCity(_ value: String) {
        var settings = viewState.weather
        settings.cityName = value
        interactor.setWeatherSettings(settings)
    }

    func setAutoUpdateWeather(_ value: Bool) {
        var settings = viewState.weather
        settings.updateAutomatically = value
        interactor.setWeatherSettings(settings)
    }

    func setUseDeviceLocation(_ value: Bool) {
        var settings = viewState.weather
        settings.useDeviceLocation = value
        interactor.setWeatherSettings(settings)
    }

    // MARK: Appearance

    func setDarkTripMode(_ value: Bool) {
        var appearance = viewState.appearance
        appearance.useDarkTripMode = value
        interactor.setAppearance(appearance)
    }

    func setHalftone(_ value: Bool) {
        var appearance = viewState.appearance
        appearance.showHalftoneMotif = value
        interactor.setAppearance(appearance)
    }

    func setReduceMotion(_ value: Bool) {
        var appearance = viewState.appearance
        appearance.reduceMotion = value
        interactor.setAppearance(appearance)
    }

    // MARK: Data

    func didTapExport() {
        switch interactor.exportData() {
        case .exported(let url):
            exportedFile = ExportedFile(url: url)
        case .failed(let message):
            toast = ToastMessage(text: message, kind: .failure)
        }
    }

    func didTapImport() { isImportPresented = true }

    func didPickImportFile(_ result: Result<[URL], Error>) {
        isImportPresented = false
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            confirm = ConfirmRequest(
                title: "Replace Everything?",
                message: "Importing a backup replaces your current wardrobe, outfits, trips and history with the contents of the file. This cannot be undone.",
                confirmTitle: "Replace With Backup",
                cancelTitle: "Cancel",
                isDestructive: true,
                onConfirm: { [weak self] in
                    guard let self else { return }
                    if let error = self.interactor.importBackup(from: url) {
                        self.toast = ToastMessage(text: error, kind: .failure)
                    } else {
                        self.toast = ToastMessage(text: "Backup imported", kind: .success)
                        self.interactor.rescheduleNotifications()
                    }
                }
            )
        case .failure(let error):
            toast = ToastMessage(text: "That file could not be opened. \(error.localizedDescription)", kind: .failure)
        }
    }

    func didTapCleanUpPhotos() {
        let count = viewState.unusedPhotoCount
        guard count > 0 else {
            toast = ToastMessage(text: "No unused photographs to remove", kind: .info)
            return
        }
        confirm = ConfirmRequest(
            title: "Remove \(Plural.count(count, "Unused Photo"))?",
            message: "These images are not used by any piece or record. Removing them frees space and cannot be undone.",
            confirmTitle: "Remove",
            cancelTitle: "Keep",
            isDestructive: true,
            onConfirm: { [weak self] in
                guard let self else { return }
                let removed = self.interactor.cleanUpUnusedPhotos()
                self.toast = ToastMessage(text: "\(Plural.count(removed, "photograph")) removed", kind: .success)
                self.refresh()
            }
        )
    }

    func didTapClearHistory() {
        guard viewState.wearRecordCount > 0 else {
            toast = ToastMessage(text: "There is no wear history to clear", kind: .info)
            return
        }
        confirm = ConfirmRequest(
            title: "Clear Wear History?",
            message: "All \(Plural.count(viewState.wearRecordCount, "wear record")) are deleted. Your pieces, outfits and trips are kept, but every statistic starts again from nothing.",
            confirmTitle: "Clear History",
            cancelTitle: "Keep",
            isDestructive: true,
            onConfirm: { [weak self] in
                self?.interactor.clearWearHistory()
                self?.toast = ToastMessage(text: "Wear history cleared", kind: .info)
            }
        )
    }

    func didTapDeleteEverything() {
        confirm = ConfirmRequest(
            title: "Delete All App Data?",
            message: "Every piece, photograph, outfit, trip, event and record is removed and the app returns to its first-run state.",
            confirmTitle: "Delete Everything",
            cancelTitle: "Cancel",
            isDestructive: true,
            requiresSecondStep: true,
            secondStepMessage: "There is no way back from this. Nothing is stored anywhere else, so nothing can be recovered. Export a backup first if you are unsure.",
            onConfirm: { [weak self] in
                guard let self else { return }
                if let error = self.interactor.deleteAllData() {
                    self.toast = ToastMessage(text: error, kind: .failure)
                } else {
                    self.toast = ToastMessage(text: "Everything deleted", kind: .info)
                }
            }
        )
    }
}

/// Wrapper so the share sheet can be presented with `.sheet(item:)`.
struct ExportedFile: Identifiable {
    var id: String { url.absoluteString }
    var url: URL
}

// MARK: - Router

final class SettingsRouter: SettingsRouterProtocol {
    let coordinator: NavigationCoordinator

    init(coordinator: NavigationCoordinator) {
        self.coordinator = coordinator
    }

    func openWardrobeSetup() { coordinator.push(.wardrobeSetup) }
    func openEssentials() { coordinator.push(.essentialsList) }
    func openCategoryWeights() { coordinator.push(.categoryWeights) }
    func openNotifications() { coordinator.push(.notificationSettings) }
    func openAbout() { coordinator.push(.aboutApp) }
    func openHowItWorks() { coordinator.push(.howItWorks) }
}

// MARK: - Builder

enum SettingsBuilder {
    static func build(dependencies: AppDependencies) -> SettingsView {
        let interactor = SettingsInteractor(
            store: dependencies.store,
            notificationService: dependencies.notifications
        )
        let router = SettingsRouter(coordinator: dependencies.coordinator)
        let presenter = SettingsPresenter(interactor: interactor, router: router)
        return SettingsView(presenter: presenter)
    }

    static func buildEssentials(dependencies: AppDependencies) -> EssentialsListView {
        let interactor = SettingsInteractor(
            store: dependencies.store,
            notificationService: dependencies.notifications
        )
        let router = SettingsRouter(coordinator: dependencies.coordinator)
        let presenter = SettingsPresenter(interactor: interactor, router: router)
        return EssentialsListView(presenter: presenter, interactor: interactor)
    }

    static func buildCategoryWeights(dependencies: AppDependencies) -> CategoryWeightsView {
        let interactor = SettingsInteractor(
            store: dependencies.store,
            notificationService: dependencies.notifications
        )
        let router = SettingsRouter(coordinator: dependencies.coordinator)
        let presenter = SettingsPresenter(interactor: interactor, router: router)
        return CategoryWeightsView(presenter: presenter, interactor: interactor)
    }

    static func buildNotifications(dependencies: AppDependencies) -> NotificationSettingsView {
        let interactor = SettingsInteractor(
            store: dependencies.store,
            notificationService: dependencies.notifications
        )
        let router = SettingsRouter(coordinator: dependencies.coordinator)
        let presenter = SettingsPresenter(interactor: interactor, router: router)
        return NotificationSettingsView(presenter: presenter, interactor: interactor)
    }
}
