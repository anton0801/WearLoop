//
//  TripReadinessEngine.swift
//  WearLoop
//
//  The pre-departure checklist, and the rules about which trip stage the user
//  may move to next.
//

import Foundation

/// One line of the readiness checklist.
struct ReadinessItem: Identifiable, Hashable {
    enum Target: Hashable {
        case dayPlan
        case laundry
        case weightCheck
        case packingList
        case conditions
        case repairs
    }

    var id: String
    var title: String
    var isPassed: Bool
    /// Why it has not passed yet, or a confirmation when it has.
    var detail: String
    var target: Target
}

struct TripReadiness {
    var items: [ReadinessItem]

    var passedCount: Int { items.filter(\.isPassed).count }
    var totalCount: Int { items.count }
    var isReady: Bool { passedCount == totalCount }
    var outstanding: [ReadinessItem] { items.filter { !$0.isPassed } }
}

enum TripReadinessEngine {

    static func readiness(trip: Trip, state: AppState, now: Date = Date()) -> TripReadiness {
        var items: [ReadinessItem] = []

        // 1. Every day has an outfit or an explicit Undecided.
        let unplanned = trip.daysWithoutPlan
        items.append(
            ReadinessItem(
                id: "days",
                title: "All Days Have Outfits",
                isPassed: unplanned.isEmpty,
                detail: unplanned.isEmpty
                    ? "\(Plural.count(trip.dayCount, "day")) planned."
                    : "\(Plural.days(unplanned.map(\.dayNumber))) still need an outfit or an Undecided mark.",
                target: .dayPlan
            )
        )

        // 2. Nothing needed is stuck in the wash.
        let washedNeeded = neededPieces(trip: trip, state: state).filter { $0.status == .inWash }
        items.append(
            ReadinessItem(
                id: "laundry",
                title: "No Pieces Stuck in the Wash",
                isPassed: washedNeeded.isEmpty,
                detail: washedNeeded.isEmpty
                    ? "Everything the trip needs is in rotation."
                    : "\(Plural.count(washedNeeded.count, "piece")) in this trip are still in the wash.",
                target: .laundry
            )
        )

        // 3. Weight within the limit.
        let estimate = LuggageEngine.estimate(trip: trip, state: state)
        let weightPassed = !estimate.isOverLimit
        items.append(
            ReadinessItem(
                id: "weight",
                title: "Weight Within Limit",
                isPassed: weightPassed,
                detail: estimate.limitGrams == nil
                    ? "No limit set for this bag."
                    : LuggageEngine.summarySentence(estimate: estimate, units: state.profile.units),
                target: .weightCheck
            )
        )

        // 4. Essentials ticked off.
        let essentials = trip.activePacking.filter { $0.source == .essential }
        let essentialsPacked = essentials.isEmpty ? state.essentials.filter(\.isEnabled).isEmpty : essentials.allSatisfy(\.isPacked)
        items.append(
            ReadinessItem(
                id: "essentials",
                title: "Essentials Packed",
                isPassed: essentialsPacked,
                detail: essentials.isEmpty
                    ? (state.essentials.filter(\.isEnabled).isEmpty
                        ? "No essentials list set up."
                        : "Your essentials have not been added to this trip yet.")
                    : "\(essentials.filter(\.isPacked).count) of \(essentials.count) ticked off.",
                target: .packingList
            )
        )

        // 5. Weather reviewed.
        items.append(
            ReadinessItem(
                id: "conditions",
                title: "Weather Conditions Reviewed",
                isPassed: trip.conditionsReviewed,
                detail: trip.conditionsReviewed
                    ? "Expecting \(UnitFormatter.temperatureRange(trip.temperatureMin, trip.temperatureMax, units: state.profile.units))\(trip.rainExpected ? " with rain" : "")."
                    : "Confirm the temperature range and rain for this trip.",
                target: .conditions
            )
        )

        // 6. Repairs done.
        let brokenNeeded = neededPieces(trip: trip, state: state).filter { $0.status == .needsRepair }
        items.append(
            ReadinessItem(
                id: "repairs",
                title: "Repairs Completed",
                isPassed: brokenNeeded.isEmpty,
                detail: brokenNeeded.isEmpty
                    ? "Nothing in this trip needs repair."
                    : "\(Plural.count(brokenNeeded.count, "piece")) in this trip need repair.",
                target: .repairs
            )
        )

        return TripReadiness(items: items)
    }

    /// Pieces the trip depends on, from its day outfits and its packing list.
    static func neededPieces(trip: Trip, state: AppState) -> [Piece] {
        var ids = Set<UUID>()
        for day in trip.days {
            guard let outfitID = day.outfitID, let outfit = state.outfit(outfitID) else { continue }
            ids.formUnion(outfit.pieceIDs)
        }
        for entry in trip.activePacking {
            if let pieceID = entry.pieceID { ids.insert(pieceID) }
        }
        return ids.compactMap { state.piece($0) }
    }

    // MARK: - Stage rules

    /// Why the user cannot move to a stage yet, or nil when they can.
    static func blockReason(for stage: TripStage, trip: Trip, state: AppState) -> String? {
        switch stage {
        case .setup:
            return nil

        case .dayPlan:
            if trip.days.isEmpty { return "This trip has no days yet. Set its dates first." }
            return nil

        case .packingList:
            let unplanned = trip.daysWithoutPlan
            guard unplanned.isEmpty else {
                return unplanned.count == 1
                    ? "Day \(unplanned[0].dayNumber) needs an outfit or an Undecided mark before you can pack."
                    : "\(Plural.days(unplanned.map(\.dayNumber))) need an outfit or an Undecided mark before you can pack."
            }
            return nil

        case .weightCheck:
            if let reason = blockReason(for: .packingList, trip: trip, state: state) { return reason }
            if trip.activePacking.isEmpty { return "Nothing is on the packing list yet." }
            return nil

        case .ready:
            if let reason = blockReason(for: .weightCheck, trip: trip, state: state) { return reason }
            return nil

        case .inProgress:
            if trip.stage.order < TripStage.ready.order {
                return "Mark the trip as ready before starting it."
            }
            return nil

        case .recap:
            let unlogged = trip.days.filter { !$0.isLogged }
            guard unlogged.isEmpty else {
                return "\(Plural.days(unlogged.map(\.dayNumber))) have no record of what you wore."
            }
            return nil
        }
    }

    /// Stage the trip should sit at, given how much has been filled in.
    static func suggestedStage(trip: Trip, state: AppState) -> TripStage {
        if trip.recap != nil { return .recap }
        if trip.stage == .inProgress { return .inProgress }
        if trip.stage == .ready { return .ready }
        if trip.days.isEmpty { return .setup }
        if !trip.daysWithoutPlan.isEmpty { return .dayPlan }
        if trip.activePacking.isEmpty { return .packingList }
        return .weightCheck
    }
}

// MARK: - Recap

enum TripRecapEngine {

    /// Builds the plan-against-reality summary for a finished trip.
    static func build(trip: Trip, state: AppState, finishedWithoutRecords: Bool = false) -> TripRecapData {
        // Accuracy is measured over wardrobe pieces only: essentials and
        // free-text lines cannot be "worn", so counting them would drag the
        // figure down for no reason.
        let packedEntries = trip.activePacking.filter { $0.isPacked && $0.pieceID != nil }
        let packedPieceIDs = Set(packedEntries.compactMap(\.pieceID))

        // What was actually worn on this trip.
        let tripRecords = state.wearRecords.filter { $0.tripID == trip.id }
        let wornPieceIDs = Set(tripRecords.flatMap(\.pieceIDs))

        let neverWorn = packedPieceIDs.subtracting(wornPieceIDs)
        let wornNotPacked = wornPieceIDs.subtracting(packedPieceIDs)

        // Days where the record differs from the plan.
        var changed = 0
        for day in trip.days {
            guard let recordID = day.wearRecordID, let record = state.wearRecord(recordID) else { continue }
            if let planned = day.outfitID, record.outfitID != planned { changed += 1 }
            else if day.outfitID == nil && record.outfitID != nil { changed += 1 }
            else if record.wasUnplanned { changed += 1 }
        }

        let estimate = LuggageEngine.estimate(trip: trip, state: state)

        return TripRecapData(
            packedCount: packedEntries.count,
            wornCount: wornPieceIDs.intersection(packedPieceIDs).count,
            neverWornPieceIDs: Array(neverWorn),
            wornNotPackedPieceIDs: Array(wornNotPacked),
            outfitsChangedCount: changed,
            laundryLoadsDone: trip.laundryOnRoadCount,
            finalWeightKg: estimate.totalGrams / 1000,
            savedAt: Date(),
            note: "",
            finishedWithoutRecords: finishedWithoutRecords
        )
    }

    /// The lesson the user can carry to the next trip.
    static func conclusions(trip: Trip, recap: TripRecapData, state: AppState) -> [String] {
        var lines: [String] = []

        if recap.packedCount > 0 {
            lines.append("You packed \(Plural.count(recap.packedCount, "piece")) and wore \(recap.wornCount).")
        }

        // Pieces that travelled twice without being worn are worth naming.
        for pieceID in recap.neverWornPieceIDs.prefix(3) {
            guard let piece = state.piece(pieceID) else { continue }
            let unwornTrips = state.trips.filter { other in
                guard let otherRecap = other.recap else { return false }
                return otherRecap.neverWornPieceIDs.contains(pieceID)
            }.count
            if unwornTrips >= 2 {
                lines.append("\(piece.name): travelled and stayed in the bag on \(unwornTrips) trips.")
            } else {
                lines.append("\(piece.name): travelled and was never worn.")
            }
        }

        if recap.outfitsChangedCount > 0 {
            lines.append("You changed the plan on \(Plural.count(recap.outfitsChangedCount, "day")).")
        }

        if !recap.wornNotPackedPieceIDs.isEmpty {
            lines.append("\(Plural.count(recap.wornNotPackedPieceIDs.count, "piece")) you wore were never on the packing list.")
        }

        if recap.packedCount > 0 && recap.wornCount == recap.packedCount {
            lines.append("Everything you packed was worn. This is a packing list worth keeping.")
        }

        return lines
    }
}
