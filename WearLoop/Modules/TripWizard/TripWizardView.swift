//
//  TripWizardView.swift
//  WearLoop
//

import SwiftUI

struct TripWizardView: View {
    @StateObject var presenter: TripWizardPresenter

    var body: some View {
        ScreenScaffold(bottomInset: 40) {
            ScreenBlock(spacing: 10) {
                ScreenHeader(presenter.viewState.stepTitle, subtitle: presenter.viewState.stepSubtitle)
            }

            stepIndicator

            Group {
                switch presenter.viewState.step {
                case 1: stepBasics
                case 2: stepDays
                case 3: stepConditions
                case 4: stepLuggage
                default: stepReview
                }
            }

            controls
        }
        .toast($presenter.toast)
        .onAppear { presenter.onAppear() }
    }

    // MARK: Step indicator

    private var stepIndicator: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(1...presenter.viewState.totalSteps, id: \.self) { step in
                    let isCurrent = step == presenter.viewState.step
                    let isDone = step < presenter.viewState.step
                    Button {
                        presenter.didSelectStep(step)
                    } label: {
                        HStack(spacing: 5) {
                            if isDone {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .black))
                            }
                            Text(stepName(step))
                                .font(TypeScale.captionSmall)
                                .lineLimit(1)
                        }
                        .foregroundStyle(isCurrent ? Palette.onAnchor : Palette.anchor.opacity(isDone ? 1 : 0.45))
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(
                            Capsule().fill(
                                isCurrent ? Palette.berry : (isDone ? Palette.amber.opacity(0.35) : Palette.surface)
                            )
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(step > presenter.viewState.step)
                    .accessibilityLabel("Step \(step), \(stepName(step))")
                    .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)

                    if step < presenter.viewState.totalSteps {
                        Rectangle()
                            .fill(Palette.anchor.opacity(0.2))
                            .frame(width: 10, height: 2)
                    }
                }
            }
            .padding(.horizontal, Metrics.screenPadding)
        }
    }

    private func stepName(_ step: Int) -> String {
        switch step {
        case 1: return "Basics"
        case 2: return "Days"
        case 3: return "Conditions"
        case 4: return "Luggage"
        default: return "Review"
        }
    }

    // MARK: Step 1

    private var stepBasics: some View {
        ScreenBlock(spacing: 22) {
            FieldFrame(label: "Trip Name", isRequired: true, errorMessage: presenter.viewState.nameError) {
                WLTextField(
                    placeholder: "Berlin in March",
                    text: Binding(
                        get: { presenter.viewState.name },
                        set: { presenter.setName($0) }
                    ),
                    hasError: presenter.viewState.nameError != nil,
                    capitalization: .words
                )
            }

            FieldFrame(label: "Destination") {
                WLTextField(
                    placeholder: "Where you are going",
                    text: Binding(
                        get: { presenter.viewState.destination },
                        set: { presenter.viewState.destination = $0 }
                    ),
                    capitalization: .words
                )
            }

            FieldFrame(label: "Dates", errorMessage: presenter.viewState.dateError) {
                VStack(spacing: 10) {
                    WLDateRow(
                        label: "Start Date",
                        date: Binding(
                            get: { presenter.viewState.startDate },
                            set: { presenter.setStartDate($0) }
                        )
                    )
                    WLDateRow(
                        label: "End Date",
                        date: Binding(
                            get: { presenter.viewState.endDate },
                            set: { presenter.setEndDate($0) }
                        )
                    )
                    InlineNotice(
                        text: "\(Plural.count(presenter.viewState.dayCount, "day")) in this trip.",
                        icon: "calendar"
                    )
                }
            }

            FieldFrame(label: "Trip Type") {
                ChipGroup(
                    values: TripType.allCases,
                    title: { $0.title },
                    accent: Palette.berry,
                    isSelected: { $0 == presenter.viewState.type },
                    onTap: { presenter.setType($0) }
                )
            }
        }
    }

    // MARK: Step 2

    private var stepDays: some View {
        VStack(alignment: .leading, spacing: 18) {
            ScreenBlock(spacing: 10) {
                if presenter.viewState.days.isEmpty {
                    InlineNotice(text: "Set the dates first and the days appear here.", icon: "calendar")
                } else {
                    HStack(spacing: 8) {
                        Text("Apply to every day")
                            .font(TypeScale.captionSmall)
                            .foregroundStyle(Palette.anchor.opacity(0.6))
                        Spacer(minLength: 0)
                    }
                    WrappingHStack {
                        ForEach(TripDayOccasion.allCases) { occasion in
                            ChipView(title: occasion.title, isSelected: false) {
                                presenter.applyToAllDays([occasion])
                            }
                        }
                    }
                }
            }

            ForEach(Array(presenter.viewState.days.enumerated()), id: \.element.id) { index, day in
                dayCard(index: index, day: day)
            }
        }
    }

    private func dayCard(index: Int, day: TripDay) -> some View {
        ScreenBlock(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Day \(day.dayNumber)")
                    .font(TypeScale.bodyBold)
                    .foregroundStyle(Palette.anchor)
                Text(DateFormatterCache.dayMonth.string(from: day.date))
                    .font(TypeScale.captionSmall)
                    .foregroundStyle(Palette.anchor.opacity(0.55))
                Spacer(minLength: 8)
                if index > 0 {
                    Button("Copy Previous") { presenter.copyPreviousDay(to: index) }
                        .buttonStyle(CompactOutlineButtonStyle())
                }
                if !day.occasions.isEmpty {
                    Button {
                        presenter.clearDay(index)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(CompactOutlineButtonStyle())
                    .accessibilityLabel("Clear day \(day.dayNumber)")
                }
            }

            ChipGroup(
                values: TripDayOccasion.allCases,
                title: { $0.title },
                accent: Palette.amber,
                isSelected: { day.occasions.contains($0) },
                onTap: { presenter.toggleOccasion($0, dayIndex: index) }
            )

            if day.occasions.isEmpty {
                Text("No occasion set. You can still plan an outfit for this day.")
                    .font(TypeScale.captionSmall)
                    .foregroundStyle(Palette.anchor.opacity(0.5))
            }
        }
        .padding(.vertical, 10)
        .background(
            Rectangle()
                .fill(index.isMultiple(of: 2) ? Color.clear : Palette.surface.opacity(0.5))
        )
    }

    // MARK: Step 3

    private var stepConditions: some View {
        ScreenBlock(spacing: 22) {
            FieldFrame(
                label: "Expected Temperature Range",
                helpText: "Outfits outside this range are flagged, not removed."
            ) {
                TemperatureRangeControl(
                    minValue: Binding(
                        get: { presenter.viewState.temperatureMin },
                        set: { presenter.setTemperature(min: $0, max: presenter.viewState.temperatureMax) }
                    ),
                    maxValue: Binding(
                        get: { presenter.viewState.temperatureMax },
                        set: { presenter.setTemperature(min: presenter.viewState.temperatureMin, max: $0) }
                    ),
                    units: presenter.viewState.units
                )
            }

            WLToggleRow(
                title: "Rain Expected",
                subtitle: "Days without an outer layer get a warning.",
                isOn: Binding(
                    get: { presenter.viewState.rainExpected },
                    set: { presenter.viewState.rainExpected = $0 }
                )
            )

            WLToggleRow(
                title: "Laundry Available",
                subtitle: "When you can wash on the road, fewer pieces are needed.",
                isOn: Binding(
                    get: { presenter.viewState.laundryAvailable },
                    set: { presenter.viewState.laundryAvailable = $0 }
                )
            )

            FieldFrame(label: "Dress Code Notes") {
                WLTextEditor(
                    placeholder: "Anything the trip requires you to wear",
                    text: Binding(
                        get: { presenter.viewState.dressCodeNotes },
                        set: { presenter.viewState.dressCodeNotes = $0 }
                    ),
                    minHeight: 84
                )
            }
        }
    }

    // MARK: Step 4

    private var stepLuggage: some View {
        ScreenBlock(spacing: 22) {
            FieldFrame(label: "Luggage Type") {
                ChipGroup(
                    values: LuggageType.allCases,
                    title: { $0.title },
                    accent: Palette.berry,
                    isSelected: { $0 == presenter.viewState.luggageType },
                    onTap: { presenter.setLuggageType($0) }
                )
            }

            if presenter.viewState.luggageType.allowsLimit {
                FieldFrame(
                    label: "Weight Limit",
                    isRequired: true,
                    errorMessage: presenter.viewState.limitError,
                    helpText: "The gauge turns red the moment the bag goes over this."
                ) {
                    WLNumberField(
                        placeholder: "8",
                        value: Binding(
                            get: { presenter.viewState.weightLimitKg },
                            set: { presenter.viewState.weightLimitKg = $0; presenter.viewState.limitError = nil }
                        ),
                        suffix: presenter.viewState.units == .metric ? "kg" : "kg (entered)",
                        hasError: presenter.viewState.limitError != nil
                    )
                }
            } else {
                InlineNotice(
                    text: "With no limit the bag is still weighed, but nothing is ever flagged as too heavy.",
                    icon: "info.circle"
                )
            }

            FieldFrame(label: "Volume Notes") {
                WLTextEditor(
                    placeholder: "Bag size, anything bulky you already know about",
                    text: Binding(
                        get: { presenter.viewState.volumeNotes },
                        set: { presenter.viewState.volumeNotes = $0 }
                    ),
                    minHeight: 84
                )
            }
        }
    }

    // MARK: Step 5

    private var stepReview: some View {
        ScreenBlock(spacing: 16) {
            Panel {
                FactRow(label: "Trip", value: presenter.viewState.name.wlIsBlank ? "Not named" : presenter.viewState.name)
                Divider().overlay(Palette.anchor.opacity(0.1))
                FactRow(
                    label: "Dates",
                    value: DateFormatterCache.rangeText(presenter.viewState.startDate, presenter.viewState.endDate)
                )
                Divider().overlay(Palette.anchor.opacity(0.1))
                FactRow(label: "Days", value: Plural.count(presenter.viewState.dayCount, "day"))
                Divider().overlay(Palette.anchor.opacity(0.1))
                FactRow(label: "Type", value: presenter.viewState.type.title)
                Divider().overlay(Palette.anchor.opacity(0.1))
                FactRow(
                    label: "Conditions",
                    value: UnitFormatter.temperatureRange(
                        presenter.viewState.temperatureMin,
                        presenter.viewState.temperatureMax,
                        units: presenter.viewState.units
                    ) + (presenter.viewState.rainExpected ? ", rain" : "")
                )
                Divider().overlay(Palette.anchor.opacity(0.1))
                FactRow(
                    label: "Luggage",
                    value: presenter.viewState.luggageType.allowsLimit
                        ? "\(presenter.viewState.luggageType.title) · \(UnitFormatter.limit(kg: presenter.viewState.weightLimitKg ?? 0, units: presenter.viewState.units))"
                        : presenter.viewState.luggageType.title
                )
            }

            if presenter.viewState.name.wlIsBlank {
                WarningPanel(
                    message: "This trip has no name yet.",
                    primaryTitle: "Go to Basics",
                    primaryAction: { presenter.didSelectStep(1) }
                )
            }

            if !presenter.viewState.daysWithoutOccasion.isEmpty {
                WarningPanel(
                    message: "\(Plural.days(presenter.viewState.daysWithoutOccasion.map(\.dayNumber))) have no occasion. You can still plan them, but the app has less to go on.",
                    primaryTitle: "Go to Days",
                    primaryAction: { presenter.didSelectStep(2) },
                    tint: Palette.berry
                )
            }

            if !presenter.viewState.hasOutfits {
                WarningPanel(
                    message: "You have no outfits yet. The packing list is built from outfits, so build at least one before packing.",
                    tint: Palette.berry
                )
            }

            if presenter.viewState.daysWithoutOccasion.isEmpty && !presenter.viewState.name.wlIsBlank {
                InlineNotice(
                    text: "Everything is filled in. Creating the trip opens its workspace.",
                    icon: "checkmark.circle.fill",
                    colour: Palette.success
                )
            }

            if let error = presenter.viewState.saveError {
                WarningPanel(message: error, tint: Palette.danger)
            }
        }
    }

    // MARK: Controls

    private var controls: some View {
        ScreenBlock(spacing: 10) {
            if presenter.viewState.step == presenter.viewState.totalSteps {
                PrimaryButton(
                    title: presenter.viewState.isEditingExisting ? "Save Trip" : "Create Trip",
                    isEnabled: !presenter.viewState.didFinish,
                    isBusy: presenter.viewState.isSaving
                ) {
                    presenter.didTapCreate()
                }
            } else {
                PrimaryButton(title: "Continue", isEnabled: presenter.canContinue()) {
                    presenter.didTapContinue()
                }
            }

            HStack(spacing: 10) {
                SecondaryButton(title: presenter.viewState.step == 1 ? "Cancel" : "Back") {
                    presenter.didTapBack()
                }
                SecondaryButton(title: "Save as Draft") {
                    presenter.didTapSaveDraft()
                }
            }
        }
    }
}
