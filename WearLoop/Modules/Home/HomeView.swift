//
//  HomeView.swift
//  WearLoop
//

import SwiftUI

struct HomeView: View {
    @StateObject var presenter: HomePresenter

    var body: some View {
        ScreenScaffold {
            ScreenBlock(spacing: 10) {
                ScreenHeader(presenter.viewState.greeting, subtitle: presenter.viewState.dateText, artwork: .home) {
                    Button {
                        presenter.didTapProfile()
                    } label: {
                        Image(systemName: "person.fill")
                    }
                    .buttonStyle(IconButtonStyle())
                    .accessibilityLabel("Profile and settings")
                }
            }

            switch presenter.viewState.mode {
            case .emptyWardrobe:
                emptyWardrobe
            case .piecesWithoutOutfits(let count):
                piecesWithoutOutfits(count: count)
            case .full:
                fullHome
            }
        }
        .toast($presenter.toast)
        .sheet(isPresented: $presenter.isWeatherSheetPresented) {
            WeatherInputSheet(
                weather: presenter.viewState.weather,
                units: presenter.viewState.units,
                title: "Weather Today",
                onFetch: presenter.canFetchWeather ? { await presenter.fetchWeatherForToday() } : nil,
                fetchUnavailableReason: presenter.weatherFetchUnavailableReason
            ) { updated in
                presenter.didSaveWeather(updated)
            }
        }
        .sheet(isPresented: $presenter.isMarkWornSheetPresented) {
            MarkWornSheet(
                outfitName: presenter.viewState.suggestedOutfit?.name ?? "",
                pieceCount: presenter.viewState.suggestedPieces.count
            ) { sendToWash in
                presenter.didConfirmMarkWorn(sendToWash: sendToWash)
            }
        }
        .onAppear { presenter.onAppear() }
    }

    // MARK: - Empty states

    private var emptyWardrobe: some View {
        ScreenBlock {
            EmptyStateView(
                title: "your wardrobe is empty",
                message: "Add a few pieces and the app can start building outfits and packing lists.",
                actionTitle: "Add First Piece",
                action: { presenter.didTapAddPiece() },
                secondaryActionTitle: "How It Works",
                secondaryAction: { presenter.didTapHowItWorks() },
                showHalftone: presenter.viewState.showHalftone
            )
        }
    }

    private func piecesWithoutOutfits(count: Int) -> some View {
        VStack(alignment: .leading, spacing: Metrics.sectionGap) {
            ScreenBlock {
                EmptyStateView(
                    title: "pieces without outfits",
                    message: "You have \(Plural.count(count, "piece")) and no outfits yet. Outfits are what the app plans with.",
                    actionTitle: "Build First Outfit",
                    action: { presenter.didTapBuildOutfit() },
                    secondaryActionTitle: "Add Another Piece",
                    secondaryAction: { presenter.didTapAddPiece() },
                    showHalftone: presenter.viewState.showHalftone
                )
            }
            neverWornRail
        }
    }

    // MARK: - Full home

    private var fullHome: some View {
        VStack(alignment: .leading, spacing: Metrics.sectionGap) {
            todaysLook
            if let step = presenter.viewState.nextStep { nextStepCard(step) }
            weatherSection
            eventSection
            tripSection
            washSection
            recentlyWornRail
            neverWornRail
        }
    }

    // MARK: Today's look

    private var todaysLook: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScreenBlock {
                SectionHeader("today's look")
            }

            if let outfit = presenter.viewState.suggestedOutfit {
                ScreenBlock(spacing: 12) {
                    Button {
                        presenter.didTapSuggestedOutfit()
                    } label: {
                        OutfitFlatLay(
                            pieces: presenter.viewState.suggestedPieces.map {
                                ($0, $0.category.naturalLayer)
                            },
                            showHalftone: presenter.viewState.showHalftone,
                            height: 260
                        )
                    }
                    .buttonStyle(CardPressStyle())
                    .accessibilityLabel("\(outfit.name), \(Plural.count(presenter.viewState.suggestedPieces.count, "piece")). Opens the outfit.")

                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(outfit.name)
                                .font(TypeScale.bodyBold)
                                .foregroundStyle(Palette.anchor)
                            Text("\(outfit.occasion.title) · \(outfit.temperatureText)")
                                .font(TypeScale.captionSmall)
                                .foregroundStyle(Palette.anchor.opacity(0.6))
                        }
                        Spacer(minLength: 0)
                        if presenter.viewState.todayAlreadyWorn {
                            Label("Worn today", systemImage: "checkmark")
                                .font(TypeScale.caption)
                                .foregroundStyle(Palette.success)
                        }
                    }

                    // Why this outfit
                    Panel {
                        Text("Why This Outfit")
                            .font(TypeScale.caption)
                            .foregroundStyle(Palette.anchor.opacity(0.6))
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(presenter.viewState.suggestionReasons.enumerated()), id: \.offset) { _, reason in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle()
                                        .fill(Palette.amber)
                                        .frame(width: 6, height: 6)
                                        .padding(.top, 7)
                                    Text(reason)
                                        .font(TypeScale.caption)
                                        .foregroundStyle(Palette.anchor)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }

                    if presenter.showsWeatherWarning, let mismatch = presenter.viewState.weatherMismatch {
                        WarningPanel(
                            message: mismatch,
                            primaryTitle: "Choose Another Outfit",
                            primaryAction: { presenter.didTapPlanner() },
                            secondaryTitle: "Keep Anyway",
                            secondaryAction: { presenter.didTapKeepAnyway() },
                            tint: Palette.danger
                        )
                    }

                    HStack(spacing: 10) {
                        PrimaryButton(
                            title: presenter.viewState.todayAlreadyWorn ? "Already Worn Today" : "Mark as Worn",
                            isEnabled: !presenter.viewState.todayAlreadyWorn
                        ) {
                            presenter.didTapMarkWorn()
                        }
                        SecondaryButton(title: "Plan") { presenter.didTapPlanner() }
                            .frame(width: 110)
                    }
                }
            } else {
                ScreenBlock {
                    InlineNotice(
                        text: "No outfit can be suggested right now. Every outfit needs at least two pieces that are all in rotation.",
                        icon: "info.circle"
                    )
                    SecondaryButton(title: "Build an Outfit") { presenter.didTapBuildOutfit() }
                }
            }
        }
    }

    // MARK: Next step

    private func nextStepCard(_ step: NextStep) -> some View {
        ScreenBlock {
            Button {
                presenter.didTapNextStep()
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Next Step")
                        .font(TypeScale.captionSmall)
                        .foregroundStyle(Palette.onAnchor.opacity(0.7))
                    Text(step.title)
                        .font(TypeScale.sectionTitle)
                        .tracking(TypeScale.sectionTitleTracking)
                        .foregroundStyle(Palette.onAnchor)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(step.detail)
                        .font(TypeScale.caption)
                        .foregroundStyle(Palette.onAnchor.opacity(0.75))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                        .fill(Palette.anchor)
                )
                .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            }
            .buttonStyle(CardPressStyle())
            .accessibilityLabel("Next step: \(step.title). \(step.detail)")
        }
    }

    // MARK: Weather

    private var weatherSection: some View {
        ScreenBlock(spacing: 10) {
            SectionHeader("weather today") {
                Button(presenter.viewState.weather == nil ? "Add" : "Edit") {
                    presenter.didTapSetWeather()
                }
                .buttonStyle(CompactOutlineButtonStyle())
            }
            if let temperature = presenter.viewState.weatherTemperatureText {
                Panel {
                    Text(temperature)
                        .font(TypeScale.mediumNumber)
                        .foregroundStyle(Palette.anchor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let detail = presenter.viewState.weatherDetailText {
                        Text(detail)
                            .font(TypeScale.caption)
                            .foregroundStyle(Palette.anchor.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                InlineNotice(
                    text: "No weather entered for today. Add it and the app checks your outfit's own temperature range against it.",
                    icon: "cloud"
                )
            }
        }
    }

    // MARK: Event

    @ViewBuilder
    private var eventSection: some View {
        if let name = presenter.viewState.nextEventName {
            ScreenBlock(spacing: 10) {
                SectionHeader("upcoming event", accent: Palette.burgundy) {
                    Button("All") { presenter.didTapEvents() }
                        .buttonStyle(CompactOutlineButtonStyle())
                }
                NavigationRow(
                    title: name,
                    subtitle: presenter.viewState.nextEventDetail,
                    icon: presenter.viewState.nextEventHasOutfit ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                    accent: presenter.viewState.nextEventHasOutfit ? Palette.success : Palette.burgundy
                ) {
                    presenter.didTapEvent()
                }
            }
        }
    }

    // MARK: Trip

    @ViewBuilder
    private var tripSection: some View {
        if let trip = presenter.viewState.trip {
            ScreenBlock(spacing: 10) {
                SectionHeader(trip.isInProgress ? "trip in progress" : "trip readiness", accent: Palette.burgundy)
                Button {
                    presenter.didTapTrip()
                } label: {
                    Panel {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(trip.name)
                                    .font(TypeScale.bodyBold)
                                    .foregroundStyle(Palette.anchor)
                                Text(trip.destination.isEmpty ? trip.startText : "\(trip.destination) · \(trip.startText)")
                                    .font(TypeScale.captionSmall)
                                    .foregroundStyle(Palette.anchor.opacity(0.6))
                            }
                            Spacer(minLength: 8)
                            if let dayText = trip.dayText {
                                Text(dayText)
                                    .font(TypeScale.caption)
                                    .foregroundStyle(Palette.onAnchor)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(Palette.burgundy))
                            }
                        }
                        CountProgress(
                            passed: trip.passedChecks,
                            total: trip.totalChecks,
                            label: "checks passed",
                            fill: trip.passedChecks == trip.totalChecks ? Palette.success : Palette.amber
                        )
                        Text(trip.isInProgress ? "Open trip mode" : "Open the trip workspace")
                            .font(TypeScale.captionSmall)
                            .foregroundStyle(Palette.anchor.opacity(0.5))
                    }
                    .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                }
                .buttonStyle(CardPressStyle())
            }
        }
    }

    // MARK: Wash

    @ViewBuilder
    private var washSection: some View {
        if !presenter.viewState.inWash.isEmpty {
            ScreenBlock(spacing: 10) {
                SectionHeader("in the wash", accent: Palette.burgundy) {
                    Button("Laundry") { presenter.didTapLaundry() }
                        .buttonStyle(CompactOutlineButtonStyle())
                }
                VStack(spacing: 8) {
                    ForEach(presenter.viewState.inWash.prefix(4)) { item in
                        FactRow(
                            label: item.name,
                            value: item.backText,
                            valueColour: item.isOverdue ? Palette.danger : nil
                        )
                        .padding(14)
                        .background(PlateBackground(cornerRadius: 14))
                    }
                    if presenter.viewState.inWash.count > 4 {
                        Text("and \(presenter.viewState.inWash.count - 4) more")
                            .font(TypeScale.captionSmall)
                            .foregroundStyle(Palette.anchor.opacity(0.5))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if !presenter.viewState.readyToReturnIDs.isEmpty {
                    PrimaryButton(
                        title: "Return \(Plural.count(presenter.viewState.readyToReturnIDs.count, "Piece")) to the Wardrobe"
                    ) {
                        presenter.didTapReturnLaundry()
                    }
                }
            }
        }
    }

    // MARK: Rails

    @ViewBuilder
    private var recentlyWornRail: some View {
        if !presenter.viewState.recentlyWorn.isEmpty {
            RailSection(
                title: "recently worn",
                items: presenter.viewState.recentlyWorn
            ) { piece in
                PieceCard(
                    piece: piece,
                    statusText: piece.category.title,
                    width: Metrics.railCardWidth
                ) {
                    presenter.didTapPiece(piece.id)
                }
            }
        }
    }

    @ViewBuilder
    private var neverWornRail: some View {
        if !presenter.viewState.neverWorn.isEmpty {
            RailSection(
                title: "never worn",
                accent: Palette.burgundy,
                items: presenter.viewState.neverWorn
            ) { piece in
                PieceCard(
                    piece: piece,
                    statusText: "Not worn yet",
                    width: Metrics.railCardWidth
                ) {
                    presenter.didTapPiece(piece.id)
                }
            }
        }
    }
}

// MARK: - Weather sheet

/// Manual weather entry. There is no external service, so the numbers are the
/// user's own unless the system source is connected.
struct WeatherInputSheet: View {
    let weather: WeatherInput?
    let units: MeasurementUnits
    var title: String = "Weather"
    /// Fetches the reading for the day this sheet is editing. Absent when the
    /// screen has nothing sensible to look up.
    var onFetch: (() async -> WeatherLookupOutcome)?
    /// Why fetching is not on offer, when it is not.
    var fetchUnavailableReason: String?
    let onSave: (WeatherInput?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var temperature: Double = 15
    @State private var rain: Bool = false
    @State private var wind: Double?
    @State private var source: WeatherInput.Source = .manual
    @State private var locationName: String?
    @State private var isFetching = false
    @State private var fetchError: String?

    var body: some View {
        NavigationStack {
            ScreenScaffold {
                ScreenBlock(spacing: 20) {
                    ScreenHeader(title.lowercased(), subtitle: subtitle)

                    fetchSection

                    FieldFrame(label: "Temperature") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(UnitFormatter.temperature(temperature, units: units))
                                .font(TypeScale.bigNumber)
                                .foregroundStyle(Palette.anchor)
                            Slider(value: $temperature, in: -25...45, step: 1)
                                .tint(Palette.amber)
                                .onChange(of: temperature) { _, _ in markEditedByHand() }
                                .accessibilityValue(UnitFormatter.temperature(temperature, units: units))
                        }
                    }

                    WLToggleRow(title: "Rain Expected", isOn: $rain)
                        .onChange(of: rain) { _, _ in markEditedByHand() }

                    FieldFrame(label: "Wind", helpText: "Optional, in kilometres per hour.") {
                        WLNumberField(placeholder: "Not set", value: $wind, suffix: "km/h")
                    }

                    PrimaryButton(title: "Save Weather") {
                        onSave(
                            WeatherInput(
                                temperatureC: temperature,
                                rain: rain,
                                windKph: wind,
                                source: source,
                                locationName: locationName
                            )
                        )
                        dismiss()
                    }

                    if weather != nil {
                        SecondaryButton(title: "Clear Weather") {
                            onSave(nil)
                            dismiss()
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Palette.anchor)
                }
            }
            .toolbarBackground(Palette.background, for: .navigationBar)
        }
        .onAppear {
            if let weather {
                temperature = weather.temperatureC
                rain = weather.rain
                wind = weather.windKph
                source = weather.source
                locationName = weather.locationName
            }
        }
    }

    private var subtitle: String {
        source.isFetched
            ? "Fetched for this day. Change any value and it becomes your own."
            : "Entered by hand."
    }

    @ViewBuilder
    private var fetchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let onFetch {
                Button {
                    Task { await fetch(using: onFetch) }
                } label: {
                    HStack(spacing: 8) {
                        if isFetching {
                            ProgressView().tint(Palette.anchor)
                        } else {
                            Image(systemName: "cloud.sun.fill")
                        }
                        Text(isFetching ? "Fetching…" : "Get Current Weather")
                    }
                }
                .buttonStyle(SecondaryButtonStyle(isEnabled: !isFetching))
                .disabled(isFetching)

                if let locationName, source.isFetched {
                    InlineNotice(
                        text: "Last reading for \(locationName).",
                        icon: "mappin.and.ellipse",
                        colour: Palette.anchor.opacity(0.6)
                    )
                }
            } else if let reason = fetchUnavailableReason {
                InlineNotice(text: reason, icon: "info.circle")
            }

            if let fetchError {
                WarningPanel(message: fetchError, tint: Palette.danger)
            }
        }
    }

    private func fetch(using work: @escaping () async -> WeatherLookupOutcome) async {
        isFetching = true
        fetchError = nil
        let outcome = await work()
        isFetching = false

        switch outcome {
        case .fetched(let input):
            temperature = input.temperatureC
            rain = input.rain
            wind = input.windKph
            source = input.source
            locationName = input.locationName
        case .failed(let message):
            fetchError = message
        }
    }

    /// Touching the controls makes the reading the user's own again.
    private func markEditedByHand() {
        guard source.isFetched else { return }
        source = .manual
        locationName = nil
    }
}

// MARK: - Mark worn sheet

/// Confirming a wearing, with the option to send the pieces straight to the wash.
struct MarkWornSheet: View {
    let outfitName: String
    let pieceCount: Int
    let onConfirm: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sendToWash = false

    var body: some View {
        NavigationStack {
            ScreenScaffold {
                ScreenBlock(spacing: 20) {
                    ScreenHeader(
                        "mark as worn",
                        subtitle: "\(outfitName) · \(Plural.count(pieceCount, "piece")). This adds a wear record to every piece."
                    )

                    WLToggleRow(
                        title: "Send Pieces to the Wash",
                        subtitle: "They become unavailable until you return them, and their outfits say so.",
                        isOn: $sendToWash
                    )

                    PrimaryButton(title: "Confirm") {
                        onConfirm(sendToWash)
                    }
                    SecondaryButton(title: "Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(400)])
    }
}
