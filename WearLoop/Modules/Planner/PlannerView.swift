//
//  PlannerView.swift
//  WearLoop
//

import SwiftUI

struct PlannerView: View {
    @StateObject var presenter: PlannerPresenter
    @State private var notesDraft: String = ""

    var body: some View {
        ScreenScaffold {
            ScreenBlock(spacing: 10) {
                ScreenHeader("plan a day", subtitle: "Two weeks ahead. Assigning is not the same as wearing.")
            }

            calendar
            dayCard
            occasionSection
            weatherSection
            outfitSection
            notesSection
            wornSection
        }
        .sheet(isPresented: $presenter.isOutfitPickerPresented) {
            OutfitPickerSheet(
                title: "assign outfit",
                subtitle: "Ranked by this day's weather and occasion.",
                candidates: presenter.candidates,
                onPick: { presenter.didPickOutfit($0, isBackup: false) },
                onBuild: { presenter.didTapBuildOutfit() }
            )
        }
        .sheet(isPresented: $presenter.isBackupPickerPresented) {
            OutfitPickerSheet(
                title: "backup outfit",
                subtitle: "A second choice if the plan changes.",
                candidates: presenter.candidates,
                onPick: { presenter.didPickOutfit($0, isBackup: true) },
                onBuild: { presenter.didTapBuildOutfit() }
            )
        }
        .sheet(isPresented: $presenter.isWeatherPresented) {
            WeatherInputSheet(
                weather: presenter.viewState.weather,
                units: presenter.viewState.units,
                title: "Expected Weather",
                onFetch: presenter.canFetchWeather ? { await presenter.fetchWeatherForSelectedDay() } : nil,
                fetchUnavailableReason: presenter.weatherFetchUnavailableReason
            ) { presenter.didSaveWeather($0) }
        }
        .sheet(isPresented: $presenter.isMarkWornPresented) {
            MarkWornSheet(
                outfitName: presenter.viewState.assignedOutfit?.name ?? "",
                pieceCount: presenter.viewState.assignedPieces.count
            ) { presenter.didConfirmMarkWorn(sendToWash: $0) }
        }
        .toast($presenter.toast)
        .confirm($presenter.confirm)
        .onAppear {
            presenter.onAppear()
            notesDraft = presenter.viewState.notes
        }
        .onChange(of: presenter.selectedDate) { _, _ in
            notesDraft = presenter.viewState.notes
        }
    }

    // MARK: Calendar

    private var calendar: some View {
        WearCalendarStrip(
            days: presenter.viewState.days,
            onTapDay: { presenter.didSelectDay($0) },
            selectedDate: presenter.viewState.selectedDate
        )
    }

    private var dayCard: some View {
        ScreenBlock(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(presenter.viewState.selectedDayTitle)
                Spacer(minLength: 8)
                Text(presenter.viewState.selectedDaySubtitle)
                    .font(TypeScale.caption)
                    .monospacedDigit()
                    .foregroundStyle(Palette.anchor.opacity(0.55))
            }
            if let event = presenter.viewState.eventName {
                InlineNotice(text: "Event this day: \(event)", icon: "star.fill", colour: Palette.berry)
                TextButton(title: "Open events") { presenter.didTapEvents() }
            }
            if presenter.viewState.isPast && !presenter.viewState.isWorn {
                InlineNotice(text: "This day has already passed. You can still record what you wore.", icon: "clock.arrow.circlepath")
            }
        }
    }

    // MARK: Occasion

    private var occasionSection: some View {
        ScreenBlock(spacing: 10) {
            SectionHeader("occasion of the day")
            ChipGroup(
                values: Occasion.allCases,
                title: { $0.title },
                accent: Palette.berry,
                isSelected: { $0 == presenter.viewState.occasion },
                onTap: { occasion in
                    presenter.didSetOccasion(presenter.viewState.occasion == occasion ? nil : occasion)
                }
            )
        }
    }

    // MARK: Weather

    private var weatherSection: some View {
        ScreenBlock(spacing: 10) {
            SectionHeader("expected weather") {
                Button(presenter.viewState.weather == nil ? "Add" : "Edit") {
                    presenter.didTapWeather()
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
                InlineNotice(text: "No weather entered for this day.", icon: "cloud")
            }
        }
    }

    // MARK: Outfit

    private var outfitSection: some View {
        ScreenBlock(spacing: 12) {
            SectionHeader("assigned outfit")

            if !presenter.viewState.hasOutfits {
                EmptyStateView(
                    title: "no outfits to assign",
                    message: "Build an outfit first — days are planned with outfits, not single pieces.",
                    actionTitle: "Build First Outfit",
                    action: { presenter.didTapBuildOutfit() },
                    showHalftone: presenter.viewState.showHalftone
                )
            } else if let outfit = presenter.viewState.assignedOutfit {
                Button {
                    presenter.didTapOutfit(outfit.id)
                } label: {
                    OutfitFlatLay(
                        pieces: presenter.viewState.assignedPieces.map { ($0, $0.category.naturalLayer) },
                        showHalftone: presenter.viewState.showHalftone,
                        height: 230
                    )
                }
                .buttonStyle(CardPressStyle())
                .accessibilityLabel("\(outfit.name). Opens the outfit.")

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(outfit.name)
                            .font(TypeScale.bodyBold)
                            .foregroundStyle(Palette.anchor)
                        Text("\(outfit.occasion.title) · \(outfit.temperatureText)")
                            .font(TypeScale.captionSmall)
                            .foregroundStyle(Palette.anchor.opacity(0.6))
                    }
                    Spacer(minLength: 8)
                    if let status = presenter.viewState.assignedStatus, status != .ready {
                        StatusTag(text: status.tagText, fill: status.tagFill, textColour: status.tagTextColour)
                    }
                }

                if let note = presenter.viewState.availabilityNote {
                    WarningPanel(message: note, tint: Palette.berry)
                }

                if presenter.showsWeatherWarning {
                    if let mismatch = presenter.viewState.weatherMismatch {
                        WarningPanel(
                            message: mismatch,
                            primaryTitle: "Choose Another Outfit",
                            primaryAction: { presenter.didTapAssign() },
                            secondaryTitle: "Keep Anyway",
                            secondaryAction: { presenter.didTapKeepAnyway() }
                        )
                    }
                    if let rain = presenter.viewState.rainWarning {
                        WarningPanel(
                            message: rain,
                            primaryTitle: "Choose Another Outfit",
                            primaryAction: { presenter.didTapAssign() },
                            secondaryTitle: "Keep Anyway",
                            secondaryAction: { presenter.didTapKeepAnyway() },
                            tint: Palette.berry
                        )
                    }
                }

                HStack(spacing: 10) {
                    SecondaryButton(title: "Change") { presenter.didTapAssign() }
                    SecondaryButton(title: "Clear") { presenter.didTapClearAssignment() }
                }

                if let backup = presenter.viewState.backupOutfit {
                    FactRow(label: "Backup Outfit", value: backup.name)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.surface))
                    TextButton(title: "Change backup") { presenter.didTapAssignBackup() }
                } else {
                    SecondaryButton(title: "Add a Backup Outfit") { presenter.didTapAssignBackup() }
                }
            } else {
                EmptyStateView(
                    title: "nothing planned",
                    message: "Assign an outfit and the app checks it against this day's weather and occasion.",
                    actionTitle: "Assign Outfit",
                    action: { presenter.didTapAssign() },
                    showHalftone: presenter.viewState.showHalftone
                )
            }
        }
    }

    // MARK: Notes

    private var notesSection: some View {
        ScreenBlock(spacing: 10) {
            SectionHeader("notes")
            WLTextEditor(placeholder: "Anything about this day", text: $notesDraft, minHeight: 84)
                .onChange(of: notesDraft) { _, newValue in
                    presenter.didEditNotes(newValue)
                }
        }
    }

    // MARK: Worn

    @ViewBuilder
    private var wornSection: some View {
        if presenter.viewState.assignedOutfit != nil {
            ScreenBlock(spacing: 10) {
                SectionHeader("record")
                if presenter.viewState.isWorn {
                    InlineNotice(
                        text: "Marked as worn. Every piece has a wear record for this day.",
                        icon: "checkmark.circle.fill",
                        colour: Palette.success
                    )
                    SecondaryButton(title: "Remove This Wear Record") { presenter.didTapUndoWorn() }
                } else {
                    Text("An assigned outfit is not counted as worn. Confirm it here when you actually put it on.")
                        .font(TypeScale.captionSmall)
                        .foregroundStyle(Palette.anchor.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                    PrimaryButton(title: "Mark as Worn") { presenter.didTapMarkWorn() }
                }
            }
        }
    }
}

// MARK: - Outfit picker

/// Shared picker used by the planner, events and trip days.
struct OutfitPickerSheet: View {
    let title: String
    var subtitle: String?
    let candidates: [OutfitListItem]
    let onPick: (UUID) -> Void
    var onBuild: (() -> Void)?
    /// Hides outfits that cannot be used, for pickers that require availability.
    var availableOnly: Bool = false

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [OutfitListItem] {
        var result = candidates
        if availableOnly {
            result = result.filter { $0.status == .ready }
        }
        guard !search.wlIsBlank else { return result }
        let needle = search.wlTrimmed.lowercased()
        return result.filter {
            $0.outfit.name.lowercased().contains(needle)
                || $0.outfit.occasion.title.lowercased().contains(needle)
        }
    }

    var body: some View {
        NavigationStack {
            ScreenScaffold {
                ScreenBlock(spacing: 10) {
                    ScreenHeader(title, subtitle: subtitle)
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Palette.anchor.opacity(0.45))
                        TextField("Search outfits", text: $search)
                            .font(TypeScale.body)
                            .foregroundStyle(Palette.anchor)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.surface))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Palette.anchor.opacity(0.2), lineWidth: 2)
                    )
                }

                if filtered.isEmpty {
                    ScreenBlock {
                        EmptyStateView(
                            title: candidates.isEmpty ? "no outfits yet" : "nothing matches",
                            message: candidates.isEmpty
                                ? "Build an outfit and it becomes available here."
                                : "No outfit matches that search.",
                            actionTitle: candidates.isEmpty ? "Build an Outfit" : nil,
                            action: candidates.isEmpty ? { onBuild?(); dismiss() } : nil
                        )
                    }
                } else {
                    ScreenBlock(spacing: 12) {
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: Metrics.cardGap),
                                      GridItem(.flexible(), spacing: Metrics.cardGap)],
                            spacing: Metrics.cardGap
                        ) {
                            ForEach(filtered) { item in
                                OutfitCard(
                                    outfit: item.outfit,
                                    pieces: item.pieces,
                                    status: item.status,
                                    subtitle: item.subtitle,
                                    height: 200,
                                    width: nil,
                                    isDimmed: item.status != .ready
                                ) {
                                    onPick(item.outfit.id)
                                    dismiss()
                                }
                            }
                        }
                        if !availableOnly {
                            Text("An outfit with a piece in the wash can still be assigned — it will show the return date until the piece is back.")
                                .font(TypeScale.captionSmall)
                                .foregroundStyle(Palette.anchor.opacity(0.55))
                                .fixedSize(horizontal: false, vertical: true)
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
        }
    }
}
