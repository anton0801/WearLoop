//
//  RepairsView.swift
//  WearLoop
//

import SwiftUI

struct RepairsView: View {
    @StateObject var presenter: RepairsPresenter

    var body: some View {
        ScreenScaffold {
            ScreenBlock(spacing: 10) {
                ScreenHeader("repairs and care", subtitle: presenter.viewState.summaryText, artwork: .repairs) {
                    Button {
                        presenter.didTapAdd()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(IconButtonStyle())
                    .accessibilityLabel("Report an issue")
                    .disabled(presenter.viewState.repairablePieces.isEmpty)
                    .opacity(presenter.viewState.repairablePieces.isEmpty ? 0.4 : 1)
                }
            }

            SegmentBar(items: presenter.segmentItems(), selection: $presenter.section)

            if presenter.section == .open && presenter.viewState.totalOpen > 0 {
                ScreenBlock(spacing: 12) {
                    HStack(spacing: 20) {
                        BigNumber(value: "\(presenter.viewState.totalOpen)", label: "waiting", colour: Palette.danger, isCompact: true)
                        BigNumber(value: "\(presenter.viewState.oldestDays)", label: "days oldest", isCompact: true)
                        Spacer(minLength: 0)
                    }
                }
            }

            if presenter.section == .completed, let cost = presenter.viewState.totalCostText {
                ScreenBlock {
                    Panel {
                        FactRow(label: "Spent on Repairs", value: cost)
                    }
                }
            }

            content
        }
        .sheet(isPresented: $presenter.isAddPresented) {
            AddRepairSheet(pieces: presenter.viewState.repairablePieces) { pieceID, issue, plan in
                presenter.didAddIssue(pieceID: pieceID, issue: issue, plannedAction: plan)
            }
        }
        .sheet(item: $presenter.completingRow) { row in
            CompleteRepairSheet(name: row.name) { cost in
                presenter.didCompleteRepair(row.id, cost: cost)
            }
        }
        .sheet(item: $presenter.editingRow) { row in
            EditRepairSheet(row: row) { issue, plan in
                presenter.didUpdateIssue(row.id, issue: issue, plannedAction: plan)
            }
        }
        .toast($presenter.toast)
        .confirm($presenter.confirm)
        .onAppear { presenter.onAppear() }
    }

    @ViewBuilder
    private var content: some View {
        if presenter.viewState.rows.isEmpty {
            ScreenBlock {
                EmptyStateView(
                    title: presenter.section == .open ? "nothing to repair" : "nothing repaired yet",
                    message: presenter.section == .open
                        ? "Nothing is waiting. Report an issue from a piece's own screen, or add one here."
                        : "Repairs you complete are listed here with what they cost.",
                    actionTitle: presenter.section == .open && !presenter.viewState.repairablePieces.isEmpty
                        ? "Report an Issue" : nil,
                    action: presenter.section == .open && !presenter.viewState.repairablePieces.isEmpty
                        ? { presenter.didTapAdd() } : nil,
                    showHalftone: presenter.viewState.showHalftone
                )
            }
        } else {
            ScreenBlock(spacing: 12) {
                ForEach(presenter.viewState.rows) { row in
                    repairCard(row)
                }
            }
        }
    }

    private func repairCard(_ row: RepairRow) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                if let piece = row.piece {
                    Button {
                        presenter.didTapPiece(piece.id)
                    } label: {
                        PieceImage(
                            photoID: piece.photoID,
                            fallbackColour: piece.primaryColour,
                            fallbackInitial: piece.name.wlInitial,
                            initialSize: 26
                        )
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(CardPressStyle())
                    .accessibilityLabel("Open \(piece.name)")
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(row.name)
                        .font(TypeScale.bodyBold)
                        .foregroundStyle(Palette.anchor)
                    Text(row.issue)
                        .font(TypeScale.caption)
                        .foregroundStyle(Palette.anchor.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                    if !row.plannedAction.wlIsBlank {
                        Text("Plan: \(row.plannedAction)")
                            .font(TypeScale.captionSmall)
                            .foregroundStyle(Palette.anchor.opacity(0.55))
                    }
                }
                Spacer(minLength: 0)
            }

            Panel(padding: 12) {
                FactRow(label: "Reported On", value: row.reportedText)
                if row.completedText == nil {
                    Divider().overlay(Palette.anchor.opacity(0.1))
                    FactRow(
                        label: "Waiting",
                        value: Plural.count(row.daysOpen, "day"),
                        valueColour: row.suggestsRetiring ? Palette.danger : nil
                    )
                } else {
                    Divider().overlay(Palette.anchor.opacity(0.1))
                    FactRow(label: "Completed On", value: row.completedText ?? "")
                }
                if let cost = row.costText {
                    Divider().overlay(Palette.anchor.opacity(0.1))
                    FactRow(label: "Cost", value: cost)
                }
                if row.usedInOutfits > 0 && row.completedText == nil {
                    Divider().overlay(Palette.anchor.opacity(0.1))
                    FactRow(
                        label: "Blocking",
                        value: Plural.count(row.usedInOutfits, "outfit"),
                        valueColour: Palette.burgundy
                    )
                }
            }

            if presenter.showsRetireSuggestion(row) {
                WarningPanel(
                    message: "This has been waiting for \(Plural.count(row.daysOpen, "day")). If you are not going to fix it, retiring keeps its history without cluttering the wardrobe.",
                    primaryTitle: "Retire Piece",
                    primaryAction: { presenter.didTapRetire(row) },
                    secondaryTitle: "Keep Waiting",
                    secondaryAction: { presenter.didTapKeepWaiting(row) },
                    tint: Palette.danger
                )
            }

            if row.completedText == nil {
                HStack(spacing: 8) {
                    Button("Mark as Repaired") { presenter.didTapComplete(row) }
                        .buttonStyle(CompactButtonStyle(fill: Palette.success, textColour: .white))
                    Button("Edit") { presenter.didTapEdit(row) }
                        .buttonStyle(CompactOutlineButtonStyle())
                    Button("Remove") { presenter.didTapDelete(row) }
                        .buttonStyle(CompactOutlineButtonStyle(stroke: Palette.danger, textColour: Palette.danger))
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(PlateBackground(cornerRadius: Metrics.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(presenter.showsRetireSuggestion(row) ? Palette.danger.opacity(0.4) : .clear, lineWidth: 2)
        )
    }
}

// MARK: - Sheets

struct AddRepairSheet: View {
    let pieces: [Piece]
    let onAdd: (UUID, String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: UUID?
    @State private var issue = ""
    @State private var plan = ""
    @State private var pieceError: String?
    @State private var issueError: String?
    @State private var search = ""

    private var filtered: [Piece] {
        guard !search.wlIsBlank else { return pieces }
        let needle = search.wlTrimmed.lowercased()
        return pieces.filter { $0.searchHaystack.contains(needle) }
    }

    var body: some View {
        NavigationStack {
            ScreenScaffold {
                ScreenBlock(spacing: 20) {
                    ScreenHeader(
                        "report an issue",
                        subtitle: "The piece leaves rotation until the repair is done."
                    )

                    FieldFrame(label: "Piece", isRequired: true, errorMessage: pieceError) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Palette.anchor.opacity(0.45))
                                TextField("Search", text: $search)
                                    .font(TypeScale.body)
                                    .foregroundStyle(Palette.anchor)
                                    .autocorrectionDisabled()
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 48)
                            .background(PlateBackground(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Palette.anchor.opacity(0.2), lineWidth: 2)
                            )

                            if filtered.isEmpty {
                                InlineNotice(text: "No piece matches that search.", icon: "magnifyingglass")
                            } else {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: Metrics.cardGap) {
                                        ForEach(filtered) { piece in
                                            PieceCard(
                                                piece: piece,
                                                statusText: piece.category.title,
                                                showTag: false,
                                                isSelected: selectedID == piece.id,
                                                height: 170,
                                                width: 130
                                            ) {
                                                selectedID = piece.id
                                                pieceError = nil
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 2)
                                }
                            }
                        }
                    }

                    FieldFrame(label: "Issue", isRequired: true, errorMessage: issueError) {
                        WLTextField(
                            placeholder: "Loose button, torn hem…",
                            text: $issue,
                            hasError: issueError != nil
                        )
                    }

                    FieldFrame(label: "Planned Action") {
                        WLTextField(placeholder: "Take to the tailor", text: $plan)
                    }

                    PrimaryButton(title: "Add to Repair List") {
                        pieceError = selectedID == nil ? "Choose the piece that needs repair." : nil
                        issueError = issue.wlIsBlank ? "Describe the issue to continue." : nil
                        guard let id = selectedID, pieceError == nil, issueError == nil else { return }
                        onAdd(id, issue, plan)
                    }
                    SecondaryButton(title: "Cancel") { dismiss() }
                }
            }
        }
    }
}

struct CompleteRepairSheet: View {
    let name: String
    let onComplete: (Double?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var cost: Double?

    var body: some View {
        NavigationStack {
            ScreenScaffold {
                ScreenBlock(spacing: 20) {
                    ScreenHeader(
                        "mark as repaired",
                        subtitle: "\(name) goes back into rotation and becomes available for outfits and trips again."
                    )

                    FieldFrame(label: "Cost", helpText: "Optional. Counted in the repair total.") {
                        WLNumberField(placeholder: "Not entered", value: $cost)
                    }

                    PrimaryButton(title: "Mark as Repaired") { onComplete(cost) }
                    SecondaryButton(title: "Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(400)])
    }
}

struct EditRepairSheet: View {
    let row: RepairRow
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var issue = ""
    @State private var plan = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScreenScaffold {
                ScreenBlock(spacing: 20) {
                    ScreenHeader("edit issue", subtitle: row.name)

                    FieldFrame(label: "Issue", isRequired: true, errorMessage: error) {
                        WLTextField(placeholder: "What is wrong", text: $issue, hasError: error != nil)
                    }
                    FieldFrame(label: "Planned Action") {
                        WLTextField(placeholder: "What you will do about it", text: $plan)
                    }

                    PrimaryButton(title: "Save") {
                        guard !issue.wlIsBlank else {
                            error = "Describe the issue to continue."
                            return
                        }
                        onSave(issue, plan)
                    }
                    SecondaryButton(title: "Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(460)])
        .onAppear {
            issue = row.issue
            plan = row.plannedAction
        }
    }
}
