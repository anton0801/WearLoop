//
//  TripRecapView.swift
//  WearLoop
//

import SwiftUI

struct TripRecapView: View {
    @StateObject var presenter: TripRecapPresenter
    @State private var noteDraft = ""
    @State private var didLoadNote = false

    var body: some View {
        Group {
            if let state = presenter.viewState {
                content(state)
            } else if presenter.isMissing {
                ScreenScaffold {
                    ScreenBlock {
                        EmptyStateView(
                            title: "this trip is gone",
                            message: "It was deleted. Wear records made during it are kept."
                        )
                    }
                }
            } else {
                ScreenScaffold { LoadingStateView(message: "Building the recap…") }
            }
        }
        .sheet(isPresented: $presenter.isTemplateSheetPresented) {
            if let state = presenter.viewState {
                CreateTemplateSheet(defaultName: "\(state.tripName) template") {
                    presenter.didCreateTemplate(name: $0)
                }
            }
        }
        .toast($presenter.toast)
        .confirm($presenter.confirm)
        .onAppear {
            presenter.onAppear()
            if !didLoadNote {
                noteDraft = presenter.viewState?.note ?? ""
                didLoadNote = true
            }
        }
    }

    private func content(_ state: TripRecapViewState) -> some View {
        ScreenScaffold {
            ScreenBlock(spacing: 10) {
                ScreenHeader("trip recap", subtitle: "\(state.tripName) · \(state.dateText)")
                if !state.isFinished {
                    InlineNotice(
                        text: "This trip has not been finished yet. These figures are a preview and will update as you record more.",
                        icon: "info.circle"
                    )
                }
                if state.recap?.finishedWithoutRecords == true {
                    InlineNotice(
                        text: "This trip was finished without full records, so the figures below are incomplete.",
                        icon: "exclamationmark.triangle.fill",
                        colour: Palette.burgundy
                    )
                }
            }

            headline(state)
            comparison(state)
            neverWornSection(state)
            wornNotPackedSection(state)
            conclusionsSection(state)
            noteSection(state)
            actionsSection(state)
        }
    }

    // MARK: Headline

    private func headline(_ state: TripRecapViewState) -> some View {
        ScreenBlock(spacing: 14) {
            SectionHeader("planned vs worn", accent: Palette.burgundy)

            HStack(alignment: .top, spacing: 20) {
                BigNumber(value: "\(state.packedCount)", label: "pieces packed", isCompact: true)
                BigNumber(value: "\(state.wornCount)", label: "actually worn", colour: Palette.success, isCompact: true)
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(state.accuracyText)
                        .font(TypeScale.bigNumber)
                        .foregroundStyle(accuracyColour(state.accuracyFraction))
                    Text("packing accuracy")
                        .font(TypeScale.caption)
                        .foregroundStyle(Palette.anchor.opacity(0.6))
                }
                ValueBar(
                    fraction: state.accuracyFraction,
                    fill: accuracyColour(state.accuracyFraction),
                    height: 12
                )
                Text("The share of what you packed that you actually put on.")
                    .font(TypeScale.captionSmall)
                    .foregroundStyle(Palette.anchor.opacity(0.55))
            }
        }
    }

    private func accuracyColour(_ fraction: Double) -> Color {
        if fraction >= 0.8 { return Palette.success }
        if fraction >= 0.5 { return Palette.amber }
        return Palette.danger
    }

    // MARK: Comparison

    private func comparison(_ state: TripRecapViewState) -> some View {
        ScreenBlock {
            Panel {
                FactRow(label: "Pieces Packed", value: "\(state.packedCount)")
                Divider().overlay(Palette.anchor.opacity(0.1))
                FactRow(label: "Worn at Least Once", value: "\(state.wornCount)")
                Divider().overlay(Palette.anchor.opacity(0.1))
                FactRow(
                    label: "Never Worn on This Trip",
                    value: "\(state.neverWorn.count)",
                    valueColour: state.neverWorn.isEmpty ? Palette.success : Palette.burgundy
                )
                Divider().overlay(Palette.anchor.opacity(0.1))
                FactRow(label: "Outfits Changed", value: "\(state.outfitsChanged)")
                Divider().overlay(Palette.anchor.opacity(0.1))
                FactRow(label: "Laundry Done", value: Plural.count(state.laundryDone, "load"))
                Divider().overlay(Palette.anchor.opacity(0.1))
                FactRow(label: "Final Weight", value: state.finalWeightText)
            }
        }
    }

    // MARK: Rails

    @ViewBuilder
    private func neverWornSection(_ state: TripRecapViewState) -> some View {
        if state.neverWorn.isEmpty {
            ScreenBlock(spacing: 10) {
                SectionHeader("never worn on this trip")
                InlineNotice(
                    text: "Everything you packed was worn. This is a packing list worth keeping.",
                    icon: "checkmark.circle.fill",
                    colour: Palette.success
                )
            }
        } else {
            RailSection(
                title: "never worn on this trip",
                accent: Palette.burgundy,
                items: state.neverWorn
            ) { piece in
                PieceCard(
                    piece: piece,
                    statusText: "Travelled, never worn",
                    width: Metrics.railCardWidth
                ) {
                    presenter.didTapPiece(piece.id)
                }
            }
        }
    }

    @ViewBuilder
    private func wornNotPackedSection(_ state: TripRecapViewState) -> some View {
        if !state.wornNotPacked.isEmpty {
            RailSection(
                title: "worn but not on the list",
                accent: Palette.amber,
                items: state.wornNotPacked
            ) { piece in
                PieceCard(
                    piece: piece,
                    statusText: "Worn, never packed",
                    width: Metrics.railCardWidth
                ) {
                    presenter.didTapPiece(piece.id)
                }
            }
        }
    }

    // MARK: Conclusions

    @ViewBuilder
    private func conclusionsSection(_ state: TripRecapViewState) -> some View {
        if !state.conclusions.isEmpty {
            ScreenBlock(spacing: 10) {
                SectionHeader("what to take from this")
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(state.conclusions.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .top, spacing: 10) {
                            Rectangle()
                                .fill(Palette.amber)
                                .frame(width: 4)
                                .clipShape(Capsule())
                            Text(line)
                                .font(TypeScale.body)
                                .foregroundStyle(Palette.anchor)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Palette.surface)
                                .halftoneBacking(
                                    enabled: state.showHalftone,
                                    opacity: 0.12,
                                    focus: .trailing,
                                    spacing: 26
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        )
                    }
                }
            }
        }
    }

    // MARK: Note

    private func noteSection(_ state: TripRecapViewState) -> some View {
        ScreenBlock(spacing: 10) {
            SectionHeader("your note")
            WLTextEditor(placeholder: "Anything to remember for next time", text: $noteDraft, minHeight: 90)
                .onChange(of: noteDraft) { _, newValue in
                    presenter.didSaveNote(newValue)
                }
                .disabled(!state.isFinished)
            if !state.isFinished {
                Text("Notes can be added once the trip is finished.")
                    .font(TypeScale.captionSmall)
                    .foregroundStyle(Palette.anchor.opacity(0.5))
            }
        }
    }

    // MARK: Actions

    private func actionsSection(_ state: TripRecapViewState) -> some View {
        ScreenBlock(spacing: 10) {
            if state.isFinished {
                PrimaryButton(title: "Create Packing Template") { presenter.didTapCreateTemplate() }
                if state.hasTemplate {
                    InlineNotice(
                        text: "A template from this trip already exists.",
                        icon: "doc.on.doc",
                        colour: Palette.anchor.opacity(0.6)
                    )
                    SecondaryButton(title: "Open Templates") { presenter.didTapTemplates() }
                }
                SecondaryButton(title: "Close Trip") { presenter.didTapCloseTrip() }
            } else {
                PrimaryButton(title: "Save Recap") { presenter.didTapSaveRecap() }
                Text("Saving marks the trip as finished and locks in these figures.")
                    .font(TypeScale.captionSmall)
                    .foregroundStyle(Palette.anchor.opacity(0.55))
            }
        }
    }
}

// MARK: - Create template

struct CreateTemplateSheet: View {
    let defaultName: String
    let onCreate: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            ScreenScaffold {
                ScreenBlock(spacing: 20) {
                    ScreenHeader(
                        "save as template",
                        subtitle: "Only the items you ticked off as packed are kept."
                    )

                    FieldFrame(label: "Template Name") {
                        WLTextField(placeholder: defaultName, text: $name, capitalization: .words)
                    }

                    PrimaryButton(title: "Create Template") {
                        onCreate(name.wlIsBlank ? defaultName : name)
                    }
                    SecondaryButton(title: "Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(420)])
        .onAppear { name = defaultName }
    }
}
