//
//  Feedback.swift
//  WearLoop
//
//  Toasts, confirmations and the photo picker. Every destructive action is
//  confirmed, and the confirmation says what will actually happen.
//

import PhotosUI
import SwiftUI

// MARK: - Toast

struct ToastMessage: Equatable, Identifiable {
    enum Kind: Equatable {
        case success
        case failure
        case info

        var colour: Color {
            switch self {
            case .success: return Palette.success
            case .failure: return Palette.danger
            case .info: return Palette.anchor
            }
        }

        var icon: String {
            switch self {
            case .success: return "checkmark"
            case .failure: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            }
        }
    }

    var id = UUID()
    var text: String
    var kind: Kind = .success
    /// An action offered alongside the message, e.g. "Undo".
    var actionTitle: String?
    var action: (() -> Void)?

    static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool {
        lhs.id == rhs.id
    }
}

/// Shows a short confirmation over the bottom of the screen.
struct ToastOverlay: ViewModifier {
    @Binding var message: ToastMessage?
    var bottomPadding: CGFloat = 24

    @State private var dismissTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message {
                    HStack(spacing: 10) {
                        Image(systemName: message.kind.icon)
                            .font(.system(size: 13, weight: .black))
                        Text(message.text)
                            .font(TypeScale.caption)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if let actionTitle = message.actionTitle, let action = message.action {
                            Button {
                                action()
                                self.message = nil
                            } label: {
                                Text(actionTitle)
                                    .font(TypeScale.caption)
                                    .underline()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .foregroundStyle(Palette.onAnchor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(message.kind.colour == Palette.anchor ? Palette.anchor : message.kind.colour)
                    )
                    .padding(.horizontal, Metrics.screenPadding)
                    .padding(.bottom, bottomPadding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityAddTraits(.isStaticText)
                    .accessibilityLabel(message.text)
                }
            }
            .animation(Motion.standard, value: message)
            .onChange(of: message) { _, newValue in
                dismissTask?.cancel()
                guard newValue != nil else { return }
                dismissTask = Task {
                    try? await Task.sleep(nanoseconds: 3_200_000_000)
                    guard !Task.isCancelled else { return }
                    await MainActor.run { message = nil }
                }
            }
    }
}

extension View {
    func toast(_ message: Binding<ToastMessage?>, bottomPadding: CGFloat = 24) -> some View {
        modifier(ToastOverlay(message: message, bottomPadding: bottomPadding))
    }
}

// MARK: - Confirmation

/// A confirmation that spells out the consequence before it happens.
struct ConfirmRequest: Identifiable {
    var id = UUID()
    var title: String
    var message: String
    var confirmTitle: String
    var cancelTitle: String = "Cancel"
    var isDestructive: Bool = true
    /// Set for the second confirmation of an irreversible action.
    var requiresSecondStep: Bool = false
    var secondStepMessage: String?
    var onConfirm: () -> Void
}

extension View {
    /// Presents a confirmation, with an optional second step for the
    /// irreversible cases such as deleting all data.
    func confirm(_ request: Binding<ConfirmRequest?>) -> some View {
        modifier(ConfirmModifier(request: request))
    }
}

private struct ConfirmModifier: ViewModifier {
    @Binding var request: ConfirmRequest?
    @State private var secondStep: ConfirmRequest?

    func body(content: Content) -> some View {
        content
            .alert(
                request?.title ?? "",
                isPresented: Binding(
                    get: { request != nil },
                    set: { if !$0 { request = nil } }
                ),
                presenting: request
            ) { item in
                Button(item.cancelTitle, role: .cancel) { request = nil }
                Button(item.confirmTitle, role: item.isDestructive ? .destructive : nil) {
                    if item.requiresSecondStep {
                        // Hand over to the second confirmation.
                        var second = item
                        second.id = UUID()
                        second.requiresSecondStep = false
                        second.title = "Are You Certain?"
                        second.message = item.secondStepMessage ?? "This cannot be undone."
                        request = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            secondStep = second
                        }
                    } else {
                        let action = item.onConfirm
                        request = nil
                        action()
                    }
                }
            } message: { item in
                Text(item.message)
            }
            .alert(
                secondStep?.title ?? "",
                isPresented: Binding(
                    get: { secondStep != nil },
                    set: { if !$0 { secondStep = nil } }
                ),
                presenting: secondStep
            ) { item in
                Button(item.cancelTitle, role: .cancel) { secondStep = nil }
                Button(item.confirmTitle, role: .destructive) {
                    let action = item.onConfirm
                    secondStep = nil
                    action()
                }
            } message: { item in
                Text(item.message)
            }
    }
}

// MARK: - Photo picking

/// Camera capture. Checked for availability before it is offered, so the button
/// is never a dead end on a device without a camera.
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker

        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

/// The photo row of the piece form: take, choose or remove.
struct PhotoPickerControls: View {
    @Binding var image: UIImage?
    /// Set when the piece already has a stored photograph.
    var existingPhotoID: String?
    var fallbackColour: PieceColour
    var fallbackInitial: String
    var onRemove: () -> Void

    @State private var photosItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var loadError: String?
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            preview

            HStack(spacing: 8) {
                if CameraPicker.isAvailable {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Take Photo", systemImage: "camera.fill")
                    }
                    .buttonStyle(CompactOutlineButtonStyle())
                }

                PhotosPicker(selection: $photosItem, matching: .images, photoLibrary: .shared()) {
                    Label("Choose From Gallery", systemImage: "photo.on.rectangle")
                        .font(TypeScale.caption)
                        .foregroundStyle(Palette.anchor)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(Capsule().fill(Palette.surface))
                        .overlay(Capsule().strokeBorder(Palette.anchor, lineWidth: 2))
                }
            }

            if image != nil || existingPhotoID != nil {
                Button("Remove Photo") {
                    image = nil
                    photosItem = nil
                    onRemove()
                }
                .buttonStyle(CompactOutlineButtonStyle(stroke: Palette.danger, textColour: Palette.danger))
            }

            if !CameraPicker.isAvailable {
                Text("This device has no camera available, so photos can only come from the gallery.")
                    .font(TypeScale.captionSmall)
                    .foregroundStyle(Palette.anchor.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let loadError {
                Text(loadError)
                    .font(TypeScale.captionSmall)
                    .foregroundStyle(Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker { captured in
                image = captured
                loadError = nil
            }
            .ignoresSafeArea()
        }
        .onChange(of: photosItem) { _, newItem in
            guard let newItem else { return }
            isLoading = true
            loadError = nil
            Task {
                do {
                    if let data = try await newItem.loadTransferable(type: Data.self),
                       let loaded = UIImage(data: data) {
                        await MainActor.run {
                            image = loaded
                            isLoading = false
                        }
                    } else {
                        await MainActor.run {
                            loadError = "That photo could not be read. Try another one."
                            isLoading = false
                        }
                    }
                } catch {
                    await MainActor.run {
                        loadError = "That photo could not be loaded. \(error.localizedDescription)"
                        isLoading = false
                    }
                }
            }
        }
    }

    private var preview: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let existingPhotoID {
                PieceImage(
                    photoID: existingPhotoID,
                    fallbackColour: fallbackColour,
                    fallbackInitial: fallbackInitial
                )
            } else {
                Rectangle()
                    .fill(fallbackColour.colour)
                    .overlay(
                        Text(fallbackInitial)
                            .font(.system(size: 72, weight: .black))
                            .foregroundStyle(
                                (fallbackColour.prefersLightText ? Color.white : Palette.anchor).opacity(0.3)
                            )
                    )
            }
            if isLoading {
                Rectangle().fill(Palette.anchor.opacity(0.35))
                ProgressView().tint(.white)
            }
        }
        .frame(height: 220)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .accessibilityLabel(image != nil || existingPhotoID != nil ? "Current photo" : "No photo yet, a coloured cover will be used")
    }
}
