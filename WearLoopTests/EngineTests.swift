//
//  EngineTests.swift
//  WearLoopTests
//
//  The calculations the user is asked to trust: bag weight, availability,
//  readiness, recap and the statistics.
//

import XCTest
@testable import WearLoop

final class LuggageEngineTests: XCTestCase {

    func testTotalWeightSumsRealWeightsAndFlagsNoEstimates() {
        let (state, tripID) = Fixtures.stateWithTrip()
        let estimate = LuggageEngine.estimate(trip: state.trip(tripID)!, state: state)

        // Office outfit: shirt 200 + trousers 400 + shoes 800.
        XCTAssertEqual(estimate.totalGrams, 1400, accuracy: 0.001)
        XCTAssertEqual(estimate.estimatedLineCount, 0, "Every piece has a real weight.")
        XCTAssertFalse(estimate.isOverLimit)
    }

    func testAPieceWithoutAWeightUsesTheCategoryAverageAndSaysSo() {
        var (state, tripID) = Fixtures.stateWithTrip()
        // Strip the weight from the shirt.
        state.pieces[0].weightGrams = nil

        let estimate = LuggageEngine.estimate(trip: state.trip(tripID)!, state: state)

        XCTAssertEqual(estimate.estimatedLineCount, 1)
        XCTAssertEqual(
            estimate.totalGrams,
            PieceCategory.top.defaultWeightGrams + 400 + 800,
            accuracy: 0.001
        )
        XCTAssertNotNil(LuggageEngine.estimateNote(estimate: estimate))
    }

    func testGoingOverTheLimitIsReportedWithTheExactExcess() {
        var (state, tripID) = Fixtures.stateWithTrip()
        state.trips[0].weightLimitKg = 1.0   // 1000 g against 1400 g packed

        let estimate = LuggageEngine.estimate(trip: state.trip(tripID)!, state: state)

        XCTAssertTrue(estimate.isOverLimit)
        XCTAssertEqual(estimate.overByGrams, 400, accuracy: 0.001)
        XCTAssertTrue(
            LuggageEngine.summarySentence(estimate: estimate, units: .metric).contains("Over by"))
    }

    func testNoLimitMeansNothingIsEverOverweight() {
        var (state, tripID) = Fixtures.stateWithTrip()
        state.trips[0].luggageType = .noLimit
        state.trips[0].weightLimitKg = nil

        let estimate = LuggageEngine.estimate(trip: state.trip(tripID)!, state: state)

        XCTAssertNil(estimate.limitGrams)
        XCTAssertFalse(estimate.isOverLimit)
        XCTAssertEqual(estimate.overByGrams, 0)
    }

    func testItemsMarkedNotPackingLeaveTheBag() {
        var (state, tripID) = Fixtures.stateWithTrip()
        let before = LuggageEngine.estimate(trip: state.trip(tripID)!, state: state).totalGrams

        let index = state.trips[0].packing.firstIndex { $0.pieceID == state.pieces[2].id }!  // shoes, 800 g
        state.trips[0].packing[index].isNotPacking = true

        let after = LuggageEngine.estimate(trip: state.trip(tripID)!, state: state).totalGrams
        XCTAssertEqual(before - after, 800, accuracy: 0.001)
    }
}

final class AvailabilityEngineTests: XCTestCase {

    func testAnOutfitWithFewerThanTwoPiecesIsReportedNotSilentlyAccepted() {
        var state = Fixtures.populatedState()
        state.outfits[0].items = [state.outfits[0].items[0]]

        let check = AvailabilityEngine.check(outfit: state.outfits[0], state: state)
        XCTAssertTrue(check.notes.contains { $0.contains("Only one piece") })
        XCTAssertFalse(AvailabilityEngine.isAssignable(outfit: state.outfits[0], state: state))
    }

    func testTemperatureRangeIsTheOverlapOfThePiecesSeasons() {
        var state = AppState()
        let winter = Fixtures.piece("Coat", category: .outerwear, seasons: [.winter])
        let allYear = Fixtures.piece("Shirt", seasons: [.allYear])
        state.pieces = [winter, allYear]

        let range = AvailabilityEngine.derivedTemperatureRange(
            pieceIDs: [winter.id, allYear.id], state: state
        )
        // Winter is -15...6, all year is -5...30, so the overlap is -5...6.
        XCTAssertEqual(range.min, -5, accuracy: 0.001)
        XCTAssertEqual(range.max, 6, accuracy: 0.001)
        XCTAssertFalse(range.widened)
    }

    func testPiecesThatDisagreeAboutTheWeatherWidenTheRangeAndSaySo() {
        var state = AppState()
        let winter = Fixtures.piece("Coat", category: .outerwear, seasons: [.winter])   // -15...6
        let summer = Fixtures.piece("Shorts", category: .bottom, seasons: [.summer])    // 17...36
        state.pieces = [winter, summer]

        let range = AvailabilityEngine.derivedTemperatureRange(
            pieceIDs: [winter.id, summer.id], state: state
        )
        XCTAssertTrue(range.widened, "There is no overlap, so the caller must be told.")
        XCTAssertLessThan(range.min, range.max)
    }

    func testWeatherMismatchOnlyFiresOutsideTheOutfitsOwnRange() {
        let outfit = Fixtures.outfit("Mid", pieces: [], temperature: 8...16)

        XCTAssertNil(
            AvailabilityEngine.weatherMismatch(
                outfit: outfit, weather: WeatherInput(temperatureC: 12), units: .metric, dayLabel: "Today"
            ),
            "Inside the range there is nothing to warn about."
        )
        let cold = AvailabilityEngine.weatherMismatch(
            outfit: outfit, weather: WeatherInput(temperatureC: 3), units: .metric, dayLabel: "Tomorrow"
        )
        XCTAssertNotNil(cold)
        XCTAssertTrue(cold!.contains("8 to 16"))
        XCTAssertTrue(cold!.contains("3 °C"))
    }

    func testRainWarningOnlyWhenThereIsNoOuterLayer() {
        var state = Fixtures.populatedState()
        let rain = WeatherInput(temperatureC: 12, rain: true)

        let noOuter = state.outfits[0]  // shirt, trousers, shoes
        XCTAssertNotNil(AvailabilityEngine.rainWarning(outfit: noOuter, weather: rain, state: state))

        let coat = state.pieces[3]
        state.outfits[0].items.append(OutfitItem(pieceID: coat.id, layer: .outer))
        XCTAssertNil(AvailabilityEngine.rainWarning(outfit: state.outfits[0], weather: rain, state: state))
    }

    func testFormalityMismatchIsOneWay() {
        let casual = Fixtures.outfit("Jeans", pieces: [], formality: .casual)
        let formal = Fixtures.outfit("Suit", pieces: [], formality: .formal)

        XCTAssertNotNil(
            AvailabilityEngine.formalityMismatch(outfit: casual, required: .formal, requiredLabel: "event"))
        XCTAssertNil(
            AvailabilityEngine.formalityMismatch(outfit: formal, required: .casual, requiredLabel: "event"),
            "Being smarter than required is not a problem."
        )
    }
}

final class TripReadinessTests: XCTestCase {

    func testPackingIsBlockedUntilEveryDayIsPlanned() {
        var (state, tripID) = Fixtures.stateWithTrip()
        state.trips[0].days[1].outfitID = nil

        let reason = TripReadinessEngine.blockReason(for: .packingList, trip: state.trip(tripID)!, state: state)
        XCTAssertNotNil(reason)
        XCTAssertTrue(reason!.contains("Day 2"))
    }

    func testMarkingADayUndecidedUnblocksPacking() {
        var (state, tripID) = Fixtures.stateWithTrip()
        state.trips[0].days[1].outfitID = nil
        state.trips[0].days[1].isUndecided = true

        XCTAssertNil(TripReadinessEngine.blockReason(for: .packingList, trip: state.trip(tripID)!, state: state))
    }

    func testReadinessFailsWhileAPieceTheTripNeedsIsInTheWash() {
        var (state, tripID) = Fixtures.stateWithTrip()
        state.trips[0].conditionsReviewed = true

        WardrobeActions.sendToWash(pieceIDs: [state.pieces[0].id], in: &state, now: Fixtures.now)

        let readiness = TripReadinessEngine.readiness(trip: state.trip(tripID)!, state: state, now: Fixtures.now)
        let laundryCheck = readiness.items.first { $0.id == "laundry" }
        XCTAssertEqual(laundryCheck?.isPassed, false)
        XCTAssertFalse(readiness.isReady)
    }

    func testFinishingIsBlockedUntilEveryDayHasARecord() {
        let (state, tripID) = Fixtures.stateWithTrip()
        let reason = TripReadinessEngine.blockReason(for: .recap, trip: state.trip(tripID)!, state: state)
        XCTAssertNotNil(reason, "Days with no record must be named before the trip can close.")
    }
}

final class TripRecapTests: XCTestCase {

    func testPackingAccuracyCountsGarmentsOnBothSidesOfTheFraction() {
        var (state, tripID) = Fixtures.stateWithTrip()

        // Tick every wardrobe piece as packed, plus an essential and a free-text line.
        for index in state.trips[0].packing.indices { state.trips[0].packing[index].isPacked = true }
        state.trips[0].packing.append(
            PackingEntry(source: .essential, manualName: "Charger", isPacked: true))
        state.trips[0].packing.append(
            PackingEntry(source: .manual, manualName: "Book", isPacked: true))

        // Wear one of the three packed garments.
        WardrobeActions.recordWear(
            outfitID: nil,
            pieceIDs: [state.pieces[0].id],
            date: Fixtures.now,
            context: .trip,
            tripID: tripID,
            in: &state
        )

        let recap = TripRecapEngine.build(trip: state.trip(tripID)!, state: state)

        XCTAssertEqual(recap.packedCount, 3, "Essentials and free text are not garments.")
        XCTAssertEqual(recap.wornCount, 1)
        XCTAssertEqual(recap.neverWornPieceIDs.count, 2)
    }

    func testAGarmentWornButNeverPackedIsReportedSeparately() {
        var (state, tripID) = Fixtures.stateWithTrip()
        for index in state.trips[0].packing.indices { state.trips[0].packing[index].isPacked = true }

        let coat = state.pieces[3]   // not in the office outfit, so not packed
        WardrobeActions.recordWear(
            outfitID: nil, pieceIDs: [coat.id], date: Fixtures.now,
            context: .trip, tripID: tripID, in: &state
        )

        let recap = TripRecapEngine.build(trip: state.trip(tripID)!, state: state)
        XCTAssertEqual(recap.wornNotPackedPieceIDs, [coat.id])
    }
}

final class InsightsTests: XCTestCase {

    func testPatternsStayLockedUntilThereAreEnoughDays() {
        var state = Fixtures.populatedState()
        XCTAssertFalse(InsightsEngine.isUnlocked(state: state))

        for day in 0 ..< InsightsEngine.requiredWearDays {
            WardrobeActions.recordWear(
                outfitID: state.outfits[0].id,
                pieceIDs: [],
                date: Calendar.wl.addingDays(-day, to: Fixtures.now),
                context: .day,
                in: &state
            )
        }
        XCTAssertTrue(InsightsEngine.isUnlocked(state: state))
    }

    func testTwoRecordsOnOneDayCountAsOneDayOfHistory() {
        var state = Fixtures.populatedState()
        for _ in 0 ..< 5 {
            WardrobeActions.recordWear(
                outfitID: state.outfits[0].id, pieceIDs: [], date: Fixtures.now, context: .day, in: &state
            )
        }
        XCTAssertEqual(state.wearRecordDayCount, 1)
    }

    func testCostPerWearNeedsBothAPriceAndAWearing() {
        var state = Fixtures.populatedState()
        let shirt = state.pieces[0]   // priced at 60

        XCTAssertNil(state.costPerWear(pieceID: shirt.id), "No wearings yet.")

        for _ in 0 ..< 3 {
            WardrobeActions.recordWear(
                outfitID: nil, pieceIDs: [shirt.id], date: Fixtures.now, context: .day, in: &state
            )
        }
        XCTAssertEqual(state.costPerWear(pieceID: shirt.id)!, 20, accuracy: 0.001)
    }

    func testAMetricWithNoDataReportsWhyRatherThanShowingZero() {
        let state = Fixtures.populatedState()
        let metric = InsightsEngine.metric(.mostWorn, state: state, now: Fixtures.now)
        XCTAssertTrue(metric.isLocked)
        XCTAssertNotNil(metric.lockedMessage)
        XCTAssertTrue(metric.rows.isEmpty)
    }
}

final class GrammarTests: XCTestCase {

    func testCountsReadAsEnglish() {
        XCTAssertEqual(Plural.count(1, "piece"), "1 piece")
        XCTAssertEqual(Plural.count(3, "piece"), "3 pieces")
        XCTAssertEqual(Plural.count(0, "piece"), "0 pieces")
    }

    func testDayListsReadAsEnglish() {
        XCTAssertEqual(Plural.days([1]), "day 1")
        XCTAssertEqual(Plural.days([1, 4]), "days 1 and 4")
        XCTAssertEqual(Plural.days([6, 1, 3]), "days 1, 3 and 6")
    }
}
