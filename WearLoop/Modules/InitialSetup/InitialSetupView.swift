//
//  InitialSetupView.swift
//  WearLoop
//

import SwiftUI

struct InitialSetupView: View {
    @StateObject var presenter: InitialSetupPresenter

    var body: some View {
        ScreenScaffold(bottomInset: 40) {
            ScreenBlock(spacing: 10) {
                ScreenHeader(
                    presenter.viewState.isEditing ? "wardrobe setup" : "set up your wardrobe",
                    subtitle: presenter.viewState.isEditing
                        ? "Changing these does not recalculate finished trips or wear records."
                        : "These few answers let the app check outfits against the season and the occasion."
                )
            }

            ScreenBlock(spacing: 22) {
                nameField
                climateField
                seasonsField
                occasionsField
                laundryField
                unitsField

                if let error = presenter.viewState.saveError {
                    ErrorStateView(
                        title: "could not save",
                        message: error,
                        retryTitle: "Try Again"
                    ) {
                        presenter.didTapSave()
                    }
                }

                PrimaryButton(
                    title: "Save Setup",
                    isEnabled: presenter.viewState.canSave,
                    isBusy: presenter.viewState.isSaving
                ) {
                    presenter.didTapSave()
                }

                if !presenter.viewState.canSave && !presenter.viewState.isSaving {
                    Text("Choose at least one season and one occasion to continue.")
                        .font(TypeScale.captionSmall)
                        .foregroundStyle(Palette.anchor.opacity(0.6))
                }
            }
        }
        .onAppear { presenter.onAppear() }
    }

    // MARK: Fields

    private var nameField: some View {
        FieldFrame(label: "Your Display Name", helpText: "Only used to greet you on the home screen.") {
            WLTextField(
                placeholder: "Optional",
                text: Binding(
                    get: { presenter.viewState.displayName },
                    set: { presenter.viewState.displayName = $0 }
                ),
                capitalization: .words
            )
        }
    }

    private var climateField: some View {
        FieldFrame(label: "Home Climate", helpText: "Used as a sanity check when an outfit's range looks unusual.") {
            ChipGroup(
                values: HomeClimate.allCases,
                title: { $0.title },
                accent: Palette.anchor,
                isSelected: { $0 == presenter.viewState.homeClimate },
                onTap: { presenter.setClimate($0) }
            )
        }
    }

    private var seasonsField: some View {
        FieldFrame(
            label: "Seasons You Dress For",
            isRequired: true,
            errorMessage: presenter.viewState.seasonError
        ) {
            ChipGroup(
                values: Season.allCases,
                title: { $0.title },
                accent: Palette.amber,
                isSelected: { presenter.viewState.seasons.contains($0) },
                onTap: { presenter.toggleSeason($0) }
            )
        }
    }

    private var occasionsField: some View {
        FieldFrame(
            label: "Usual Occasions",
            isRequired: true,
            errorMessage: presenter.viewState.occasionError
        ) {
            ChipGroup(
                values: Occasion.allCases,
                title: { $0.title },
                accent: Palette.berry,
                isSelected: { presenter.viewState.occasions.contains($0) },
                onTap: { presenter.toggleOccasion($0) }
            )
        }
    }

    private var laundryField: some View {
        FieldFrame(
            label: "Laundry Cycle Length",
            helpText: "Sets the date a piece is expected back from the wash."
        ) {
            ChipGroup(
                values: LaundryCycle.allCases,
                title: { $0.title },
                accent: Palette.anchor,
                isSelected: { $0 == presenter.viewState.laundryCycle },
                onTap: { presenter.setCycle($0) }
            )
        }
    }

    private var unitsField: some View {
        FieldFrame(label: "Measurement Units") {
            ChipGroup(
                values: MeasurementUnits.allCases,
                title: { $0.title },
                accent: Palette.anchor,
                isSelected: { $0 == presenter.viewState.units },
                onTap: { presenter.setUnits($0) }
            )
        }
    }
}
