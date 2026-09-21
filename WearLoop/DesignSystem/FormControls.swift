//
//  FormControls.swift
//  WearLoop
//
//  Fields, chip pickers and steppers. Every field can show its own validation
//  message so the form can point at the exact problem.
//

import SwiftUI

// MARK: - Field frame

/// Label, control and error message in the app's own field style.
struct FieldFrame<Content: View>: View {
    let label: String
    var isRequired: Bool = false
    /// Set to highlight the field and show the reason.
    var errorMessage: String?
    var helpText: String?
    @ViewBuilder var content: () -> Content

    @Environment(\.wlDarkSurface) private var isDark

    var body: some View {
        let colours = SurfaceColours.forDark(isDark)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(label)
                    .font(TypeScale.caption)
                    .foregroundStyle(colours.text)
                if isRequired {
                    Text("required")
                        .font(TypeScale.captionSmall)
                        .foregroundStyle(Palette.burgundy)
                }
            }

            content()

            if let errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text(errorMessage)
                        .font(TypeScale.captionSmall)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Palette.danger)
                .transition(.opacity)
            } else if let helpText {
                Text(helpText)
                    .font(TypeScale.captionSmall)
                    .foregroundStyle(colours.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isRequired ? "\(label), required" : label)
    }
}

// MARK: - Text input

struct WLTextField: View {
    let placeholder: String
    @Binding var text: String
    var hasError: Bool = false
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .sentences
    var submitLabel: SubmitLabel = .done
    var onSubmit: (() -> Void)?

    var body: some View {
        TextField(placeholder, text: $text)
            .font(TypeScale.body)
            .foregroundStyle(Palette.anchor)
            .keyboardType(keyboard)
            .textInputAutocapitalization(capitalization)
            .autocorrectionDisabled(keyboard == .emailAddress)
            .submitLabel(submitLabel)
            .onSubmit { onSubmit?() }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(PlateBackground(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(hasError ? Palette.danger : Palette.anchor.opacity(0.25), lineWidth: 2)
            )
    }
}

struct WLTextEditor: View {
    let placeholder: String
    @Binding var text: String
    var minHeight: CGFloat = 96

    var body: some View {
        ZStack(alignment: .topLeading) {
            PlateBackground(cornerRadius: 14, isRaised: false)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.anchor.opacity(0.25), lineWidth: 2)

            if text.isEmpty {
                Text(placeholder)
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.anchor.opacity(0.35))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(TypeScale.body)
                .foregroundStyle(Palette.anchor)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .frame(minHeight: minHeight)
    }
}

/// A numeric field that keeps an optional value, so "not entered" stays distinct
/// from zero.
struct WLNumberField: View {
    let placeholder: String
    @Binding var value: Double?
    var suffix: String?
    var hasError: Bool = false
    var allowsDecimal: Bool = true

    @State private var text: String = ""
    @State private var isSyncing = false

    var body: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $text)
                .font(TypeScale.body)
                .foregroundStyle(Palette.anchor)
                .keyboardType(allowsDecimal ? .decimalPad : .numberPad)
                .onChange(of: text) { _, newValue in
                    guard !isSyncing else { return }
                    let filtered = newValue.filter { $0.isNumber || $0 == "." || $0 == "," }
                    if filtered != newValue {
                        isSyncing = true
                        text = filtered
                        isSyncing = false
                    }
                    let normalised = filtered.replacingOccurrences(of: ",", with: ".")
                    value = normalised.isEmpty ? nil : Double(normalised)
                }
            if let suffix {
                Text(suffix)
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.anchor.opacity(0.5))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(PlateBackground(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(hasError ? Palette.danger : Palette.anchor.opacity(0.25), lineWidth: 2)
        )
        .onAppear { syncFromValue() }
        .onChange(of: value) { _, _ in
            // Keep the text in step when the value is changed from outside.
            let current = text.replacingOccurrences(of: ",", with: ".")
            if Double(current) != value { syncFromValue() }
        }
    }

    private func syncFromValue() {
        isSyncing = true
        if let value {
            text = allowsDecimal
                ? (value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value))
                : String(Int(value))
        } else {
            text = ""
        }
        isSyncing = false
    }
}

// MARK: - Chips

/// A single selectable chip.
struct ChipView: View {
    let title: String
    let isSelected: Bool
    var accent: Color = Palette.anchor
    var isDisabled: Bool = false
    /// Small colour dot, used by the colour picker.
    var swatch: Color?
    let action: () -> Void

    @Environment(\.wlDarkSurface) private var isDark

    var body: some View {
        let colours = SurfaceColours.forDark(isDark)
        Button(action: action) {
            HStack(spacing: 6) {
                if let swatch {
                    Circle()
                        .fill(swatch)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(colours.text.opacity(0.3), lineWidth: 1))
                }
                Text(title)
                    .font(TypeScale.caption)
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Palette.onAnchor : (isDisabled ? colours.mutedText : colours.text))
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? accent : (isDark ? colours.card : Palette.surface))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(isSelected ? .clear : colours.text.opacity(0.25), lineWidth: 2)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A wrapping group of chips for choosing one or many values.
struct ChipGroup<Value: Hashable & Identifiable>: View {
    let values: [Value]
    let title: (Value) -> String
    var swatch: ((Value) -> Color?)?
    var accent: Color = Palette.anchor
    let isSelected: (Value) -> Bool
    let onTap: (Value) -> Void

    var body: some View {
        WrappingHStack(spacing: 8, lineSpacing: 8) {
            ForEach(values) { value in
                ChipView(
                    title: title(value),
                    isSelected: isSelected(value),
                    accent: accent,
                    swatch: swatch?(value)
                ) {
                    onTap(value)
                }
            }
        }
    }
}

/// Lays chips out in rows, wrapping to the next line when the width runs out.
struct WrappingHStack<Content: View>: View {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        // Layout protocol keeps this a single pass, unlike a GeometryReader.
        FlowLayout(spacing: spacing, lineSpacing: lineSpacing) {
            content()
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + lineSpacing
                totalWidth = max(totalWidth, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += rowWidth > 0 ? spacing + size.width : size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth)
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.minX + maxWidth {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Toggle row

struct WLToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    @Environment(\.wlDarkSurface) private var isDark

    var body: some View {
        let colours = SurfaceColours.forDark(isDark)
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(TypeScale.bodyBold)
                    .foregroundStyle(colours.text)
                if let subtitle {
                    Text(subtitle)
                        .font(TypeScale.captionSmall)
                        .foregroundStyle(colours.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Palette.amber)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(isDark ? colours.card : Palette.surface))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Date picker row

struct WLDateRow: View {
    let label: String
    @Binding var date: Date
    var range: ClosedRange<Date>?

    var body: some View {
        HStack {
            Text(label)
                .font(TypeScale.caption)
                .foregroundStyle(Palette.anchor)
            Spacer(minLength: 8)
            Group {
                if let range {
                    DatePicker("", selection: $date, in: range, displayedComponents: .date)
                } else {
                    DatePicker("", selection: $date, displayedComponents: .date)
                }
            }
            .labelsHidden()
            .tint(Palette.burgundy)
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(PlateBackground(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.anchor.opacity(0.25), lineWidth: 2)
        )
    }
}

/// A date row whose value can be cleared, for optional dates.
struct WLOptionalDateRow: View {
    let label: String
    @Binding var date: Date?
    var addTitle: String = "Add date"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let bound = date {
                HStack {
                    DatePicker(
                        "",
                        selection: Binding(get: { bound }, set: { date = $0 }),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .tint(Palette.burgundy)
                    Spacer(minLength: 8)
                    Button { date = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Palette.anchor.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear \(label)")
                }
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(PlateBackground(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Palette.anchor.opacity(0.25), lineWidth: 2)
                )
            } else {
                Button { date = Date() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                        Text(addTitle)
                    }
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.anchor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .frame(height: 52)
                    .background(PlateBackground(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Palette.anchor.opacity(0.25), style: StrokeStyle(lineWidth: 2))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Stepper

/// A numeric stepper with the app's own look.
struct WLStepper: View {
    let label: String
    @Binding var value: Int
    var range: ClosedRange<Int> = 0...99
    var step: Int = 1
    var valueText: String?

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(TypeScale.caption)
                .foregroundStyle(Palette.anchor)
            Spacer(minLength: 8)
            HStack(spacing: 0) {
                stepButton(systemName: "minus", enabled: value > range.lowerBound) {
                    value = max(value - step, range.lowerBound)
                }
                Text(valueText ?? "\(value)")
                    .font(.system(size: 17, weight: .black).monospacedDigit())
                    .foregroundStyle(Palette.anchor)
                    .frame(minWidth: 56)
                stepButton(systemName: "plus", enabled: value < range.upperBound) {
                    value = min(value + step, range.upperBound)
                }
            }
            .background(Capsule().fill(Palette.surface))
            .overlay(Capsule().strokeBorder(Palette.anchor.opacity(0.25), lineWidth: 2))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(valueText ?? "\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + step, range.upperBound)
            case .decrement: value = max(value - step, range.lowerBound)
            default: break
            }
        }
    }

    private func stepButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(enabled ? Palette.anchor : Palette.anchor.opacity(0.25))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Two-handled temperature range control.
struct TemperatureRangeControl: View {
    @Binding var minValue: Double
    @Binding var maxValue: Double
    var units: MeasurementUnits
    var bounds: ClosedRange<Double> = -20...40

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(UnitFormatter.temperatureRange(minValue, maxValue, units: units))
                .font(TypeScale.bodyBold)
                .foregroundStyle(Palette.anchor)

            VStack(spacing: 6) {
                labelledSlider(
                    title: "From",
                    value: Binding(
                        get: { minValue },
                        set: { minValue = min($0, maxValue - 1) }
                    )
                )
                labelledSlider(
                    title: "To",
                    value: Binding(
                        get: { maxValue },
                        set: { maxValue = max($0, minValue + 1) }
                    )
                )
            }
        }
    }

    private func labelledSlider(title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(TypeScale.captionSmall)
                .foregroundStyle(Palette.anchor.opacity(0.6))
                .frame(width: 34, alignment: .leading)
            Slider(value: value, in: bounds, step: 1)
                .tint(Palette.amber)
            Text(UnitFormatter.temperature(value.wrappedValue, units: units))
                .font(.system(size: 13, weight: .bold).monospacedDigit())
                .foregroundStyle(Palette.anchor)
                .frame(width: 56, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) temperature")
        .accessibilityValue(UnitFormatter.temperature(value.wrappedValue, units: units))
    }
}
