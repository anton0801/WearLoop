//
//  WardrobeActionsTests.swift
//  WearLoopTests
//
//  The promise of the app is that one change reaches every section. These are
//  the tests that hold that promise to account.
//

import XCTest
@testable import WearLoop

final class WardrobeActionsTests: XCTestCase {

    // MARK: Wash propagation

    func testSendingToWashMakesTheOutfitPartlyUnavailable() {
        var state = Fixtures.populatedState()
        let shirt = state.pieces[0]
        let office = state.outfits[0]

        XCTAssertEqual(
            AvailabilityEngine.check(outfit: office, state: state).status, .ready,
            "The outfit starts fully available."
        )

        WardrobeActions.sendToWash(pieceIDs: [shirt.id], in: &state, now: Fixtures.now)

        let check = AvailabilityEngine.check(outfit: state.outfits[0], state: state, referenceDate: Fixtures.now)
        XCTAssertEqual(check.status, .partlyUnavailable)
        XCTAssertEqual(check.inWashPieceIDs, [shirt.id])
        XCTAssertNotNil(check.earliestReturn, "A washed piece must show when it comes back.")
    }

    func testSendingToWashUnticksThePieceOnAnUnfinishedTrip() {
        var (state, tripID) = Fixtures.stateWithTrip()
        let shirt = state.pieces[0]

        // Tick everything as packed first.
        for index in state.trips[0].packing.indices {
            state.trips[0].packing[index].isPacked = true
        }

        WardrobeActions.sendToWash(pieceIDs: [shirt.id], in: &state, now: Fixtures.now)

        let entry = state.trip(tripID)?.packing.first { $0.pieceID == shirt.id }
        XCTAssertEqual(entry?.isPacked, false, "A piece in the wash cannot stay ticked as packed.")
    }

    func testReturningFromWashRestoresRotationAndClosesTheRecord() {
        var state = Fixtures.populatedState()
        let shirt = state.pieces[0]

        WardrobeActions.sendToWash(pieceIDs: [shirt.id], in: &state, now: Fixtures.now)
        XCTAssertEqual(state.piece(shirt.id)?.status, .inWash)
        XCTAssertEqual(state.laundryRecords.filter { $0.returnedAt == nil }.count, 1)

        WardrobeActions.returnFromWash(pieceIDs: [shirt.id], in: &state, now: Fixtures.now)

        XCTAssertEqual(state.piece(shirt.id)?.status, .inRotation)
        XCTAssertNil(state.piece(shirt.id)?.expectedBackDate)
        XCTAssertEqual(state.laundryRecords.filter { $0.returnedAt == nil }.count, 0)
    }

    func testAPieceNeedingRepairDoesNotReturnToRotationFromTheWash() {
        var state = Fixtures.populatedState()
        let shirt = state.pieces[0]

        WardrobeActions.reportRepair(pieceID: shirt.id, issue: "Torn", plannedAction: "", in: &state, now: Fixtures.now)
        WardrobeActions.sendToWash(pieceIDs: [shirt.id], in: &state, now: Fixtures.now)
        WardrobeActions.returnFromWash(pieceIDs: [shirt.id], in: &state, now: Fixtures.now)

        XCTAssertEqual(
            state.piece(shirt.id)?.status, .needsRepair,
            "Washing does not mend a torn garment."
        )
    }

    // MARK: Deletion

    func testDeletingAPieceRemovesItFromOutfitsButKeepsHistory() {
        var state = Fixtures.populatedState()
        let shirt = state.pieces[0]
        let office = state.outfits[0]

        WardrobeActions.recordWear(
            outfitID: office.id, pieceIDs: [], date: Fixtures.now, context: .day, in: &state
        )
        XCTAssertEqual(state.wearRecords.count, 1)

        WardrobeActions.deletePiece(shirt.id, in: &state)

        XCTAssertNil(state.piece(shirt.id))
        XCTAssertFalse(state.outfits[0].contains(pieceID: shirt.id), "The outfit loses the piece.")
        XCTAssertEqual(state.wearRecords.count, 1, "History is never rewritten by a deletion.")
        XCTAssertEqual(
            state.wearRecords[0].pieceSnapshots.first { $0.pieceID == shirt.id }?.name, "Shirt",
            "The record keeps its own copy of the name."
        )
    }

    func testDeletingAnOutfitClearsEveryPlanThatPointedAtIt() {
        var (state, tripID) = Fixtures.stateWithTrip()
        let office = state.outfits[0]

        let planID = WardrobeActions.ensureDayPlan(for: Fixtures.now, in: &state)
        state.dayPlans[state.dayPlans.firstIndex { $0.id == planID }!].outfitID = office.id
        state.events = [
            EventEntity(name: "Wedding", date: Fixtures.now, occasion: .formal, dressCode: .formal, outfitID: office.id)
        ]

        WardrobeActions.deleteOutfit(office.id, in: &state)

        XCTAssertNil(state.outfit(office.id))
        XCTAssertNil(state.dayPlans.first?.outfitID)
        XCTAssertNil(state.events.first?.outfitID)
        XCTAssertTrue(
            state.trip(tripID)!.days.allSatisfy { $0.outfitID == nil },
            "Trip days lose the deleted outfit too."
        )
    }

    // MARK: Packing

    func testRefreshingPackingKeepsManualEntriesAndDropsUnneededOnes() {
        var (state, tripID) = Fixtures.stateWithTrip()
        let extra = Fixtures.piece("Swim shorts", category: .bottom)
        state.pieces.append(extra)

        state.trips[0].packing.append(PackingEntry(source: .manual, pieceID: extra.id))
        state.trips[0].packing.append(PackingEntry(source: .manual, manualName: "Passport"))

        // Clear the day plans so nothing is required by an outfit any more.
        for index in state.trips[0].days.indices { state.trips[0].days[index].outfitID = nil }
        WardrobeActions.refreshPacking(tripID: tripID, in: &state)

        let packing = state.trip(tripID)!.packing
        XCTAssertTrue(
            packing.contains { $0.pieceID == extra.id },
            "A piece added by hand survives a refresh."
        )
        XCTAssertTrue(
            packing.contains { $0.manualName == "Passport" },
            "A free-text line survives a refresh."
        )
        XCTAssertFalse(
            packing.contains { $0.source == .fromOutfits },
            "Nothing is required by an outfit any more."
        )
    }

    func testAPieceRequiredByAnOutfitIsNotListedTwice() {
        var (state, tripID) = Fixtures.stateWithTrip()
        let shirt = state.pieces[0]

        // Add by hand something the outfits already need.
        state.trips[0].packing.append(PackingEntry(source: .manual, pieceID: shirt.id))
        WardrobeActions.refreshPacking(tripID: tripID, in: &state)

        let matching = state.trip(tripID)!.packing.filter { $0.pieceID == shirt.id }
        XCTAssertEqual(matching.count, 1, "One piece, one line.")
        XCTAssertEqual(matching.first?.source, .fromOutfits, "It is promoted, not duplicated.")
    }

    // MARK: Wear records

    func testRemovingAWearRecordUnlinksEverythingThatPointedAtIt() {
        var state = Fixtures.populatedState()
        let office = state.outfits[0]

        let planID = WardrobeActions.ensureDayPlan(for: Fixtures.now, in: &state)
        let index = state.dayPlans.firstIndex { $0.id == planID }!
        let recordID = WardrobeActions.recordWear(
            outfitID: office.id, pieceIDs: [], date: Fixtures.now, context: .day, in: &state
        )
        state.dayPlans[index].wearRecordID = recordID

        WardrobeActions.deleteWearRecord(recordID, in: &state)

        XCTAssertTrue(state.wearRecords.isEmpty)
        XCTAssertNil(state.dayPlans[index].wearRecordID, "The day goes back to merely planned.")
    }

    func testRetiringAPieceArchivesItAndClosesItsRepair() {
        var state = Fixtures.populatedState()
        let shirt = state.pieces[0]
        WardrobeActions.reportRepair(pieceID: shirt.id, issue: "Torn", plannedAction: "", in: &state, now: Fixtures.now)

        WardrobeActions.retirePiece(shirt.id, in: &state, now: Fixtures.now)

        XCTAssertEqual(state.piece(shirt.id)?.status, .archived)
        XCTAssertTrue(state.openRepairs.isEmpty, "Retiring closes the outstanding issue.")
    }

    // MARK: Trip days

    func testShorteningATripKeepsThePlansOfTheDaysThatRemain() {
        var (state, _) = Fixtures.stateWithTrip()
        var trip = state.trips[0]
        let firstDayOutfit = trip.days[0].outfitID

        trip.endDate = trip.startDate   // three days down to one
        WardrobeActions.rebuildDays(for: &trip)

        XCTAssertEqual(trip.days.count, 1)
        XCTAssertEqual(trip.days[0].outfitID, firstDayOutfit, "Day one keeps what it had.")
    }

    func testAnEndDateBeforeTheStartIsCorrectedRatherThanCrashing() {
        var trip = Trip(
            name: "Broken",
            startDate: Fixtures.now.wlStartOfDay,
            endDate: Calendar.wl.addingDays(-5, to: Fixtures.now.wlStartOfDay)
        )
        WardrobeActions.rebuildDays(for: &trip)

        XCTAssertEqual(trip.days.count, 1)
        XCTAssertEqual(trip.endDate, trip.startDate)
    }
}
