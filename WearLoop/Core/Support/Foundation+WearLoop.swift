//
//  Foundation+WearLoop.swift
//  WearLoop
//
//  Shared calendar, formatting and small helpers used across the whole app.
//

import SwiftUI

// MARK: - Calendar

extension Calendar {
    /// One calendar for the whole app so day maths never disagrees with itself.
    static let wl: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2 // Monday
        return calendar
    }()

    /// Whole days between two dates, ignoring the time of day.
    func dayCount(from start: Date, to end: Date) -> Int {
        let a = startOfDay(for: start)
        let b = startOfDay(for: end)
        return dateComponents([.day], from: a, to: b).day ?? 0
    }

    func addingDays(_ days: Int, to date: Date) -> Date {
        self.date(byAdding: .day, value: days, to: date) ?? date
    }

    func isSameDay(_ a: Date, _ b: Date) -> Bool {
        startOfDay(for: a) == startOfDay(for: b)
    }
}

extension Date {
    var wlStartOfDay: Date { Calendar.wl.startOfDay(for: self) }

    /// Inclusive list of days from this date to `end`.
    func wlDays(through end: Date) -> [Date] {
        var result: [Date] = []
        var cursor = wlStartOfDay
        let last = end.wlStartOfDay
        while cursor <= last, result.count < 400 {
            result.append(cursor)
            cursor = Calendar.wl.addingDays(1, to: cursor)
        }
        return result
    }
}

// MARK: - Date text

/// Formatters are expensive to build, so they are made once.
enum DateFormatterCache {
    static let dayMonth: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f
    }()

    static let dayMonthYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    static let weekdayShort: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    static let weekdayLong: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()

    static let dayNumber: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()

    static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        return f
    }()

    static let fileStamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return f
    }()

    static func rangeText(_ start: Date, _ end: Date) -> String {
        let calendar = Calendar.wl
        if calendar.isSameDay(start, end) {
            return dayMonthYear.string(from: start)
        }
        let sameYear = calendar.component(.year, from: start) == calendar.component(.year, from: end)
        if sameYear {
            return "\(dayMonth.string(from: start)) – \(dayMonthYear.string(from: end))"
        }
        return "\(dayMonthYear.string(from: start)) – \(dayMonthYear.string(from: end))"
    }

    /// "today", "tomorrow", "Friday" or a date, whichever reads best.
    static func relativeDayText(_ date: Date, now: Date = Date()) -> String {
        let days = Calendar.wl.dayCount(from: now, to: date)
        switch days {
        case 0: return "today"
        case 1: return "tomorrow"
        case -1: return "yesterday"
        case 2...6: return weekdayLong.string(from: date)
        default: return dayMonth.string(from: date)
        }
    }
}

// MARK: - Units

enum UnitFormatter {
    static func temperature(_ celsius: Double, units: MeasurementUnits) -> String {
        switch units {
        case .metric:
            return "\(Int(celsius.rounded())) °C"
        case .imperial:
            return "\(Int((celsius * 9 / 5 + 32).rounded())) °F"
        }
    }

    static func temperatureRange(_ min: Double, _ max: Double, units: MeasurementUnits) -> String {
        switch units {
        case .metric:
            return "\(Int(min.rounded())) to \(Int(max.rounded())) °C"
        case .imperial:
            return "\(Int((min * 9 / 5 + 32).rounded())) to \(Int((max * 9 / 5 + 32).rounded())) °F"
        }
    }

    /// Weight from grams, in the user's units, with one decimal.
    static func weight(grams: Double, units: MeasurementUnits) -> String {
        switch units {
        case .metric:
            let kg = grams / 1000
            return kg < 1
                ? "\(Int(grams.rounded())) g"
                : String(format: "%.1f kg", kg)
        case .imperial:
            let lb = grams / 453.592
            return lb < 1
                ? String(format: "%.1f oz", grams / 28.3495)
                : String(format: "%.1f lb", lb)
        }
    }

    /// Weight of a whole bag, always shown in the large unit.
    static func bagWeight(grams: Double, units: MeasurementUnits) -> String {
        switch units {
        case .metric: return String(format: "%.1f kg", grams / 1000)
        case .imperial: return String(format: "%.1f lb", grams / 453.592)
        }
    }

    static func limit(kg: Double, units: MeasurementUnits) -> String {
        switch units {
        case .metric: return String(format: "%.1f kg", kg)
        case .imperial: return String(format: "%.1f lb", kg * 2.20462)
        }
    }

    static func money(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = value < 100 ? 2 : 0
        formatter.locale = .current
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }
}

// MARK: - Colour

extension Color {
    /// Builds a colour from "#RRGGBB" or "RRGGBB".
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r, g, b, a: Double
        switch cleaned.count {
        case 8:
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        case 6:
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        default:
            r = 0; g = 0; b = 0; a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

// MARK: - Collections

extension Array where Element: Hashable {
    /// Keeps the first occurrence of each element and drops later duplicates.
    var wlUnique: [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }

    /// Adds or removes an element, for chip pickers.
    mutating func wlToggle(_ element: Element) {
        if let index = firstIndex(of: element) {
            remove(at: index)
        } else {
            append(element)
        }
    }
}

extension String {
    var wlTrimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var wlIsBlank: Bool { wlTrimmed.isEmpty }

    /// First letter used by the generated cover of a piece with no photo.
    var wlInitial: String {
        guard let first = wlTrimmed.first else { return "?" }
        return String(first).uppercased()
    }
}

// MARK: - Dictionary keys

/// Lets `[PieceCategory: Double]` encode as a readable JSON object.
extension PieceCategory: CodingKeyRepresentable {}

// MARK: - Grammar

enum Plural {
    /// "1 piece" / "3 pieces"
    static func count(_ n: Int, _ singular: String, _ plural: String? = nil) -> String {
        let word = n == 1 ? singular : (plural ?? singular + "s")
        return "\(n) \(word)"
    }

    /// "day 1" / "days 1 and 4" / "days 1, 3 and 6"
    static func list(_ values: [Int]) -> String {
        let sorted = values.sorted()
        switch sorted.count {
        case 0: return ""
        case 1: return "\(sorted[0])"
        case 2: return "\(sorted[0]) and \(sorted[1])"
        default:
            guard let last = sorted.last else { return "" }
            let head = sorted.dropLast().map(String.init).joined(separator: ", ")
            return "\(head) and \(last)"
        }
    }

    /// "days 1 and 4" with the right leading word.
    static func days(_ values: [Int]) -> String {
        let word = values.count == 1 ? "day" : "days"
        return "\(word) \(list(values))"
    }
}
