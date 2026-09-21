//
//  PieceFormView.swift
//  WearLoop
//

import SwiftUI

struct PieceFormView: View {
    @StateObject var presenter: PieceFormPresenter
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name, material, size, storage, tag, price, weight, care, note
    }

    var body: some View {
        ScreenScaffold(bottomInset: 40) {
            ScreenBlock(spacing: 10) {
                ScreenHeader(
                    presenter.viewState.title,
                    subtitle: presenter.viewState.isEditing
                        ? "Status and lifecycle are changed from the piece's own screen."
                        : "Name, category, colour, season and occasion are required.",
                    artwork: .camera
                )
            }

            ScreenBlock(spacing: 22) {
                photoField
                nameField
                categoryField
                colourField
                seasonField
                occasionField
            }

            ScreenBlock(spacing: 10) {
                SectionHeader("details")
            }

            ScreenBlock(spacing: 22) {
                materialField
                sizeField
                conditionField
                storageField
                weightField
                priceField
                purchaseDateField
                tagsField
                careNotesField
                privateNoteField
            }

            ScreenBlock(spacing: 12) {
                if let error = presenter.viewState.saveError {
                    WarningPanel(message: error, tint: Palette.danger)
                }
                if presenter.viewState.hasAnyError {
                    WarningPanel(
                        message: "Some required fields still need an answer. They are marked above.",
                        tint: Palette.danger
                    )
                }
                PrimaryButton(
                    title: "Save Piece",
                    isEnabled: !presenter.viewState.didSave,
                    isBusy: presenter.viewState.isSaving
                ) {
                    focusedField = nil
                    presenter.didTapSave()
                }
                SecondaryButton(title: "Cancel") { presenter.didTapCancel() }
            }
        }
        .onAppear { presenter.onAppear() }
    }

    // MARK: Photo

    private var photoField: some View {
        FieldFrame(
            label: "Photo",
            helpText: "With no photo the card becomes a solid block in the garment's colour."
        ) {
            PhotoPickerControls(
                image: Binding(
                    get: { presenter.viewState.newImage },
                    set: { presenter.viewState.newImage = $0; presenter.viewState.removePhoto = false }
                ),
                existingPhotoID: presenter.viewState.existingPhotoID,
                fallbackColour: presenter.viewState.previewColour,
                fallbackInitial: presenter.viewState.previewInitial,
                onRemove: { presenter.removePhoto() }
            )
        }
    }

    // MARK: Required fields

    private var nameField: some View {
        FieldFrame(label: "Piece Name", isRequired: true, errorMessage: presenter.viewState.nameError) {
            WLTextField(
                placeholder: "Navy wool coat",
                text: Binding(
                    get: { presenter.viewState.name },
                    set: { presenter.setName($0) }
                ),
                hasError: presenter.viewState.nameError != nil,
                capitalization: .sentences,
                submitLabel: .next
            )
            .focused($focusedField, equals: .name)
        }
    }

    private var categoryField: some View {
        FieldFrame(label: "Category", isRequired: true, errorMessage: presenter.viewState.categoryError) {
            ChipGroup(
                values: PieceCategory.allCases,
                title: { $0.title },
                accent: Palette.anchor,
                isSelected: { $0 == presenter.viewState.category },
                onTap: { presenter.setCategory($0) }
            )
        }
    }

    private var colourField: some View {
        FieldFrame(
            label: "Colour",
            isRequired: true,
            errorMessage: presenter.viewState.colourError,
            helpText: "The first colour is used for the generated cover."
        ) {
            ChipGroup(
                values: PieceColour.allCases,
                title: { $0.title },
                swatch: { $0.colour },
                accent: Palette.anchor,
                isSelected: { presenter.viewState.colours.contains($0) },
                onTap: { presenter.toggleColour($0) }
            )
        }
    }

    private var seasonField: some View {
        FieldFrame(label: "Season", isRequired: true, errorMessage: presenter.viewState.seasonError) {
            ChipGroup(
                values: Season.allCases,
                title: { $0.title },
                accent: Palette.amber,
                isSelected: { presenter.viewState.seasons.contains($0) },
                onTap: { presenter.toggleSeason($0) }
            )
        }
    }

    private var occasionField: some View {
        FieldFrame(label: "Occasions", isRequired: true, errorMessage: presenter.viewState.occasionError) {
            ChipGroup(
                values: Occasion.allCases,
                title: { $0.title },
                accent: Palette.burgundy,
                isSelected: { presenter.viewState.occasions.contains($0) },
                onTap: { presenter.toggleOccasion($0) }
            )
        }
    }

    // MARK: Optional fields

    private var materialField: some View {
        FieldFrame(label: "Material", helpText: "Used to warn about mixing incompatible care in one wash load.") {
            WLTextField(
                placeholder: "Wool, cotton, linen…",
                text: Binding(
                    get: { presenter.viewState.material },
                    set: { presenter.viewState.material = $0 }
                )
            )
            .focused($focusedField, equals: .material)
        }
    }

    private var sizeField: some View {
        FieldFrame(label: "Size") {
            WLTextField(
                placeholder: "M, 42, 32/34…",
                text: Binding(
                    get: { presenter.viewState.size },
                    set: { presenter.viewState.size = $0 }
                ),
                capitalization: .characters
            )
            .focused($focusedField, equals: .size)
        }
    }

    private var conditionField: some View {
        FieldFrame(
            label: "Condition",
            helpText: presenter.viewState.condition == .needsRepair
                ? "Marking it as needing repair takes the piece out of rotation."
                : nil
        ) {
            ChipGroup(
                values: PieceCondition.allCases,
                title: { $0.title },
                accent: presenter.viewState.condition == .needsRepair ? Palette.danger : Palette.anchor,
                isSelected: { $0 == presenter.viewState.condition },
                onTap: { presenter.setCondition($0) }
            )
        }
    }

    private var storageField: some View {
        FieldFrame(label: "Storage Place") {
            VStack(alignment: .leading, spacing: 8) {
                WLTextField(
                    placeholder: "Wardrobe, loft box, suitcase…",
                    text: Binding(
                        get: { presenter.viewState.storagePlace },
                        set: { presenter.setStoragePlace($0) }
                    )
                )
                .focused($focusedField, equals: .storage)

                if !presenter.viewState.suggestedStoragePlaces.isEmpty {
                    WrappingHStack {
                        ForEach(presenter.viewState.suggestedStoragePlaces, id: \.self) { place in
                            ChipView(
                                title: place,
                                isSelected: presenter.viewState.storagePlace == place
                            ) {
                                presenter.setStoragePlace(place)
                            }
                        }
                    }
                }
            }
        }
    }

    private var weightField: some View {
        FieldFrame(
            label: "Weight",
            helpText: "Optional. Without it the luggage estimate uses the category average and says so."
        ) {
            WLNumberField(
                placeholder: "Category average",
                value: Binding(
                    get: { presenter.viewState.weightGrams },
                    set: { presenter.viewState.weightGrams = $0 }
                ),
                suffix: "g"
            )
            .focused($focusedField, equals: .weight)
        }
    }

    private var priceField: some View {
        FieldFrame(label: "Purchase Price", helpText: "Needed for cost per wear.") {
            WLNumberField(
                placeholder: "Not entered",
                value: Binding(
                    get: { presenter.viewState.purchasePrice },
                    set: { presenter.viewState.purchasePrice = $0 }
                )
            )
            .focused($focusedField, equals: .price)
        }
    }

    private var purchaseDateField: some View {
        FieldFrame(label: "Purchase Date") {
            WLOptionalDateRow(
                label: "Purchase date",
                date: Binding(
                    get: { presenter.viewState.purchaseDate },
                    set: { presenter.viewState.purchaseDate = $0 }
                ),
                addTitle: "Add purchase date"
            )
        }
    }

    private var tagsField: some View {
        FieldFrame(label: "Personal Tags") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    WLTextField(
                        placeholder: "Add a tag",
                        text: Binding(
                            get: { presenter.viewState.tagDraft },
                            set: { presenter.viewState.tagDraft = $0 }
                        ),
                        submitLabel: .done,
                        onSubmit: { presenter.addTag() }
                    )
                    .focused($focusedField, equals: .tag)

                    Button("Add") { presenter.addTag() }
                        .buttonStyle(CompactButtonStyle(isEnabled: !presenter.viewState.tagDraft.wlIsBlank))
                        .disabled(presenter.viewState.tagDraft.wlIsBlank)
                }

                if !presenter.viewState.tags.isEmpty {
                    WrappingHStack {
                        ForEach(presenter.viewState.tags, id: \.self) { tag in
                            Button {
                                presenter.removeTag(tag)
                            } label: {
                                HStack(spacing: 5) {
                                    Text(tag)
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .black))
                                }
                                .font(TypeScale.caption)
                                .foregroundStyle(Palette.onAnchor)
                                .padding(.horizontal, 12)
                                .frame(height: 34)
                                .background(Capsule().fill(Palette.anchor))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove tag \(tag)")
                        }
                    }
                }

                let unused = presenter.viewState.suggestedTags.filter { !presenter.viewState.tags.contains($0) }
                if !unused.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tags you already use")
                            .font(TypeScale.captionSmall)
                            .foregroundStyle(Palette.anchor.opacity(0.5))
                        WrappingHStack {
                            ForEach(unused.prefix(12), id: \.self) { tag in
                                ChipView(title: tag, isSelected: false) {
                                    presenter.addTag(tag)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var careNotesField: some View {
        FieldFrame(label: "Care Notes", helpText: "Shown when a wash load mixes different care needs.") {
            WLTextEditor(
                placeholder: "Cold wash, do not tumble dry…",
                text: Binding(
                    get: { presenter.viewState.careNotes },
                    set: { presenter.viewState.careNotes = $0 }
                ),
                minHeight: 84
            )
            .focused($focusedField, equals: .care)
        }
    }

    private var privateNoteField: some View {
        FieldFrame(label: "Private Note", helpText: "Only ever shown on this piece's own screen.") {
            WLTextEditor(
                placeholder: "Anything you want to remember",
                text: Binding(
                    get: { presenter.viewState.privateNote },
                    set: { presenter.viewState.privateNote = $0 }
                ),
                minHeight: 84
            )
            .focused($focusedField, equals: .note)
        }
    }
}
