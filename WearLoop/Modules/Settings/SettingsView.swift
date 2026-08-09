//
//  SettingsView.swift
//  WearLoop
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @StateObject var presenter: SettingsPresenter

    var body: some View {
        ScreenScaffold {
            ScreenBlock(spacing: 10) {
                ScreenHeader(
                    "settings",
                    subtitle: presenter.viewState.profile.greetingName.isEmpty
                        ? "Everything is stored on this device only."
                        : "\(presenter.viewState.profile.greetingName) · stored on this device only"
                )
            }

            profileSection
            listsSection
            weatherSection
            appearanceSection
            dataSection
            aboutSection
        }
        .sheet(item: $presenter.exportedFile) { file in
            ShareSheet(items: [file.url])
        }
        .fileImporter(
            isPresented: $presenter.isImportPresented,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            presenter.didPickImportFile(result)
        }
        .toast($presenter.toast)
        .confirm($presenter.confirm)
        .onAppear { presenter.onAppear() }
    }

    // MARK: Profile

    private var profileSection: some View {
        ScreenBlock(spacing: 10) {
            SectionHeader("profile")
            NavigationRow(
                title: "Wardrobe Setup",
                subtitle: "\(presenter.viewState.profile.seasons.count) seasons · \(presenter.viewState.profile.occasions.count) occasions · \(presenter.viewState.profile.laundryCycle.title.lowercased())",
                icon: "person.crop.square"
            ) {
                presenter.didTapWardrobeSetup()
            }
            Panel {
                FactRow(label: "Display Name", value: presenter.viewState.profile.greetingName.isEmpty ? "Not set" : presenter.viewState.profile.greetingName)
                Divider().overlay(Palette.anchor.opacity(0.1))
                FactRow(label: "Home Climate", value: presenter.viewState.profile.homeClimate.title)
                Divider().overlay(Palette.anchor.opacity(0.1))
                FactRow(label: "Units", value: presenter.viewState.profile.units.title)
            }
        }
    }

    // MARK: Lists

    private var listsSection: some View {
        ScreenBlock(spacing: 10) {
            SectionHeader("lists")
            NavigationRow(
                title: "Essentials List",
                subtitle: presenter.viewState.essentials.isEmpty
                    ? "Nothing set up"
                    : "\(Plural.count(presenter.viewState.essentials.filter(\.isEnabled).count, "item")) added to every trip",
                icon: "checklist",
                accent: Palette.amber
            ) {
                presenter.didTapEssentials()
            }
            NavigationRow(
                title: "Category Weights",
                subtitle: "Averages used when a piece has no real weight",
                icon: "scalemass",
                accent: Palette.amber
            ) {
                presenter.didTapCategoryWeights()
            }
            NavigationRow(
                title: "Notifications",
                subtitle: presenter.viewState.notifications.hasGrantedConsent
                    ? (presenter.viewState.notifications.anyEnabled ? "On" : "All reminders turned off")
                    : "Off",
                icon: "bell",
                accent: Palette.berry
            ) {
                presenter.didTapNotifications()
            }
        }
    }

    // MARK: Weather

    private var weatherSection: some View {
        ScreenBlock(spacing: 10) {
            SectionHeader("weather")

            if presenter.viewState.isWeatherKeyConfigured {
                InlineNotice(
                    text: "An OpenWeatherMap key is set up, so screens with weather offer a fetch button. Readings are never fetched on their own.",
                    icon: "checkmark.circle.fill",
                    colour: Palette.success
                )
            } else {
                InlineNotice(
                    text: "No OpenWeatherMap key is set, so weather is entered by hand. A developer adds the key in WeatherAPIKey.swift.",
                    icon: "info.circle"
                )
            }

            WLToggleRow(
                title: "Update Weather Automatically",
                subtitle: "Fetches today's conditions when the app opens. Anything you typed yourself is left alone.",
                isOn: Binding(
                    get: { presenter.viewState.weather.updateAutomatically },
                    set: { presenter.setAutoUpdateWeather($0) }
                )
            )

            WLToggleRow(
                title: "Use This Device's Location",
                subtitle: "Asked for only when you tap a fetch button, used for that one request and not stored.",
                isOn: Binding(
                    get: { presenter.viewState.weather.useDeviceLocation },
                    set: { presenter.setUseDeviceLocation($0) }
                )
            )

            FieldFrame(
                label: "City",
                helpText: presenter.viewState.weather.useDeviceLocation
                    ? "Used when the device's location is unavailable."
                    : "Used for every weather lookup. A country helps: \"Berlin, DE\"."
            ) {
                WLTextField(
                    placeholder: "Berlin, DE",
                    text: Binding(
                        get: { presenter.viewState.weather.cityName },
                        set: { presenter.setWeatherCity($0) }
                    ),
                    capitalization: .words
                )
            }
        }
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        ScreenBlock(spacing: 10) {
            SectionHeader("appearance")
            WLToggleRow(
                title: "Dark Trip Mode",
                subtitle: "Trip mode is the one dark screen in the app. Photographs keep their colour either way.",
                isOn: Binding(
                    get: { presenter.viewState.appearance.useDarkTripMode },
                    set: { presenter.setDarkTripMode($0) }
                )
            )
            WLToggleRow(
                title: "Halftone Motif",
                subtitle: "The dot pattern behind empty states, the luggage gauge and trip headers.",
                isOn: Binding(
                    get: { presenter.viewState.appearance.showHalftoneMotif },
                    set: { presenter.setHalftone($0) }
                )
            )
            WLToggleRow(
                title: "Reduce Motion",
                subtitle: "Turns down the spring animations throughout the app.",
                isOn: Binding(
                    get: { presenter.viewState.appearance.reduceMotion },
                    set: { presenter.setReduceMotion($0) }
                )
            )
        }
    }

    // MARK: Data

    private var dataSection: some View {
        ScreenBlock(spacing: 10) {
            SectionHeader("your data")

            Panel {
                FactRow(label: "Pieces", value: "\(presenter.viewState.pieceCount)")
                Divider().overlay(Palette.anchor.opacity(0.1))
                FactRow(label: "Outfits", value: "\(presenter.viewState.outfitCount)")
                Divider().overlay(Palette.anchor.opacity(0.1))
                FactRow(label: "Trips", value: "\(presenter.viewState.tripCount)")
                Divider().overlay(Palette.anchor.opacity(0.1))
                FactRow(label: "Wear Records", value: "\(presenter.viewState.wearRecordCount)")
                Divider().overlay(Palette.anchor.opacity(0.1))
                FactRow(label: "Photographs", value: "\(presenter.viewState.photoCount)")
                if presenter.viewState.unusedPhotoCount > 0 {
                    Divider().overlay(Palette.anchor.opacity(0.1))
                    FactRow(
                        label: "Unused Photographs",
                        value: "\(presenter.viewState.unusedPhotoCount)",
                        valueColour: Palette.berry
                    )
                }
                Divider().overlay(Palette.anchor.opacity(0.1))
                FactRow(label: "Document Size", value: presenter.viewState.storageText)
            }

            SecondaryButton(title: "Export Data") { presenter.didTapExport() }
            SecondaryButton(title: "Import Backup") { presenter.didTapImport() }
            if presenter.viewState.unusedPhotoCount > 0 {
                SecondaryButton(
                    title: "Remove \(Plural.count(presenter.viewState.unusedPhotoCount, "Unused Photo"))"
                ) {
                    presenter.didTapCleanUpPhotos()
                }
            }

            Text("Export writes a single JSON file you can keep anywhere. Importing replaces everything currently in the app.")
                .font(TypeScale.captionSmall)
                .foregroundStyle(Palette.anchor.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)

            SecondaryButton(
                title: "Clear Wear History",
                textColour: Palette.danger,
                strokeColour: Palette.danger
            ) {
                presenter.didTapClearHistory()
            }

            DangerButton(title: "Delete All App Data") { presenter.didTapDeleteEverything() }
        }
    }

    // MARK: About

    private var aboutSection: some View {
        ScreenBlock(spacing: 10) {
            SectionHeader("about")
            NavigationRow(title: "How It Works", icon: "questionmark.circle") {
                presenter.didTapHowItWorks()
            }
            NavigationRow(title: "About Wear Loop", icon: "info.circle") {
                presenter.didTapAbout()
            }
        }
    }
}

// MARK: - Share sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Essentials list

struct EssentialsListView: View {
    @StateObject var presenter: SettingsPresenter
    let interactor: SettingsInteractorProtocol

    @State private var newName = ""
    @State private var newWeight: Double?
    @State private var error: String?

    var body: some View {
        ScreenScaffold {
            ScreenBlock(spacing: 10) {
                ScreenHeader(
                    "essentials list",
                    subtitle: "Set up once and offered on every trip: charger, toothbrush, documents."
                )
            }

            ScreenBlock(spacing: 20) {
                FieldFrame(label: "Add an Item", errorMessage: error) {
                    VStack(spacing: 10) {
                        WLTextField(
                            placeholder: "Phone charger",
                            text: $newName,
                            hasError: error != nil,
                            submitLabel: .done,
                            onSubmit: { add() }
                        )
                        HStack(spacing: 10) {
                            WLNumberField(placeholder: "Weight", value: $newWeight, suffix: "g")
                            Button("Add") { add() }
                                .buttonStyle(CompactButtonStyle(isEnabled: !newName.wlIsBlank))
                                .disabled(newName.wlIsBlank)
                        }
                    }
                }
            }

            if presenter.viewState.essentials.isEmpty {
                ScreenBlock {
                    EmptyStateView(
                        title: "nothing here yet",
                        message: "Add what you always take, or start from the usual suggestions.",
                        actionTitle: "Add the Usual Suggestions",
                        action: { interactor.restoreSuggestedEssentials() }
                    )
                }
            } else {
                ScreenBlock(spacing: 8) {
                    SectionHeader("your essentials")
                    ForEach(presenter.viewState.essentials) { item in
                        essentialRow(item)
                    }
                    SecondaryButton(title: "Add the Usual Suggestions") {
                        interactor.restoreSuggestedEssentials()
                    }
                    Text("Turning an item off keeps it in the list but stops it being added to new trips.")
                        .font(TypeScale.captionSmall)
                        .foregroundStyle(Palette.anchor.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toast($presenter.toast)
        .confirm($presenter.confirm)
        .onAppear { presenter.onAppear() }
    }

    private func essentialRow(_ item: EssentialItem) -> some View {
        HStack(spacing: 12) {
            Button {
                var updated = item
                updated.isEnabled.toggle()
                interactor.updateEssential(updated)
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(item.isEnabled ? Palette.amber : Palette.surface)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(item.isEnabled ? Palette.amber : Palette.anchor.opacity(0.3), lineWidth: 2)
                    if item.isEnabled {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(Palette.anchor)
                    }
                }
                .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isEnabled ? "\(item.name), on" : "\(item.name), off")

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(TypeScale.bodyBold)
                    .foregroundStyle(item.isEnabled ? Palette.anchor : Palette.anchor.opacity(0.5))
                Text(item.weightGrams.map { "\(Int($0)) g" } ?? "No weight entered")
                    .font(TypeScale.captionSmall)
                    .foregroundStyle(Palette.anchor.opacity(0.5))
            }
            Spacer(minLength: 8)
            Button {
                presenter.confirm = ConfirmRequest(
                    title: "Remove \(item.name)?",
                    message: "It is taken off the essentials list and off trips that have not finished.",
                    confirmTitle: "Remove",
                    cancelTitle: "Keep",
                    isDestructive: true,
                    onConfirm: { interactor.deleteEssential(item.id) }
                )
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Palette.danger)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(item.name)")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.surface))
    }

    private func add() {
        guard !newName.wlIsBlank else {
            error = "Enter a name to add an item."
            return
        }
        interactor.addEssential(name: newName, weight: newWeight)
        newName = ""
        newWeight = nil
        error = nil
    }
}

// MARK: - Category weights

struct CategoryWeightsView: View {
    @StateObject var presenter: SettingsPresenter
    let interactor: SettingsInteractorProtocol

    var body: some View {
        ScreenScaffold {
            ScreenBlock(spacing: 10) {
                ScreenHeader(
                    "category weights",
                    subtitle: "Used when a piece has no weight of its own. The luggage check always says when an average was used."
                )
            }

            ScreenBlock(spacing: 12) {
                ForEach(PieceCategory.allCases) { category in
                    HStack(spacing: 12) {
                        Text(category.title)
                            .font(TypeScale.bodyBold)
                            .foregroundStyle(Palette.anchor)
                        Spacer(minLength: 8)
                        WLNumberField(
                            placeholder: "\(Int(category.defaultWeightGrams))",
                            value: Binding(
                                get: { presenter.viewState.categoryWeights[category] },
                                set: { interactor.setCategoryWeight($0 ?? category.defaultWeightGrams, for: category) }
                            ),
                            suffix: "g",
                            allowsDecimal: false
                        )
                        .frame(width: 140)
                    }
                }

                SecondaryButton(title: "Reset to Defaults") {
                    presenter.confirm = ConfirmRequest(
                        title: "Reset Category Weights?",
                        message: "Every category goes back to the value the app shipped with.",
                        confirmTitle: "Reset",
                        isDestructive: false,
                        onConfirm: { interactor.resetCategoryWeights() }
                    )
                }
            }
        }
        .toast($presenter.toast)
        .confirm($presenter.confirm)
        .onAppear { presenter.onAppear() }
    }
}

// MARK: - Notification settings

struct NotificationSettingsView: View {
    @StateObject var presenter: SettingsPresenter
    let interactor: SettingsInteractorProtocol

    @State private var isRequesting = false

    var body: some View {
        ScreenScaffold {
            ScreenBlock(spacing: 10) {
                ScreenHeader("notifications", subtitle: "Local reminders only. Nothing leaves this device.")
            }

            if !presenter.viewState.notifications.hasGrantedConsent {
                ScreenBlock(spacing: 14) {
                    Panel {
                        Text("What these are for")
                            .font(TypeScale.bodyBold)
                            .foregroundStyle(Palette.anchor)
                        VStack(alignment: .leading, spacing: 8) {
                            reason("A trip starts in two days and some days have no outfit")
                            reason("A wash load should be dry and ready to return")
                            reason("An event is tomorrow and has no outfit assigned")
                            reason("A repair has been waiting for weeks")
                        }
                    }
                    PrimaryButton(title: "Turn On Reminders", isBusy: isRequesting) {
                        Task { await enable() }
                    }
                    Text("You can turn each reminder off separately afterwards, and turn them all off at any time.")
                        .font(TypeScale.captionSmall)
                        .foregroundStyle(Palette.anchor.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ScreenBlock(spacing: 10) {
                    toggle(
                        "Trip Starts in Two Days",
                        subtitle: "With a note of any day still missing an outfit.",
                        keyPath: \.tripStartsInTwoDays
                    )
                    toggle(
                        "Laundry Ready to Return",
                        subtitle: "When a load should be dry.",
                        keyPath: \.laundryReadyToReturn
                    )
                    toggle(
                        "Event Tomorrow Without an Outfit",
                        subtitle: "The evening before.",
                        keyPath: \.eventTomorrowWithoutOutfit
                    )
                    toggle(
                        "Repair Pending",
                        subtitle: "When something has been waiting a fortnight.",
                        keyPath: \.repairPending
                    )

                    SecondaryButton(
                        title: "Turn Off All Reminders",
                        textColour: Palette.danger,
                        strokeColour: Palette.danger
                    ) {
                        var settings = presenter.viewState.notifications
                        settings.hasGrantedConsent = false
                        interactor.setNotificationSettings(settings)
                    }

                    Text("Turning them off here cancels everything scheduled. The system permission stays as it is.")
                        .font(TypeScale.captionSmall)
                        .foregroundStyle(Palette.anchor.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toast($presenter.toast)
        .onAppear { presenter.onAppear() }
    }

    private func reason(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Palette.amber)
                .frame(width: 6, height: 6)
                .padding(.top, 7)
            Text(text)
                .font(TypeScale.caption)
                .foregroundStyle(Palette.anchor)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func toggle(
        _ title: String,
        subtitle: String,
        keyPath: WritableKeyPath<NotificationSettings, Bool>
    ) -> some View {
        WLToggleRow(
            title: title,
            subtitle: subtitle,
            isOn: Binding(
                get: { presenter.viewState.notifications[keyPath: keyPath] },
                set: { newValue in
                    var settings = presenter.viewState.notifications
                    settings[keyPath: keyPath] = newValue
                    interactor.setNotificationSettings(settings)
                }
            )
        )
    }

    private func enable() async {
        isRequesting = true
        let granted = await interactor.requestNotificationPermission()
        isRequesting = false
        if granted {
            var settings = presenter.viewState.notifications
            settings.hasGrantedConsent = true
            interactor.setNotificationSettings(settings)
            presenter.toast = ToastMessage(text: "Reminders turned on", kind: .success)
        } else {
            presenter.toast = ToastMessage(
                text: "Permission was not granted. You can allow notifications for Wear Loop in the Settings app.",
                kind: .failure
            )
        }
    }
}
