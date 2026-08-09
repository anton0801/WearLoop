//
//  PlanningTests.swift
//  WearLoopTests
//
//  Suggestion, next step and trip coverage: the parts that decide what the app
//  tells the user to do next.
//

import XCTest
@testable import WearLoop

final class SuggestionEngineTests: XCTestCase {

    func testAnOutfitWithAPieceInTheWashIsNeverSuggested() {
        var state = Fixtures.populatedState()
        // Leave exactly one usable outfit by washing a piece of the other.
        let weekendOnly = Fixtures.piece("Jumper", category: .top)
        let jeans = Fixtures.piece("Jeans", category: .bottom)
        state.pieces.append(contentsOf: [weekendOnly, jeans])
        state.outfits = [Fixtures.outfit("Casual", pieces: [weekendOnly, jeans])]

        WardrobeActions.sendToWash(pieceIDs: [jeans.id], in: &state, now: Fixtures.now)

        XCTAssertNil(
            SuggestionEngine.suggest(for: Fixtures.now, state: state, weather: nil, occasion: nil),
            "Nothing can be suggested when no outfit is complete."
        )
    }

    func testTheSuggestionAlwaysExplainsItself() {
        let state = Fixtures.populatedState()
        let suggestion = SuggestionEngine.suggest(
            for: Fixtures.now, state: state, weather: WeatherInput(temperatureC: 12), occasion: .work
        )
        XCTAssertNotNil(suggestion)
        XCTAssertFalse(suggestion!.reasons.isEmpty, "A suggestion without a reason is a guess.")
    }

    func testWeatherInsideTheRangeIsGivenAsAReason() {
        let state = Fixtures.populatedState()
        let suggestion = SuggestionEngine.suggest(
            for: Fixtures.now, state: state, weather: WeatherInput(temperatureC: 12), occasion: nil
        )
        XCTAssertTrue(
            suggestion!.reasons.contains { $0.contains("12 °C") },
            "The temperature that justified the choice is named."
        )
    }
}

final class NextStepEngineTests: XCTestCase {

    func testAnEmptyWardrobeAsksForTheFirstPiece() {
        let step = NextStepEngine.nextStep(state: AppState(), now: Fixtures.now)
        XCTAssertEqual(step?.action, .addPiece)
    }

    func testPiecesWithoutOutfitsAskForAnOutfit() {
        var state = AppState()
        state.pieces = [Fixtures.piece("Shirt"), Fixtures.piece("Trousers", category: .bottom)]
        let step = NextStepEngine.nextStep(state: state, now: Fixtures.now)
        XCTAssertEqual(step?.action, .buildOutfit)
    }

    func testAnEventWithoutAnOutfitIsRaised() {
        var state = Fixtures.populatedState()
        state.events = [
            EventEntity(
                name: "Wedding",
                date: Calendar.wl.addingDays(3, to: Fixtures.now),
                occasion: .formal,
                dressCode: .formal
            )
        ]
        let step = NextStepEngine.nextStep(state: state, now: Fixtures.now)
        guard case .assignEventOutfit = step?.action else {
            return XCTFail("Expected the event to be raised, got \(String(describing: step?.action))")
        }
    }

    func testATidyWardrobeWithTomorrowPlannedHasNothingToNag() {
        var state = Fixtures.populatedState()
        let tomorrow = Calendar.wl.addingDays(1, to: Fixtures.now)
        let planID = WardrobeActions.ensureDayPlan(for: tomorrow, in: &state)
        state.dayPlans[state.dayPlans.firstIndex { $0.id == planID }!].outfitID = state.outfits[0].id

        XCTAssertNil(
            NextStepEngine.nextStep(state: state, now: Fixtures.now),
            "With nothing outstanding the card must disappear rather than invent work."
        )
    }
}

final class TripPlanEngineTests: XCTestCase {

    func testReusingOneOutfitAcrossDaysIsReportedAsReuse() {
        let (state, tripID) = Fixtures.stateWithTrip()   // same outfit on all three days
        let coverage = TripPlanEngine.coverage(trip: state.trip(tripID)!, state: state)

        XCTAssertEqual(coverage.daysCovered, 3)
        XCTAssertEqual(coverage.daysUndecided, 0)
        XCTAssertEqual(coverage.totalPiecesUsed, 3, "Three garments cover three days.")
        XCTAssertGreaterThan(coverage.reuseRate, 0.6, "Wearing the same outfit thrice is high reuse.")
        XCTAssertTrue(coverage.notes.contains { $0.contains("days 1, 2 and 3") })
    }

    func testUndecidedDaysAreCountedSeparatelyFromCoveredOnes() {
        var (state, tripID) = Fixtures.stateWithTrip()
        state.trips[0].days[2].outfitID = nil
        state.trips[0].days[2].isUndecided = true

        let coverage = TripPlanEngine.coverage(trip: state.trip(tripID)!, state: state)
        XCTAssertEqual(coverage.daysCovered, 2)
        XCTAssertEqual(coverage.daysUndecided, 1)
        XCTAssertEqual(coverage.daysWithoutPlan, 0)
    }

    func testAnOutfitTooWarmForTheTripIsFlaggedNotRemoved() {
        var (state, tripID) = Fixtures.stateWithTrip()
        state.trips[0].temperatureMin = 25
        state.trips[0].temperatureMax = 35
        state.outfits[0].temperatureMin = -5
        state.outfits[0].temperatureMax = 5

        let outside = TripPlanEngine.outfitsOutsideConditions(trip: state.trip(tripID)!, state: state)
        XCTAssertTrue(outside.contains(state.outfits[0].id))
        XCTAssertNotNil(
            state.trip(tripID)!.days[0].outfitID,
            "It is flagged, but the assignment is left alone."
        )
    }

    func testWhyIsThisHereNamesTheDaysThatNeedThePiece() {
        let (state, tripID) = Fixtures.stateWithTrip()
        let shirt = state.pieces[0]
        let days = TripPlanEngine.daysNeeding(pieceID: shirt.id, trip: state.trip(tripID)!, state: state)
        XCTAssertEqual(days, [1, 2, 3])
    }
}

final class PackingAccuracyTests: XCTestCase {

    func testAccuracyIsLockedUntilATripHasBeenFinished() {
        let (state, _) = Fixtures.stateWithTrip()
        let metric = InsightsEngine.metric(.packingAccuracy, state: state, now: Fixtures.now)
        XCTAssertTrue(metric.isLocked)
    }

    func testAccuracyReportsTheShareOfPackedGarmentsThatWereWorn() {
        var (state, tripID) = Fixtures.stateWithTrip()
        for index in state.trips[0].packing.indices { state.trips[0].packing[index].isPacked = true }

        WardrobeActions.recordWear(
            outfitID: nil, pieceIDs: [state.pieces[0].id], date: Fixtures.now,
            context: .trip, tripID: tripID, in: &state
        )
        state.trips[0].recap = TripRecapEngine.build(trip: state.trips[0], state: state)

        let metric = InsightsEngine.metric(.packingAccuracy, state: state, now: Fixtures.now)
        XCTAssertFalse(metric.isLocked)
        XCTAssertEqual(metric.headline, "33%", "One of three packed garments was worn.")
    }
}
