//
//  TemplatesView.swift
//  WearLoop
//

import SwiftUI

struct TemplatesView: View {
    @StateObject var presenter: TemplatesPresenter

    var body: some View {
        ScreenScaffold {
            ScreenBlock(spacing: 10) {
                ScreenHeader("my templates", subtitle: presenter.viewState.summaryText, artwork: .templates)
            }

            if presenter.viewState.items.isEmpty {
                ScreenBlock {
                    EmptyStateView(
                        title: "no templates yet",
                        message: "Finish a trip, then save what you actually packed as a template. The next trip of the same kind starts from it.",
                        showHalftone: presenter.viewState.showHalftone
                    )
                }
            } else {
                ForEach(presenter.viewState.items) { item in
                    templateCard(item)
                }
            }
        }
        .sheet(item: $presenter.applyingTemplate) { item in
            ApplyTemplateSheet(
                item: item,
                trips: presenter.viewState.applicableTrips
            ) { tripID, availableOnly in
                presenter.didConfirmApply(
                    templateID: item.id,
                    tripID: tripID,
                    availableOnly: availableOnly
                )
            }
        }
        .sheet(item: $presenter.renamingTemplate) { item in
            RenameTemplateSheet(currentName: item.template.name) { newName in
                presenter.didSubmitRename(item.id, name: newName)
            }
        }
        .toast($presenter.toast)
        .confirm($presenter.confirm)
        .onAppear { presenter.onAppear() }
    }

    private func templateCard(_ item: TemplateItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ScreenBlock(spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.template.name)
                            .font(TypeScale.sectionTitle)
                            .tracking(TypeScale.sectionTitleTracking)
                            .foregroundStyle(Palette.anchor)
                            .lineLimit(2)
                        Text("\(item.template.tripType.title) · \(Plural.count(item.template.dayCount, "day")) · from \(item.template.sourceTripName)")
                            .font(TypeScale.captionSmall)
                            .foregroundStyle(Palette.anchor.opacity(0.6))
                    }
                    Spacer(minLength: 8)
                    if item.availability.isFullyAvailable {
                        StatusTag(text: "READY", fill: Palette.success)
                    } else {
                        StatusTag(text: "CHECK", fill: Palette.burgundy)
                    }
                }

                Text(item.summary)
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.anchor.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !item.pieces.isEmpty {
                CardRail(items: item.pieces, height: 160) { piece in
                    PieceCard(
                        piece: piece,
                        statusText: piece.status.isAvailable ? piece.category.title : piece.status.title,
                        isDimmed: !piece.status.isAvailable,
                        height: 160,
                        width: 120
                    ) {
                        presenter.didTapPiece(piece.id)
                    }
                }
            }

            ScreenBlock(spacing: 8) {
                if !item.template.manualItems.isEmpty {
                    InlineNotice(
                        text: "Also includes: \(item.template.manualItems.joined(separator: ", ")).",
                        icon: "text.badge.plus"
                    )
                }
                HStack(spacing: 8) {
                    Button("Apply Template") { presenter.didTapApply(item) }
                        .buttonStyle(CompactButtonStyle(fill: Palette.amber, textColour: Palette.anchor))
                    Button("Rename") { presenter.didTapRename(item) }
                        .buttonStyle(CompactOutlineButtonStyle())
                    Button("Delete") { presenter.didTapDelete(item) }
                        .buttonStyle(CompactOutlineButtonStyle(stroke: Palette.danger, textColour: Palette.danger))
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Apply sheet

struct ApplyTemplateSheet: View {
    let item: TemplateItem
    let trips: [Trip]
    let onApply: (UUID, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTripID: UUID?
    @State private var showsMissing = false

    var body: some View {
        NavigationStack {
            ScreenScaffold {
                ScreenBlock(spacing: 18) {
                    ScreenHeader("apply template", subtitle: item.template.name)

                    Panel {
                        Text(item.summary)
                            .font(TypeScale.body)
                            .foregroundStyle(Palette.anchor)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if item.availability.missingCount > 0 {
                        VStack(alignment: .leading, spacing: 10) {
                            Button(showsMissing ? "Hide Missing" : "Review Missing") {
                                withAnimation(Motion.standard) { showsMissing.toggle() }
                            }
                            .buttonStyle(CompactOutlineButtonStyle())

                            if showsMissing {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(missingRows, id: \.self) { row in
                                        InlineNotice(text: row, icon: "exclamationmark.circle", colour: Palette.burgundy)
                                    }
                                }
                            }
                        }
                    }

                    FieldFrame(label: "Apply To", isRequired: true) {
                        if trips.isEmpty {
                            InlineNotice(text: "No unfinished trip to apply this to.", icon: "suitcase")
                        } else {
                            VStack(spacing: 8) {
                                ForEach(trips) { trip in
                                    Button {
                                        selectedTripID = trip.id
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(trip.name.wlIsBlank ? "Untitled trip" : trip.name)
                                                    .font(TypeScale.bodyBold)
                                                    .foregroundStyle(Palette.anchor)
                                                Text(trip.dateRangeText)
                                                    .font(TypeScale.captionSmall)
                                                    .foregroundStyle(Palette.anchor.opacity(0.55))
                                            }
                                            Spacer(minLength: 8)
                                            Image(systemName: selectedTripID == trip.id ? "largecircle.fill.circle" : "circle")
                                                .foregroundStyle(selectedTripID == trip.id ? Palette.burgundy : Palette.anchor.opacity(0.3))
                                        }
                                        .padding(14)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(PlateBackground(cornerRadius: 14))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .strokeBorder(selectedTripID == trip.id ? Palette.burgundy : .clear, lineWidth: 2)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityAddTraits(selectedTripID == trip.id ? [.isButton, .isSelected] : .isButton)
                                }
                            }
                        }
                    }

                    PrimaryButton(
                        title: "Apply Available Pieces",
                        isEnabled: selectedTripID != nil
                    ) {
                        if let id = selectedTripID { onApply(id, true) }
                    }

                    if item.availability.missingCount > 0 {
                        SecondaryButton(
                            title: "Apply Everything Anyway",
                            isEnabled: selectedTripID != nil
                        ) {
                            if let id = selectedTripID { onApply(id, false) }
                        }
                        Text("Applying everything includes archived pieces and pieces needing repair. They will show as unavailable on the packing list.")
                            .font(TypeScale.captionSmall)
                            .foregroundStyle(Palette.anchor.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SecondaryButton(title: "Cancel") { dismiss() }
                }
            }
        }
        .onAppear { selectedTripID = trips.first?.id }
    }

    private var missingRows: [String] {
        var rows: [String] = []
        for id in item.availability.archivedIDs {
            let name = item.template.snapshots.first { $0.pieceID == id }?.name ?? "A piece"
            rows.append("\(name): archived.")
        }
        for id in item.availability.needsRepairIDs {
            let name = item.template.snapshots.first { $0.pieceID == id }?.name ?? "A piece"
            rows.append("\(name): needs repair.")
        }
        for id in item.availability.inWashIDs {
            let name = item.template.snapshots.first { $0.pieceID == id }?.name ?? "A piece"
            rows.append("\(name): in the wash.")
        }
        if item.availability.deletedCount > 0 {
            rows.append("\(Plural.count(item.availability.deletedCount, "piece")) no longer exist in your wardrobe.")
        }
        return rows
    }
}

// MARK: - Rename sheet

struct RenameTemplateSheet: View {
    let currentName: String
    let onRename: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScreenScaffold {
                ScreenBlock(spacing: 20) {
                    ScreenHeader("rename template")
                    FieldFrame(label: "Name", isRequired: true, errorMessage: error) {
                        WLTextField(placeholder: currentName, text: $name, hasError: error != nil, capitalization: .words)
                    }
                    PrimaryButton(title: "Save") {
                        guard !name.wlIsBlank else {
                            error = "Enter a name to continue."
                            return
                        }
                        onRename(name)
                    }
                    SecondaryButton(title: "Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(360)])
        .onAppear { name = currentName }
    }
}
