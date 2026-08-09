//
//  WardrobeActions.swift
//  WearLoop
//
//  Every cross-cutting change to the wardrobe lives here, so that one edit
//  reaches all sections at once: a shirt sent to the wash makes its outfits
//  partly unavailable, drops out of packing lists and shows a return date.
//

import Foundation

enum WardrobeActions {

    // MARK: - Laundry

    /// Sends pieces to the wash basket and marks them unavailable.
    static func sendToWash(pieceIDs: [UUID], in state: inout AppState, now: Date = Date()) {
        let expected = Calendar.wl.addingDays(state.profile.laundryCycle.expectedDays, to: now)
        for pieceID in pieceIDs {
            guard let index = state.pieces.firstIndex(where: { $0.id == pieceID }) else { continue }
            guard state.pieces[index].status != .inWash else { continue }
            state.pieces[index].status = .inWash
            state.pieces[index].expectedBackDate = expected
            state.pieces[index].updatedAt = now

            if !state.washBasket.contains(pieceID) {
                state.washBasket.append(pieceID)
            }
            state.laundryRecords.append(
                LaundryRecord(
                    pieceID: pieceID,
                    snapshot: PieceSnapshot(piece: state.pieces[index]),
                    loadName: "Sent to wash",
                    sentAt: now,
                    returnedAt: nil,
                    temperatureC: nil
                )
            )
        }
        // A piece in the wash cannot be packed on an unfinished trip.
        unpackWashedPieces(pieceIDs, in: &state)
    }

    /// Starts a load from basketed pieces.
    static func startLoad(
        name: String,
        pieceIDs: [UUID],
        temperatureC: Int,
        notes: String,
        in state: inout AppState,
        now: Date = Date()
    ) {
        let expected = Calendar.wl.addingDays(state.profile.laundryCycle.expectedDays, to: now)
        let snapshots = pieceIDs.compactMap { id in state.piece(id).map(PieceSnapshot.init(piece:)) }
        let load = LaundryLoad(
            name: name.wlIsBlank ? "Wash load" : name.wlTrimmed,
            pieceIDs: pieceIDs,
            snapshots: snapshots,
            temperatureC: temperatureC,
            startedAt: now,
            expectedReady: expected,
            notes: notes,
            stage: .washingNow
        )
        state.laundryLoads.append(load)
        state.washBasket.removeAll { pieceIDs.contains($0) }

        for pieceID in pieceIDs {
            guard let index = state.pieces.firstIndex(where: { $0.id == pieceID }) else { continue }
            state.pieces[index].status = .inWash
            state.pieces[index].expectedBackDate = expected
            state.pieces[index].updatedAt = now
            // Keep the open laundry record in step with the load it joined.
            if let recordIndex = state.laundryRecords.lastIndex(where: { $0.pieceID == pieceID && $0.returnedAt == nil }) {
                state.laundryRecords[recordIndex].loadName = load.name
                state.laundryRecords[recordIndex].temperatureC = temperatureC
            }
        }
        unpackWashedPieces(pieceIDs, in: &state)
    }

    static func advanceLoad(_ loadID: UUID, to stage: LaundryStage, in state: inout AppState, now: Date = Date()) {
        guard let index = state.laundryLoads.firstIndex(where: { $0.id == loadID }) else { return }
        state.laundryLoads[index].stage = stage
        if stage == .drying, state.laundryLoads[index].expectedReady == nil {
            state.laundryLoads[index].expectedReady = Calendar.wl.addingDays(1, to: now)
        }
    }

    /// Returns pieces to rotation and closes their laundry history entries.
    static func returnFromWash(pieceIDs: [UUID], in state: inout AppState, now: Date = Date()) {
        for pieceID in pieceIDs {
            if let index = state.pieces.firstIndex(where: { $0.id == pieceID }) {
                // A piece reported broken stays broken even after a wash.
                let hasOpenRepair = state.repairs.contains { $0.pieceID == pieceID && $0.isOpen }
                state.pieces[index].status = hasOpenRepair ? .needsRepair : .inRotation
                state.pieces[index].expectedBackDate = nil
                state.pieces[index].updatedAt = now
            }
            if let recordIndex = state.laundryRecords.lastIndex(where: { $0.pieceID == pieceID && $0.returnedAt == nil }) {
                state.laundryRecords[recordIndex].returnedAt = now
            }
            state.washBasket.removeAll { $0 == pieceID }
        }
        // Drop the pieces from their loads and remove loads that are now empty.
        for index in state.laundryLoads.indices {
            state.laundryLoads[index].pieceIDs.removeAll { pieceIDs.contains($0) }
        }
        state.laundryLoads.removeAll { $0.pieceIDs.isEmpty }
    }

    /// Pulls washed pieces out of packing lists on trips that have not finished.
    private static func unpackWashedPieces(_ pieceIDs: [UUID], in state: inout AppState) {
        for tripIndex in state.trips.indices where state.trips[tripIndex].phase != .completed {
            for entryIndex in state.trips[tripIndex].packing.indices {
                guard let pieceID = state.trips[tripIndex].packing[entryIndex].pieceID,
                      pieceIDs.contains(pieceID) else { continue }
                state.trips[tripIndex].packing[entryIndex].isPacked = false
            }
        }
    }

    // MARK: - Wearing

    /// Records a confirmed wearing. Always explicit — nothing is ever marked
    /// worn automatically.
    @discardableResult
    static func recordWear(
        outfitID: UUID?,
        pieceIDs: [UUID],
        date: Date,
        context: WearContext,
        tripID: UUID? = nil,
        eventID: UUID? = nil,
        wasUnplanned: Bool = false,
        note: String = "",
        in state: inout AppState
    ) -> UUID {
        let resolvedPieceIDs: [UUID]
        if let outfitID, let outfit = state.outfit(outfitID), pieceIDs.isEmpty {
            resolvedPieceIDs = outfit.pieceIDs
        } else {
            resolvedPieceIDs = pieceIDs
        }
        let snapshots = resolvedPieceIDs.compactMap { id in state.piece(id).map(PieceSnapshot.init(piece:)) }
        let record = WearRecord(
            date: date.wlStartOfDay,
            context: context,
            outfitID: outfitID,
            outfitName: outfitID.flatMap { state.outfit($0)?.name },
            pieceSnapshots: snapshots,
            tripID: tripID,
            eventID: eventID,
            note: note,
            wasUnplanned: wasUnplanned
        )
        state.wearRecords.append(record)

        // A worn piece is no longer new.
        for pieceID in resolvedPieceIDs {
            guard let index = state.pieces.firstIndex(where: { $0.id == pieceID }) else { continue }
            if state.pieces[index].condition == .new {
                state.pieces[index].condition = .good
            }
        }
        return record.id
    }

    /// Removes a wear record and unlinks whatever pointed at it.
    static func deleteWearRecord(_ recordID: UUID, in state: inout AppState) {
        state.wearRecords.removeAll { $0.id == recordID }
        for index in state.dayPlans.indices where state.dayPlans[index].wearRecordID == recordID {
            state.dayPlans[index].wearRecordID = nil
        }
        for index in state.events.indices where state.events[index].wearRecordID == recordID {
            state.events[index].wearRecordID = nil
        }
        for tripIndex in state.trips.indices {
            for dayIndex in state.trips[tripIndex].days.indices
            where state.trips[tripIndex].days[dayIndex].wearRecordID == recordID {
                state.trips[tripIndex].days[dayIndex].wearRecordID = nil
            }
        }
    }

    // MARK: - Piece lifecycle

    static func setStatus(_ status: PieceStatus, pieceID: UUID, in state: inout AppState, now: Date = Date()) {
        guard let index = state.pieces.firstIndex(where: { $0.id == pieceID }) else { return }
        let previous = state.pieces[index].status
        state.pieces[index].status = status
        state.pieces[index].updatedAt = now
        if status != .inWash {
            state.pieces[index].expectedBackDate = nil
            if previous == .inWash {
                state.washBasket.removeAll { $0 == pieceID }
                for loadIndex in state.laundryLoads.indices {
                    state.laundryLoads[loadIndex].pieceIDs.removeAll { $0 == pieceID }
                }
                state.laundryLoads.removeAll { $0.pieceIDs.isEmpty }
                if let recordIndex = state.laundryRecords.lastIndex(where: { $0.pieceID == pieceID && $0.returnedAt == nil }) {
                    state.laundryRecords[recordIndex].returnedAt = now
                }
            }
        }
        if status == .needsRepair {
            state.pieces[index].condition = .needsRepair
        } else if state.pieces[index].condition == .needsRepair {
            state.pieces[index].condition = .good
        }
        if !status.isAvailable {
            unpackWashedPieces([pieceID], in: &state)
        }
    }

    /// Reports a problem and takes the piece out of circulation.
    static func reportRepair(pieceID: UUID, issue: String, plannedAction: String, in state: inout AppState, now: Date = Date()) {
        guard let piece = state.piece(pieceID) else { return }
        // One open issue per piece keeps the repair list honest.
        if let existing = state.repairs.firstIndex(where: { $0.pieceID == pieceID && $0.isOpen }) {
            state.repairs[existing].issue = issue.wlTrimmed
            state.repairs[existing].plannedAction = plannedAction.wlTrimmed
        } else {
            state.repairs.append(
                RepairIssue(
                    pieceID: pieceID,
                    snapshot: PieceSnapshot(piece: piece),
                    issue: issue.wlIsBlank ? "Needs repair" : issue.wlTrimmed,
                    reportedOn: now,
                    plannedAction: plannedAction.wlTrimmed
                )
            )
        }
        setStatus(.needsRepair, pieceID: pieceID, in: &state, now: now)
    }

    static func completeRepair(_ repairID: UUID, cost: Double?, in state: inout AppState, now: Date = Date()) {
        guard let index = state.repairs.firstIndex(where: { $0.id == repairID }) else { return }
        state.repairs[index].completedOn = now
        state.repairs[index].cost = cost
        let pieceID = state.repairs[index].pieceID
        // Only return it to rotation if nothing else is holding it back.
        if let pieceIndex = state.pieces.firstIndex(where: { $0.id == pieceID }),
           state.pieces[pieceIndex].status == .needsRepair {
            setStatus(.inRotation, pieceID: pieceID, in: &state, now: now)
        }
    }

    /// Retires a piece: archived, closed repairs, out of every future plan.
    static func retirePiece(_ pieceID: UUID, in state: inout AppState, now: Date = Date()) {
        for index in state.repairs.indices where state.repairs[index].pieceID == pieceID && state.repairs[index].isOpen {
            state.repairs[index].completedOn = now
        }
        setStatus(.archived, pieceID: pieceID, in: &state, now: now)
        removeFromFuturePlans(pieceID: pieceID, in: &state)
    }

    /// Clears an archived piece out of plans that have not happened yet, while
    /// leaving finished history untouched.
    private static func removeFromFuturePlans(pieceID: UUID, in state: inout AppState) {
        for tripIndex in state.trips.indices where state.trips[tripIndex].phase != .completed {
            state.trips[tripIndex].packing.removeAll { $0.pieceID == pieceID }
        }
        state.washBasket.removeAll { $0 == pieceID }
        for index in state.laundryLoads.indices {
            state.laundryLoads[index].pieceIDs.removeAll { $0 == pieceID }
        }
        state.laundryLoads.removeAll { $0.pieceIDs.isEmpty }
    }

    /// Deletes a piece. History keeps its own snapshots, so past trips and wear
    /// records still read correctly afterwards.
    static func deletePiece(_ pieceID: UUID, in state: inout AppState) {
        state.pieces.removeAll { $0.id == pieceID }

        // Outfits lose the piece; an outfit that becomes too small is reported
        // by the outfit check rather than silently deleted.
        for index in state.outfits.indices {
            let before = state.outfits[index].items.count
            state.outfits[index].items.removeAll { $0.pieceID == pieceID }
            if state.outfits[index].items.count != before {
                state.outfits[index].updatedAt = Date()
            }
        }

        for tripIndex in state.trips.indices {
            state.trips[tripIndex].packing.removeAll { $0.pieceID == pieceID }
        }

        state.washBasket.removeAll { $0 == pieceID }
        for index in state.laundryLoads.indices {
            state.laundryLoads[index].pieceIDs.removeAll { $0 == pieceID }
        }
        state.laundryLoads.removeAll { $0.pieceIDs.isEmpty }

        // Open issues disappear with the piece; completed ones stay as history.
        state.repairs.removeAll { $0.pieceID == pieceID && $0.isOpen }

        for index in state.templates.indices {
            state.templates[index].pieceIDs.removeAll { $0 == pieceID }
        }
    }

    // MARK: - Outfit lifecycle

    /// Deletes an outfit and clears every plan that pointed at it.
    static func deleteOutfit(_ outfitID: UUID, in state: inout AppState) {
        state.outfits.removeAll { $0.id == outfitID }

        for index in state.dayPlans.indices {
            if state.dayPlans[index].outfitID == outfitID { state.dayPlans[index].outfitID = nil }
            if state.dayPlans[index].backupOutfitID == outfitID { state.dayPlans[index].backupOutfitID = nil }
        }
        for index in state.events.indices {
            if state.events[index].outfitID == outfitID { state.events[index].outfitID = nil }
            if state.events[index].backupOutfitID == outfitID { state.events[index].backupOutfitID = nil }
        }
        for tripIndex in state.trips.indices {
            for dayIndex in state.trips[tripIndex].days.indices
            where state.trips[tripIndex].days[dayIndex].outfitID == outfitID {
                state.trips[tripIndex].days[dayIndex].outfitID = nil
            }
            if state.trips[tripIndex].phase != .completed {
                refreshPacking(tripID: state.trips[tripIndex].id, in: &state)
            }
        }
        // Wear records keep `outfitName`, so history still reads correctly.
    }

    // MARK: - Day plans

    /// Returns the existing plan for a date or creates an empty one.
    static func ensureDayPlan(for date: Date, in state: inout AppState) -> UUID {
        let day = date.wlStartOfDay
        if let existing = state.dayPlans.first(where: { $0.date.wlStartOfDay == day }) {
            return existing.id
        }
        let plan = DayPlan(date: day)
        state.dayPlans.append(plan)
        return plan.id
    }

    // MARK: - Trips

    /// Rebuilds the day list after the dates change, keeping the plans of days
    /// that still exist.
    static func rebuildDays(for trip: inout Trip) {
        if trip.endDate.wlStartOfDay < trip.startDate.wlStartOfDay {
            trip.endDate = trip.startDate
        }
        let dates = trip.startDate.wlDays(through: trip.endDate)
        var rebuilt: [TripDay] = []
        for (index, date) in dates.enumerated() {
            if let existing = trip.days.first(where: { $0.date.wlStartOfDay == date }) {
                var day = existing
                day.index = index
                rebuilt.append(day)
            } else {
                rebuilt.append(TripDay(index: index, date: date))
            }
        }
        trip.days = rebuilt
    }

    /// Recomputes the "From Outfits" part of a packing list from the assigned
    /// day outfits, keeping everything the user decided by hand.
    static func refreshPacking(tripID: UUID, in state: inout AppState) {
        guard let tripIndex = state.trips.firstIndex(where: { $0.id == tripID }) else { return }
        let trip = state.trips[tripIndex]

        // Which days need which piece.
        var dayNumbers: [UUID: [Int]] = [:]
        for day in trip.days {
            guard let outfitID = day.outfitID, let outfit = state.outfit(outfitID) else { continue }
            for pieceID in outfit.pieceIDs where state.piece(pieceID) != nil {
                dayNumbers[pieceID, default: []].append(day.dayNumber)
            }
        }

        var updated: [PackingEntry] = []

        // Manual lines and essentials are kept as they are, with one exception:
        // a manual line for a piece an outfit now needs is merged into that
        // outfit's line below. Keeping both would list one garment twice and
        // count its weight twice in the bag.
        updated.append(contentsOf: trip.packing.filter { entry in
            guard entry.source != .fromOutfits else { return false }
            if entry.source == .manual, let pieceID = entry.pieceID, dayNumbers[pieceID] != nil {
                return false
            }
            return true
        })

        for (pieceID, days) in dayNumbers {
            let sortedDays = days.sorted().wlUnique
            let pieceIsAvailable = state.piece(pieceID)?.status.isAvailable ?? false

            if let existing = trip.packing.first(where: { $0.pieceID == pieceID && $0.source == .fromOutfits }) {
                var entry = existing
                entry.dayNumbers = sortedDays
                // A manual line for the same garment was just folded in, so the
                // merged line inherits both the tick and the manual origin.
                if let manual = trip.packing.first(where: { $0.pieceID == pieceID && $0.source == .manual }) {
                    entry.wasAddedManually = true
                    entry.isPacked = entry.isPacked || manual.isPacked
                }
                // A piece that has left rotation cannot stay ticked as packed.
                if !pieceIsAvailable { entry.isPacked = false }
                updated.append(entry)
            } else if let existingManual = trip.packing.first(where: { $0.pieceID == pieceID && $0.source == .manual }) {
                // Already on the list by hand and now needed by an outfit too:
                // show it once, and remember it was added manually so that
                // dropping the outfit later does not silently remove it.
                var entry = existingManual
                entry.source = .fromOutfits
                entry.wasAddedManually = true
                entry.dayNumbers = sortedDays
                if !pieceIsAvailable { entry.isPacked = false }
                updated.removeAll { $0.id == existingManual.id }
                updated.append(entry)
            } else {
                updated.append(
                    PackingEntry(
                        source: .fromOutfits,
                        pieceID: pieceID,
                        dayNumbers: sortedDays
                    )
                )
            }
        }

        // A piece the user added by hand goes back to being a manual line when
        // no day needs it any more, rather than disappearing from the trip.
        for entry in trip.packing
        where entry.source == .fromOutfits
            && entry.wasAddedManually
            && !updated.contains(where: { $0.id == entry.id }) {
            var demoted = entry
            demoted.source = .manual
            demoted.dayNumbers = []
            updated.append(demoted)
        }

        state.trips[tripIndex].packing = updated
        state.trips[tripIndex].updatedAt = Date()
    }

    /// Adds any enabled essentials that are not on the list yet.
    static func syncEssentials(tripID: UUID, in state: inout AppState) {
        guard let tripIndex = state.trips.firstIndex(where: { $0.id == tripID }) else { return }
        for essential in state.essentials where essential.isEnabled {
            let alreadyThere = state.trips[tripIndex].packing.contains {
                $0.source == .essential && $0.manualName == essential.name
            }
            guard !alreadyThere else { continue }
            state.trips[tripIndex].packing.append(
                PackingEntry(
                    source: .essential,
                    manualName: essential.name,
                    manualWeightGrams: essential.weightGrams
                )
            )
        }
    }

    /// Deletes a trip. Wear records made during it stay, because they describe
    /// what actually happened.
    static func deleteTrip(_ tripID: UUID, in state: inout AppState) {
        state.trips.removeAll { $0.id == tripID }
        for index in state.wearRecords.indices where state.wearRecords[index].tripID == tripID {
            state.wearRecords[index].tripID = nil
        }
    }

    // MARK: - Events

    static func deleteEvent(_ eventID: UUID, in state: inout AppState) {
        state.events.removeAll { $0.id == eventID }
        for index in state.wearRecords.indices where state.wearRecords[index].eventID == eventID {
            state.wearRecords[index].eventID = nil
        }
    }

    // MARK: - Housekeeping

    /// Photo identifiers still referenced anywhere, used to prune orphan files.
    static func referencedPhotoIDs(in state: AppState) -> Set<String> {
        var ids = Set<String>()
        for piece in state.pieces { if let id = piece.photoID { ids.insert(id) } }
        for record in state.wearRecords {
            for snapshot in record.pieceSnapshots { if let id = snapshot.photoID { ids.insert(id) } }
        }
        for record in state.laundryRecords { if let id = record.snapshot.photoID { ids.insert(id) } }
        for repair in state.repairs { if let id = repair.snapshot.photoID { ids.insert(id) } }
        for load in state.laundryLoads {
            for snapshot in load.snapshots { if let id = snapshot.photoID { ids.insert(id) } }
        }
        for template in state.templates {
            for snapshot in template.snapshots { if let id = snapshot.photoID { ids.insert(id) } }
        }
        return ids
    }

    /// Clears wear history without touching the wardrobe itself.
    static func clearWearHistory(in state: inout AppState) {
        state.wearRecords.removeAll()
        for index in state.dayPlans.indices { state.dayPlans[index].wearRecordID = nil }
        for index in state.events.indices { state.events[index].wearRecordID = nil }
        for tripIndex in state.trips.indices {
            for dayIndex in state.trips[tripIndex].days.indices {
                state.trips[tripIndex].days[dayIndex].wearRecordID = nil
                state.trips[tripIndex].days[dayIndex].notWorn = false
            }
        }
    }
}
