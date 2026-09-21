//
//  TripModeView.swift
//  WearLoop
//
//  The dark screen. Photographs are never dimmed here either — only the surface
//  around them changes.
//

import SwiftUI

struct TripModeView: View {
    @StateObject var presenter: TripModePresenter
    @State private var hasAppeared = false

    var body: some View {
        Group {
            if let state = presenter.viewState {
                content(state)
            } else if presenter.isMissing {
                ScreenScaffold(isDark: true) {
                    ScreenBlock {
                        EmptyStateView(
                            title: "this trip is gone",
                            message: "It was deleted while trip mode was open.",
                            actionTitle: "Close",
                            action: { presenter.didTapClose() }
                        )
                    }
                }
            } else {
                ScreenScaffold(isDark: true) { LoadingStateView(message: "Opening trip mode…") }
            }
        }
        .toast($presenter.toast)
        .confirm($presenter.confirm)
        .sheet(isPresented: $presenter.isChangePlanPresented) {
            OutfitPickerSheet(
                title: "what did you wear?",
                subtitle: "Outfits whose pieces you packed come first.",
                candidates: presenter.candidates,
                onPick: { presenter.didPickActualOutfit($0) }
            )
        }
        .sheet(isPresented: $presenter.isUnplannedPresented) {
            SelectPiecesSheet(
                title: "add unplanned pieces",
                subtitle: "Anything you wore that was not in the plan.",
                pieces: presenter.packedPieces,
                confirmTitle: "Add to Today"
            ) { presenter.didAddUnplanned($0) }
        }
        .sheet(isPresented: $presenter.isLaundryPresented) {
            SelectPiecesSheet(
                title: "laundry on the road",
                subtitle: "These pieces go into the wash and out of rotation.",
                pieces: presenter.packedPieces,
                confirmTitle: "Start a Load"
            ) { presenter.didStartLaundry($0) }
        }
        .onAppear {
            presenter.onAppear()
            // Fade into the dark screen over 0.4 seconds.
            withAnimation(Motion.tripModeFade) { hasAppeared = true }
        }
    }

    private func content(_ state: TripModeViewState) -> some View {
        ZStack {
            (state.useDarkMode ? Palette.anchor : Palette.background)
                .ignoresSafeArea()
                .opacity(hasAppeared ? 1 : 0)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: Metrics.sectionGap) {
                    header(state)
                    dayStrip(state)
                    outfitSection(state)
                    recordSection(state)
                    extrasSection(state)
                    finishSection(state)
                }
                .padding(.bottom, 40)
            }
            .opacity(hasAppeared ? 1 : 0)
        }
        .wlDarkSurface(state.useDarkMode)
    }

    private var colours: SurfaceColours {
        SurfaceColours.forDark(presenter.viewState?.useDarkMode ?? true)
    }

    // MARK: Header

    private func header(_ state: TripModeViewState) -> some View {
        ScreenBlock(spacing: 10) {
            ScreenHeader(state.dayLabel, subtitle: "\(state.tripName) · \(state.dateText)") {
                Button {
                    presenter.didTapClose()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(
                    IconButtonStyle(
                        fill: state.useDarkMode ? Color.white.opacity(0.12) : Palette.surface,
                        iconColour: colours.text
                    )
                )
                .accessibilityLabel("Close trip mode")
            }
            if !state.occasionText.isEmpty {
                Text(state.occasionText)
                    .font(TypeScale.caption)
                    .foregroundStyle(colours.mutedText)
            }
        }
    }

    // MARK: Day strip

    private func dayStrip(_ state: TripModeViewState) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(state.allDays) { day in
                    Button {
                        presenter.didSelectDay(day.index)
                    } label: {
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(day.isLogged ? Palette.amber : (state.useDarkMode ? colours.card : Palette.surface))
                                if day.isCurrent {
                                    Circle().strokeBorder(Palette.burgundy, lineWidth: 3)
                                } else if day.isNotWorn {
                                    Circle().strokeBorder(colours.mutedText, lineWidth: 2)
                                }
                                Text("\(day.dayNumber)")
                                    .font(.system(size: 16, weight: .black).monospacedDigit())
                                    .foregroundStyle(day.isLogged ? Palette.anchor : colours.text)
                            }
                            .frame(width: Metrics.wearDayCircle, height: Metrics.wearDayCircle)
                            Circle()
                                .fill(day.hasPlan ? Palette.burgundy.opacity(0.8) : Color.clear)
                                .frame(width: 5, height: 5)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Day \(day.dayNumber)\(day.isLogged ? ", recorded" : "")\(day.isCurrent ? ", showing" : "")")
                }
            }
            .padding(.horizontal, Metrics.screenPadding)
        }
    }

    // MARK: Outfit

    @ViewBuilder
    private func outfitSection(_ state: TripModeViewState) -> some View {
        ScreenBlock(spacing: 12) {
            SectionHeader(state.isLogged ? "what you wore" : "today's outfit", accent: Palette.amber)

            let shown = state.isLogged ? state.wornPieces : state.plannedPieces
            let name = state.isLogged ? (state.wornOutfitName ?? "Pieces worn") : state.plannedOutfitName

            if shown.isEmpty {
                InlineNotice(
                    text: state.isNotWorn
                        ? "Nothing was worn on this day."
                        : "No outfit planned for this day. Record what you wore with Change of Plan.",
                    icon: "questionmark.circle"
                )
            } else {
                // Photographs keep their natural colour on the dark surface.
                OutfitFlatLay(
                    pieces: shown.map { ($0, $0.category.naturalLayer) },
                    showHalftone: false,
                    height: 260
                )
                if let name {
                    Text(name)
                        .font(TypeScale.bodyBold)
                        .foregroundStyle(colours.text)
                }
                if state.wasUnplanned {
                    InlineNotice(
                        text: "This differs from the plan. The difference is kept for the recap.",
                        icon: "arrow.triangle.branch",
                        colour: Palette.burgundy
                    )
                }
            }
        }
    }

    // MARK: Record

    private func recordSection(_ state: TripModeViewState) -> some View {
        ScreenBlock(spacing: 10) {
            if state.isLogged {
                InlineNotice(
                    text: "Recorded for day \(state.dayNumber).",
                    icon: "checkmark.circle.fill",
                    colour: Palette.success
                )
                SecondaryButton(
                    title: "Change of Plan",
                    textColour: colours.text,
                    strokeColour: colours.stroke,
                    fillColour: state.useDarkMode ? colours.card : Palette.surface
                ) {
                    presenter.didTapChangeOfPlan()
                }
                SecondaryButton(
                    title: "Clear This Record",
                    textColour: colours.text,
                    strokeColour: colours.stroke,
                    fillColour: state.useDarkMode ? colours.card : Palette.surface
                ) {
                    presenter.didTapClearRecord()
                }
            } else if state.isNotWorn {
                InlineNotice(text: "Marked as nothing worn on day \(state.dayNumber).", icon: "minus.circle")
                SecondaryButton(
                    title: "Record Something Instead",
                    textColour: colours.text,
                    strokeColour: colours.stroke,
                    fillColour: state.useDarkMode ? colours.card : Palette.surface
                ) {
                    presenter.didTapChangeOfPlan()
                }
            } else {
                PrimaryButton(
                    title: state.plannedOutfitID == nil ? "Record What You Wore" : "Mark as Worn"
                ) {
                    presenter.didTapMarkWorn()
                }
                HStack(spacing: 10) {
                    SecondaryButton(
                        title: "Change of Plan",
                        textColour: colours.text,
                        strokeColour: colours.stroke,
                        fillColour: state.useDarkMode ? colours.card : Palette.surface
                    ) {
                        presenter.didTapChangeOfPlan()
                    }
                    SecondaryButton(
                        title: "Not Worn",
                        textColour: colours.text,
                        strokeColour: colours.stroke,
                        fillColour: state.useDarkMode ? colours.card : Palette.surface
                    ) {
                        presenter.didTapNotWornToday()
                    }
                }
            }
        }
    }

    // MARK: Extras

    private func extrasSection(_ state: TripModeViewState) -> some View {
        ScreenBlock(spacing: 10) {
            SectionHeader("on the road", accent: Palette.burgundy)

            SecondaryButton(
                title: "Add Unplanned Piece",
                textColour: colours.text,
                strokeColour: colours.stroke,
                fillColour: state.useDarkMode ? colours.card : Palette.surface
            ) {
                presenter.didTapAddUnplanned()
            }

            if state.laundryAvailable {
                SecondaryButton(
                    title: "Laundry on the Road",
                    textColour: colours.text,
                    strokeColour: colours.stroke,
                    fillColour: state.useDarkMode ? colours.card : Palette.surface
                ) {
                    presenter.didTapLaundry()
                }
                if state.roadLaundryCount > 0 {
                    Text("\(Plural.count(state.roadLaundryCount, "load")) washed so far.")
                        .font(TypeScale.captionSmall)
                        .foregroundStyle(colours.mutedText)
                }
            } else {
                InlineNotice(text: "This trip was set up without laundry available.", icon: "info.circle")
            }
        }
    }

    // MARK: Finish

    private func finishSection(_ state: TripModeViewState) -> some View {
        ScreenBlock(spacing: 10) {
            SectionHeader("finish", accent: Palette.amber)

            CountProgress(
                passed: state.daysLogged,
                total: state.daysTotal,
                label: "days recorded",
                fill: state.canFinish ? Palette.success : Palette.amber
            )

            if let reason = state.finishBlockReason {
                Text(reason)
                    .font(TypeScale.captionSmall)
                    .foregroundStyle(colours.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PrimaryButton(
                title: state.canFinish ? "Finish Trip" : "Finish Without Records"
            ) {
                presenter.didTapFinish()
            }

            SecondaryButton(
                title: "Leave Trip Mode",
                textColour: colours.text,
                strokeColour: colours.stroke,
                fillColour: state.useDarkMode ? colours.card : Palette.surface
            ) {
                presenter.didTapClose()
            }

            Text("Leaving keeps the trip in progress. You can resume it from the trips list at any time.")
                .font(TypeScale.captionSmall)
                .foregroundStyle(colours.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
