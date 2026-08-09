//
//  Buttons.swift
//  WearLoop
//
//  Primary amber, secondary outlined. No shadows. Press shrinks to 96%.
//

import SwiftUI

// MARK: - Styles

/// Amber fill, anchor text, 56pt tall.
struct PrimaryButtonStyle: ButtonStyle {
    var isEnabled: Bool = true
    var fill: Color = Palette.amber
    var textColour: Color = Palette.anchor
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TypeScale.button)
            .foregroundStyle(isEnabled ? textColour : textColour.opacity(0.45))
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: Metrics.buttonHeight)
            .padding(.horizontal, fullWidth ? 0 : 24)
            .background(
                RoundedRectangle(cornerRadius: Metrics.buttonRadius, style: .continuous)
                    .fill(isEnabled ? fill : fill.opacity(0.35))
            )
            .scaleEffect(configuration.isPressed && isEnabled ? 0.96 : 1)
            .animation(Motion.buttonPress, value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: Metrics.buttonRadius, style: .continuous))
    }
}

/// Surface fill with a 2pt anchor outline.
struct SecondaryButtonStyle: ButtonStyle {
    var isEnabled: Bool = true
    var strokeColour: Color = Palette.anchor
    var textColour: Color = Palette.anchor
    var fillColour: Color = Palette.surface
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TypeScale.button)
            .foregroundStyle(isEnabled ? textColour : textColour.opacity(0.4))
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: Metrics.buttonHeight)
            .padding(.horizontal, fullWidth ? 0 : 24)
            .background(
                RoundedRectangle(cornerRadius: Metrics.buttonRadius, style: .continuous)
                    .fill(fillColour)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.buttonRadius, style: .continuous)
                    .strokeBorder(isEnabled ? strokeColour : strokeColour.opacity(0.3), lineWidth: 2)
            )
            .scaleEffect(configuration.isPressed && isEnabled ? 0.96 : 1)
            .animation(Motion.buttonPress, value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: Metrics.buttonRadius, style: .continuous))
    }
}

/// A compact pill for inline actions inside cards and rows.
struct CompactButtonStyle: ButtonStyle {
    var fill: Color = Palette.anchor
    var textColour: Color = Palette.onAnchor
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TypeScale.caption)
            .foregroundStyle(isEnabled ? textColour : textColour.opacity(0.5))
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(
                Capsule(style: .continuous)
                    .fill(isEnabled ? fill : fill.opacity(0.35))
            )
            .scaleEffect(configuration.isPressed && isEnabled ? 0.96 : 1)
            .animation(Motion.buttonPress, value: configuration.isPressed)
            .contentShape(Capsule(style: .continuous))
    }
}

/// A bordered compact pill, for the quieter of two inline actions.
struct CompactOutlineButtonStyle: ButtonStyle {
    var stroke: Color = Palette.anchor
    var textColour: Color = Palette.anchor
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TypeScale.caption)
            .foregroundStyle(isEnabled ? textColour : textColour.opacity(0.4))
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(Capsule(style: .continuous).fill(Palette.surface))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(isEnabled ? stroke : stroke.opacity(0.3), lineWidth: 2)
            )
            .scaleEffect(configuration.isPressed && isEnabled ? 0.96 : 1)
            .animation(Motion.buttonPress, value: configuration.isPressed)
            .contentShape(Capsule(style: .continuous))
    }
}

/// An icon-only round button, used for back and profile.
struct IconButtonStyle: ButtonStyle {
    var fill: Color = Palette.surface
    var iconColour: Color = Palette.anchor
    var size: CGFloat = 44
    var bordered: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(iconColour)
            .frame(width: size, height: size)
            .background(Circle().fill(fill))
            .overlay(
                Circle().strokeBorder(bordered ? iconColour : .clear, lineWidth: 2)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Motion.buttonPress, value: configuration.isPressed)
            .contentShape(Circle())
    }
}

// MARK: - Ready-made buttons

/// The main call to action on a screen.
struct PrimaryButton: View {
    let title: String
    var isEnabled: Bool = true
    /// Blocks input and shows progress while a save is running.
    var isBusy: Bool = false
    var fill: Color = Palette.amber
    let action: () -> Void

    var body: some View {
        Button(action: { if isEnabled && !isBusy { action() } }) {
            HStack(spacing: 10) {
                if isBusy {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Palette.anchor)
                }
                Text(isBusy ? "Saving…" : title)
            }
        }
        .buttonStyle(PrimaryButtonStyle(isEnabled: isEnabled && !isBusy, fill: fill))
        .disabled(!isEnabled || isBusy)
        .accessibilityLabel(title)
        .accessibilityHint(isEnabled ? "" : "Unavailable until the form is complete")
    }
}

struct SecondaryButton: View {
    let title: String
    var isEnabled: Bool = true
    var textColour: Color = Palette.anchor
    var strokeColour: Color = Palette.anchor
    var fillColour: Color = Palette.surface
    let action: () -> Void

    var body: some View {
        Button(action: { if isEnabled { action() } }) {
            Text(title)
        }
        .buttonStyle(
            SecondaryButtonStyle(
                isEnabled: isEnabled,
                strokeColour: strokeColour,
                textColour: textColour,
                fillColour: fillColour
            )
        )
        .disabled(!isEnabled)
    }
}

/// A destructive action, in the danger colour.
struct DangerButton: View {
    let title: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: { if isEnabled { action() } }) {
            Text(title)
        }
        .buttonStyle(PrimaryButtonStyle(isEnabled: isEnabled, fill: Palette.danger, textColour: .white))
        .disabled(!isEnabled)
    }
}

/// A plain text action with no chrome, for tertiary choices.
struct TextButton: View {
    let title: String
    var colour: Color = Palette.anchor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(TypeScale.caption)
                .foregroundStyle(colour)
                .underline(true, color: colour.opacity(0.4))
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
