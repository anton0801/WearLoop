//
//  AvailabilityEngine.swift
//  WearLoop
//
//  Turns the current wardrobe into the plain sentences shown in "Outfit Check".
//  Nothing here is stored, so an outfit's status can never be out of date.
//

import Foundation

enum AvailabilityEngine {

    /// Everything the app can say about an outfit right now.
    static func check(outfit: Outfit, state: AppState, referenceDate: Date = Date()) -> OutfitCheck {
        var notes: [String] = []
        var inWash: [UUID] = []
        var needsRepair: [UUID] = []
        var stored: [UUID] = []
        var archived: [UUID] = []
        var earliestReturn: Date?
        var neverWorn = 0
        var colourCounts: [PieceColour: Int] = [:]

        let resolved = outfit.items.compactMap { state.piece($0.pieceID) }
        // Items whose piece no longer exists at all.
        let missing = outfit.items.filter { state.piece($0.pieceID) == nil }.map(\.pieceID)

        for piece in resolved {
            switch piece.status {
            case .inWash:
                inWash.append(piece.id)
                if let back = piece.expectedBackDate {
                    earliestReturn = earliestReturn.map { max($0, back) } ?? back
                }
            case .needsRepair:
                needsRepair.append(piece.id)
            case .storedAway:
                stored.append(piece.id)
            case .archived:
                archived.append(piece.id)
            case .inRotation:
                break
            }
            if state.wearCount(forPiece: piece.id) == 0 { neverWorn += 1 }
            colourCounts[piece.primaryColour, default: 0] += 1
        }

        let unavailable = inWash + needsRepair + stored + archived

        // MARK: Status

        var status: OutfitStatus = .ready
        if !needsRepair.isEmpty {
            status = .needsRepair
        } else if !unavailable.isEmpty || !missing.isEmpty {
            status = .partlyUnavailable
        } else if !isInSeason(outfit: outfit, on: referenceDate) {
            status = .outOfSeason
        }

        // MARK: Sentences

        if resolved.count < 2 {
            notes.append(resolved.isEmpty
                ? "Every piece in this outfit has been deleted."
                : "Only one piece is left in this outfit. Add another to plan with it.")
        }

        if unavailable.isEmpty && missing.isEmpty && resolved.count >= 2 {
            notes.append("All pieces are in rotation.")
        }

        if !inWash.isEmpty {
            let names = pieceNames(inWash, state: state)
            if let back = earliestReturn {
                let dayText = DateFormatterCache.relativeDayText(back, now: referenceDate)
                notes.append(inWash.count == 1
                    ? "\(names): in the wash until \(dayText)."
                    : "\(Plural.count(inWash.count, "piece")) are in the wash until \(dayText).")
            } else {
                notes.append(inWash.count == 1
                    ? "\(names): in the wash."
                    : "\(Plural.count(inWash.count, "piece")) are in the wash.")
            }
        }

        if !needsRepair.isEmpty {
            notes.append(needsRepair.count == 1
                ? "\(pieceNames(needsRepair, state: state)): needs repair."
                : "\(Plural.count(needsRepair.count, "piece")) need repair.")
        }

        if !stored.isEmpty {
            notes.append(stored.count == 1
                ? "\(pieceNames(stored, state: state)): stored away."
                : "\(Plural.count(stored.count, "piece")) are stored away.")
        }

        if !archived.isEmpty {
            notes.append(archived.count == 1
                ? "\(pieceNames(archived, state: state)): archived."
                : "\(Plural.count(archived.count, "piece")) are archived.")
        }

        if !missing.isEmpty {
            notes.append("\(Plural.count(missing.count, "piece")) in this outfit no longer exist.")
        }

        notes.append("Suitable for \(UnitFormatter.temperatureRange(outfit.temperatureMin, outfit.temperatureMax, units: state.profile.units)) by your own ranges.")

        if neverWorn > 0 {
            notes.append(neverWorn == 1
                ? "One piece has never been worn."
                : "\(Plural.count(neverWorn, "piece")) have never been worn.")
        }

        if let repeated = colourCounts.first(where: { $0.value >= 3 }) {
            notes.append("Colour repeat: \(Plural.count(repeated.value, "piece")) share \(repeated.key.title.lowercased()).")
        }

        if status == .outOfSeason {
            let season = Season.forMonth(Calendar.wl.component(.month, from: referenceDate))
            notes.append("Set for \(outfit.seasons.map(\.title).joined(separator: ", ").lowercased()), and it is \(season.title.lowercased()) now.")
        }

        return OutfitCheck(
            status: status,
            notes: notes,
            missingPieceIDs: missing,
            inWashPieceIDs: inWash,
            needsRepairPieceIDs: needsRepair,
            unavailablePieceIDs: unavailable,
            earliestReturn: earliestReturn,
            neverWornCount: neverWorn
        )
    }

    /// True when the outfit covers the season of the given date.
    static func isInSeason(outfit: Outfit, on date: Date) -> Bool {
        guard !outfit.seasons.isEmpty else { return true }
        if outfit.seasons.contains(.allYear) { return true }
        let season = Season.forMonth(Calendar.wl.component(.month, from: date))
        return outfit.seasons.contains(season)
    }

    /// Whether an outfit can be assigned to a plan at all.
    static func isAssignable(outfit: Outfit, state: AppState) -> Bool {
        let resolved = outfit.items.compactMap { state.piece($0.pieceID) }
        guard resolved.count >= 2 else { return false }
        return resolved.allSatisfy { $0.status.isAvailable }
    }

    private static func pieceNames(_ ids: [UUID], state: AppState) -> String {
        let names = ids.compactMap { state.piece($0)?.name }
        return names.first ?? "A piece"
    }

    // MARK: - Temperature

    /// Derives a temperature range from a set of pieces. The overlap of their
    /// season bands is used when there is one; otherwise the average is taken
    /// and the caller is told the range was widened.
    static func derivedTemperatureRange(pieceIDs: [UUID], state: AppState) -> (min: Double, max: Double, widened: Bool) {
        let bands = pieceIDs.compactMap { state.piece($0)?.temperatureBand }
        guard !bands.isEmpty else { return (5, 20, false) }

        let lower = bands.map(\.lowerBound).max() ?? 5
        let upper = bands.map(\.upperBound).min() ?? 20

        if lower + 2 <= upper {
            return (lower, upper, false)
        }
        // The pieces disagree about the weather: average their bands instead.
        let averageLower = bands.map(\.lowerBound).reduce(0, +) / Double(bands.count)
        let averageUpper = bands.map(\.upperBound).reduce(0, +) / Double(bands.count)
        return (averageLower.rounded(), max(averageUpper.rounded(), averageLower.rounded() + 4), true)
    }

    /// Seasons shared by all pieces, or the union when they share none.
    static func derivedSeasons(pieceIDs: [UUID], state: AppState) -> [Season] {
        let seasonSets = pieceIDs.compactMap { state.piece($0)?.seasons }.filter { !$0.isEmpty }
        guard let first = seasonSets.first else { return [] }

        var shared = Set(first)
        for set in seasonSets.dropFirst() { shared.formIntersection(Set(set)) }
        if !shared.isEmpty {
            return Season.allCases.filter { shared.contains($0) }
        }
        // Pieces with an "All Year" item should not wipe out the whole list.
        var union = Set<Season>()
        for set in seasonSets { union.formUnion(Set(set)) }
        return Season.allCases.filter { union.contains($0) }
    }

    /// Highest formality implied by the pieces of an outfit.
    static func derivedFormality(pieceIDs: [UUID], state: AppState) -> Formality {
        let occasions = pieceIDs.compactMap { state.piece($0)?.occasions }.flatMap { $0 }
        guard !occasions.isEmpty else { return .casual }
        return occasions.map(\.impliedFormality).max(by: { $0.rank < $1.rank }) ?? .casual
    }

    // MARK: - Weather mismatch

    /// Message shown when the weather falls outside the outfit's own range.
    static func weatherMismatch(
        outfit: Outfit,
        weather: WeatherInput,
        units: MeasurementUnits,
        dayLabel: String
    ) -> String? {
        let temperature = weather.temperatureC
        guard temperature < outfit.temperatureMin - 0.5 || temperature > outfit.temperatureMax + 0.5 else {
            return nil
        }
        let range = UnitFormatter.temperatureRange(outfit.temperatureMin, outfit.temperatureMax, units: units)
        let actual = UnitFormatter.temperature(temperature, units: units)
        return "This outfit is set for \(range). \(dayLabel) is \(actual)."
    }

    /// Message shown when rain is expected and nothing in the outfit covers it.
    static func rainWarning(outfit: Outfit, weather: WeatherInput, state: AppState) -> String? {
        guard weather.rain else { return nil }
        let hasOuterLayer = outfit.items.contains { item in
            item.layer == .outer && state.piece(item.pieceID) != nil
        }
        return hasOuterLayer ? nil : "Rain is expected and this outfit has no outer layer."
    }

    /// Message shown when the outfit sits below the required formality.
    static func formalityMismatch(outfit: Outfit, required: Formality, requiredLabel: String) -> String? {
        guard outfit.formality.rank < required.rank else { return nil }
        return "This outfit is \(outfit.formality.title). The \(requiredLabel) is \(required.title)."
    }
}
