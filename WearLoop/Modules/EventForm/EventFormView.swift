//
//  EventFormView.swift
//  WearLoop
//

import SwiftUI

struct EventFormView: View {
    @StateObject var presenter: EventFormPresenter

    var body: some View {
        ScreenScaffold(bottomInset: 40) {
            ScreenBlock(spacing: 10) {
                ScreenHeader(
                    presenter.viewState.title,
                    subtitle: "The app checks the outfit against the dress code and tells you if you have worn it before."
                )
            }

            detailsSection
            outfitSection
            notesSection
            saveSection
        }
        .sheet(isPresented: $presenter.isOutfitPickerPresented) {
            OutfitPickerSheet(
                title: "assign outfit",
                subtitle: "Ranked against the dress code and the occasion.",
                candidates: presenter.candidates,
                onPick: { presenter.didPickOutfit($0, isBackup: false) },
                onBuild: { presenter.didTapBuildOutfit() }
            )
        }
        .sheet(isPresented: $presenter.isBackupPickerPresented) {
            OutfitPickerSheet(
                title: "backup outfit",
                subtitle: "A second choice, in case the first is unavailable.",
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
                onFetch: presenter.canFetchWeather ? { await presenter.fetchWeatherForEvent() } : nil,
                fetchUnavailableReason: presenter.weatherFetchUnavailableReason
            ) { presenter.didSaveWeather($0) }
        }
        .sheet(isPresented: $presenter.isMarkWornPresented) {
            MarkWornSheet(
                outfitName: presenter.viewState.outfitName ?? "",
                pieceCount: presenter.viewState.outfitPieces.count
            ) { presenter.didConfirmMarkWorn(sendToWash: $0) }
        }
        .toast($presenter.toast)
        .confirm($presenter.confirm)
        .onAppear { presenter.onAppear() }
    }

    // MARK: Details

    private var detailsSection: some View {
        ScreenBlock(spacing: 22) {
            FieldFrame(label: "Event Name", isRequired: true, errorMessage: presenter.viewState.nameError) {
                WLTextField(
                    placeholder: "Anna's wedding",
                    text: Binding(
                        get: { presenter.viewState.name },
                        set: { presenter.setName($0) }
                    ),
                    hasError: presenter.viewState.nameError != nil,
                    capitalization: .words
                )
            }

            FieldFrame(label: "Date") {
                WLDateRow(
                    label: "Event date",
                    date: Binding(
                        get: { presenter.viewState.date },
                        set: { presenter.setDate($0) }
                    )
                )
            }

            FieldFrame(label: "Occasion") {
                ChipGroup(
                    values: Occasion.allCases,
                    title: { $0.title },
                    accent: Palette.berry,
                    isSelected: { $0 == presenter.viewState.occasion },
                    onTap: { presenter.setOccasion($0) }
                )
            }

            FieldFrame(
                label: "Dress Code",
                helpText: presenter.viewState.dressCode == .themed
                    ? "A themed dress code is not ranked, so no formality check is made."
                    : nil
            ) {
                ChipGroup(
                    values: DressCode.allCases,
                    title: { $0.title },
                    accent: Palette.anchor,
                    isSelected: { $0 == presenter.viewState.dressCode },
                    onTap: { presenter.setDressCode($0) }
                )
            }

            FieldFrame(label: "Location") {
                WLTextField(
                    placeholder: "Where it is",
                    text: Binding(
                        get: { presenter.viewState.location },
                        set: { presenter.viewState.location = $0 }
                    ),
                    capitalization: .words
                )
            }

            FieldFrame(label: "Weather") {
                VStack(alignment: .leading, spacing: 8) {
                    if let text = presenter.viewState.weatherText {
                        Panel {
                            Text(text)
                                .font(TypeScale.bodyBold)
                                .foregroundStyle(Palette.anchor)
                        }
                    }
                    SecondaryButton(
                        title: presenter.viewState.weather == nil ? "Add Weather" : "Edit Weather"
                    ) {
                        presenter.didTapWeather()
                    }
                }
            }
        }
    }

    // MARK: Outfit

    private var outfitSection: some View {
        ScreenBlock(spacing: 12) {
            SectionHeader("assigned outfit", accent: Palette.berry)

            if !presenter.viewState.hasOutfits {
                EmptyStateView(
                    title: "no outfits yet",
                    message: "Events are planned with outfits. Build one first.",
                    actionTitle: "Build an Outfit",
                    action: { presenter.didTapBuildOutfit() },
                    showHalftone: presenter.viewState.showHalftone
                )
            } else if let name = presenter.viewState.outfitName {
                Button {
                    presenter.didTapOpenOutfit()
                } label: {
                    OutfitFlatLay(
                        pieces: presenter.viewState.outfitPieces.map { ($0, $0.category.naturalLayer) },
                        showHalftone: presenter.viewState.showHalftone,
                        height: 230
                    )
                }
                .buttonStyle(CardPressStyle())
                .accessibilityLabel("\(name). Opens the outfit.")

                HStack(alignment: .top) {
                    Text(name)
                        .font(TypeScale.bodyBold)
                        .foregroundStyle(Palette.anchor)
                    Spacer(minLength: 8)
                    if let status = presenter.viewState.outfitStatus, status != .ready {
                        StatusTag(text: status.tagText, fill: status.tagFill, textColour: status.tagTextColour)
                    }
                }

                warnings

                HStack(spacing: 10) {
                    SecondaryButton(title: "Change") { presenter.didTapAssign() }
                    SecondaryButton(title: "Clear") { presenter.didTapClearOutfit() }
                }

                if let backup = presenter.viewState.backupName {
                    FactRow(label: "Backup Outfit", value: backup)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.surface))
                    TextButton(title: "Change backup") { presenter.didTapAssignBackup() }
                } else {
                    SecondaryButton(title: "Add a Backup Outfit") { presenter.didTapAssignBackup() }
                }

                wornControls
            } else {
                EmptyStateView(
                    title: "no outfit yet",
                    message: "Assign one and the app checks it against the \(presenter.viewState.dressCode.title.lowercased()) dress code.",
                    actionTitle: "Assign Outfit",
                    action: { presenter.didTapAssign() },
                    showHalftone: presenter.viewState.showHalftone
                )
            }
        }
    }

    @ViewBuilder
    private var warnings: some View {
        if let repeatWarning = presenter.viewState.repeatWarning {
            InlineNotice(text: repeatWarning, icon: "clock.arrow.circlepath", colour: Palette.berry)
        }
        if let availability = presenter.viewState.availabilityWarning {
            WarningPanel(message: availability, tint: Palette.berry)
        }
        if !presenter.didDismissWarnings {
            if let formality = presenter.viewState.formalityWarning {
                WarningPanel(
                    message: formality,
                    primaryTitle: "Choose Another Outfit",
                    primaryAction: { presenter.didTapAssign() },
                    secondaryTitle: "Keep Anyway",
                    secondaryAction: { presenter.didTapKeepAnyway() }
                )
            }
            if let weather = presenter.viewState.weatherWarning {
                WarningPanel(
                    message: weather,
                    primaryTitle: "Choose Another Outfit",
                    primaryAction: { presenter.didTapAssign() },
                    secondaryTitle: "Keep Anyway",
                    secondaryAction: { presenter.didTapKeepAnyway() },
                    tint: Palette.amber
                )
            }
        }
    }

    @ViewBuilder
    private var wornControls: some View {
        if presenter.viewState.isWorn {
            InlineNotice(
                text: "Recorded as worn at this event.",
                icon: "checkmark.circle.fill",
                colour: Palette.success
            )
            SecondaryButton(title: "Remove This Wear Record") { presenter.didTapUndoWorn() }
        } else {
            PrimaryButton(title: "Mark as Worn") { presenter.didTapMarkWorn() }
            Text("Only confirm this once you have actually worn it. Nothing is counted automatically.")
                .font(TypeScale.captionSmall)
                .foregroundStyle(Palette.anchor.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Notes

    private var notesSection: some View {
        ScreenBlock(spacing: 10) {
            SectionHeader("notes")
            WLTextEditor(
                placeholder: "Anything about this event",
                text: Binding(
                    get: { presenter.viewState.notes },
                    set: { presenter.viewState.notes = $0 }
                ),
                minHeight: 90
            )
        }
    }

    // MARK: Save

    private var saveSection: some View {
        ScreenBlock(spacing: 10) {
            if let error = presenter.viewState.saveError {
                WarningPanel(message: error, tint: Palette.danger)
            }
            PrimaryButton(
                title: presenter.viewState.isEditing ? "Save Event" : "Add Event",
                isEnabled: !presenter.viewState.didSave,
                isBusy: presenter.viewState.isSaving
            ) {
                presenter.didTapSave()
            }
            if presenter.viewState.isEditing {
                DangerButton(title: "Delete Event") { presenter.didTapDelete() }
            }
        }
    }
}
