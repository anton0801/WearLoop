//
//  LuggageEngine.swift
//  WearLoop
//
//  Weight of a packing list, and concrete ways to get under the limit.
//

import Foundation

struct LuggageLine: Identifiable, Hashable {
    var id: UUID
    var name: String
    var grams: Double
    var isEstimate: Bool
    var pieceID: UUID?
    var dayNumbers: [Int]
    var source: PackingSource
}

struct LuggageEstimate {
    var lines: [LuggageLine]
    var totalGrams: Double
    var limitGrams: Double?
    var estimatedLineCount: Int
    var estimatedValue: Double

    var isOverLimit: Bool {
        guard let limitGrams else { return false }
        return totalGrams > limitGrams
    }

    var overByGrams: Double {
        guard let limitGrams, totalGrams > limitGrams else { return 0 }
        return totalGrams - limitGrams
    }

    /// How full the bag is, clamped for the gauge.
    var fillFraction: Double {
        guard let limitGrams, limitGrams > 0 else { return 0 }
        return min(totalGrams / limitGrams, 1.35)
    }

    var heaviest: [LuggageLine] {
        lines.sorted { $0.grams > $1.grams }.prefix(5).map { $0 }
    }
}

/// A specific, actionable way to lose weight.
struct LuggageSuggestion: Identifiable, Hashable {
    var id: UUID
    var pieceID: UUID?
    /// The item the suggestion is about, shown as the row's title.
    var name: String
    var text: String
    var savingGrams: Double
}

enum LuggageEngine {

    static func estimate(trip: Trip, state: AppState) -> LuggageEstimate {
        var lines: [LuggageLine] = []
        var estimatedCount = 0
        var value: Double = 0

        for entry in trip.activePacking {
            if let pieceID = entry.pieceID {
                guard let piece = state.piece(pieceID) else { continue }
                let weight = piece.estimatedWeight(categoryWeights: state.categoryWeights)
                if weight.isEstimate { estimatedCount += 1 }
                value += piece.purchasePrice ?? 0
                lines.append(
                    LuggageLine(
                        id: entry.id,
                        name: piece.name,
                        grams: weight.grams,
                        isEstimate: weight.isEstimate,
                        pieceID: pieceID,
                        dayNumbers: entry.dayNumbers,
                        source: entry.source
                    )
                )
            } else {
                let grams = entry.manualWeightGrams ?? 0
                lines.append(
                    LuggageLine(
                        id: entry.id,
                        name: entry.manualName ?? "Item",
                        grams: grams,
                        isEstimate: entry.manualWeightGrams == nil,
                        pieceID: nil,
                        dayNumbers: entry.dayNumbers,
                        source: entry.source
                    )
                )
                if entry.manualWeightGrams == nil { estimatedCount += 1 }
            }
        }

        let total = lines.reduce(0) { $0 + $1.grams }
        let limitGrams = trip.luggageType.allowsLimit ? trip.weightLimitKg.map { $0 * 1000 } : nil

        return LuggageEstimate(
            lines: lines,
            totalGrams: total,
            limitGrams: limitGrams,
            estimatedLineCount: estimatedCount,
            estimatedValue: value
        )
    }

    /// The headline sentence about the bag.
    static func summarySentence(estimate: LuggageEstimate, units: MeasurementUnits) -> String {
        let total = UnitFormatter.bagWeight(grams: estimate.totalGrams, units: units)
        guard let limitGrams = estimate.limitGrams else {
            return "Estimated \(total). No limit set for this bag."
        }
        let limit = UnitFormatter.bagWeight(grams: limitGrams, units: units)
        if estimate.isOverLimit {
            let over = UnitFormatter.bagWeight(grams: estimate.overByGrams, units: units)
            return "Estimated \(total) of a \(limit) limit. Over by \(over)."
        }
        let spare = UnitFormatter.bagWeight(grams: limitGrams - estimate.totalGrams, units: units)
        return "Estimated \(total) of a \(limit) limit. \(spare) to spare."
    }

    /// Warning about how much of the estimate is guesswork.
    static func estimateNote(estimate: LuggageEstimate) -> String? {
        guard estimate.estimatedLineCount > 0 else { return nil }
        return estimate.estimatedLineCount == 1
            ? "One item uses a category average. Enter a real weight for a better estimate."
            : "\(Plural.count(estimate.estimatedLineCount, "item")) use category averages. Enter real weights for a better estimate."
    }

    /// Concrete cuts: heavy pieces, and pieces only one day needs.
    static func suggestions(trip: Trip, state: AppState, estimate: LuggageEstimate, units: MeasurementUnits) -> [LuggageSuggestion] {
        var results: [LuggageSuggestion] = []

        // Pieces used by a single day are the cheapest thing to drop.
        let singleUse = estimate.lines
            .filter { $0.source == .fromOutfits && $0.dayNumbers.count == 1 && $0.grams >= 150 }
            .sorted { $0.grams > $1.grams }
            .prefix(3)

        for line in singleUse {
            let saving = UnitFormatter.bagWeight(grams: line.grams, units: units)
            results.append(
                LuggageSuggestion(
                    id: line.id,
                    pieceID: line.pieceID,
                    name: line.name,
                    text: "Only day \(line.dayNumbers[0]) needs this. Leaving it behind saves \(saving).",
                    savingGrams: line.grams
                )
            )
        }

        // Then simply the heaviest things in the bag.
        for line in estimate.heaviest where !results.contains(where: { $0.id == line.id }) {
            guard line.grams >= 400, results.count < 5 else { continue }
            let saving = UnitFormatter.bagWeight(grams: line.grams, units: units)
            let days = line.dayNumbers.isEmpty
                ? "Not tied to any day."
                : "Needed on \(Plural.days(line.dayNumbers))."
            results.append(
                LuggageSuggestion(
                    id: line.id,
                    pieceID: line.pieceID,
                    name: line.name,
                    text: "\(days) One of the heaviest things in the bag at \(saving).",
                    savingGrams: line.grams
                )
            )
        }

        return results
    }
}

// MARK: - Reuse across trip days

struct TripCoverage {
    var daysCovered: Int
    var daysUndecided: Int
    var daysTotal: Int
    var piecesUsedOnce: Int
    var totalPiecesUsed: Int
    /// Fraction of piece slots that are repeats rather than new pieces.
    var reuseRate: Double
    /// Sentences about which outfits and pieces repeat.
    var notes: [String]

    var daysWithoutPlan: Int { max(daysTotal - daysCovered - daysUndecided, 0) }
}

enum TripPlanEngine {

    static func coverage(trip: Trip, state: AppState) -> TripCoverage {
        var pieceDayCount: [UUID: Int] = [:]
        var outfitDays: [UUID: [Int]] = [:]
        var covered = 0
        var undecided = 0
        var slots = 0

        for day in trip.days {
            if let outfitID = day.outfitID, let outfit = state.outfit(outfitID) {
                covered += 1
                outfitDays[outfitID, default: []].append(day.dayNumber)
                for pieceID in outfit.pieceIDs {
                    pieceDayCount[pieceID, default: 0] += 1
                    slots += 1
                }
            } else if day.isUndecided {
                undecided += 1
            }
        }

        let uniquePieces = pieceDayCount.count
        let usedOnce = pieceDayCount.values.filter { $0 == 1 }.count
        let reuseRate = slots > 0 ? 1 - (Double(uniquePieces) / Double(slots)) : 0

        var notes: [String] = []

        // Outfits worn on more than one day.
        for (outfitID, days) in outfitDays.sorted(by: { $0.value.count > $1.value.count }) where days.count > 1 {
            guard let outfit = state.outfit(outfitID), notes.count < 3 else { break }
            notes.append("\(outfit.name) is used on \(Plural.days(days)).")
        }

        // Pieces appearing on three or more days pull the bag down.
        let workhorses = pieceDayCount.filter { $0.value >= 3 }.count
        if workhorses > 0 {
            notes.append(workhorses == 1
                ? "One piece appears on three or more days."
                : "\(Plural.count(workhorses, "piece")) appear on three or more days.")
        }

        // A day made entirely of pieces nothing else needs is expensive.
        for day in trip.days {
            guard let outfitID = day.outfitID, let outfit = state.outfit(outfitID) else { continue }
            let exclusive = outfit.pieceIDs.filter { pieceDayCount[$0] == 1 }
            if exclusive.count >= 4, notes.count < 5 {
                notes.append("Day \(day.dayNumber) uses \(Plural.count(exclusive.count, "piece")) that appear nowhere else.")
            }
        }

        return TripCoverage(
            daysCovered: covered,
            daysUndecided: undecided,
            daysTotal: trip.days.count,
            piecesUsedOnce: usedOnce,
            totalPiecesUsed: uniquePieces,
            reuseRate: max(reuseRate, 0),
            notes: notes
        )
    }

    /// Which days need a given piece, for "Why Is This Here?".
    static func daysNeeding(pieceID: UUID, trip: Trip, state: AppState) -> [Int] {
        trip.days.compactMap { day in
            guard let outfitID = day.outfitID,
                  let outfit = state.outfit(outfitID),
                  outfit.contains(pieceID: pieceID) else { return nil }
            return day.dayNumber
        }
    }

    /// Outfits that no longer suit the trip's conditions after an edit.
    static func outfitsOutsideConditions(trip: Trip, state: AppState) -> Set<UUID> {
        var result = Set<UUID>()
        for day in trip.days {
            guard let outfitID = day.outfitID, let outfit = state.outfit(outfitID) else { continue }
            let noOverlap = outfit.temperatureMax < trip.temperatureMin - 1
                || outfit.temperatureMin > trip.temperatureMax + 1
            if noOverlap { result.insert(outfitID) }
            if let required = day.requiredFormality, outfit.formality.rank < required.rank {
                result.insert(outfitID)
            }
        }
        return result
    }
}
