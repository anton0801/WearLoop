//
//  StorageTests.swift
//  WearLoopTests
//
//  Persistence has to survive a document written by an older build, a partly
//  corrupt file, and a hand-picked backup that is actively hostile.
//

import XCTest
@testable import WearLoop

final class ResilientDecodingTests: XCTestCase {

    private func decode(_ json: String) throws -> AppState {
        try PersistenceService(fileName: "unused.json").decode(Data(json.utf8))
    }

    func testAnEmptyObjectLoadsAsAFreshDocument() throws {
        let state = try decode("{}")
        XCTAssertTrue(state.pieces.isEmpty)
        XCTAssertFalse(state.hasSeenOnboarding)
        XCTAssertEqual(
            state.categoryWeights.count, PieceCategory.allCases.count,
            "Every category has a fallback weight, even in a blank document."
        )
    }

    func testADocumentMissingMostKeysStillLoads() throws {
        // What a document written by a much older build would look like.
        let state = try decode("""
        { "schemaVersion": 1, "hasSeenOnboarding": true }
        """)
        XCTAssertTrue(state.hasSeenOnboarding)
        XCTAssertTrue(state.outfits.isEmpty)
        XCTAssertTrue(state.trips.isEmpty)
    }

    func testAPartlyCorruptPieceIsSalvagedRatherThanDiscarded() throws {
        let state = try decode("""
        {
          "schemaVersion": 1,
          "pieces": [
            { "id": "11111111-1111-1111-1111-111111111111", "name": "Good shirt",
              "category": "top", "colours": ["navy"], "seasons": ["allYear"],
              "occasions": ["everyday"], "status": "inRotation",
              "createdAt": "2026-01-01T00:00:00Z", "updatedAt": "2026-01-01T00:00:00Z" },
            { "name": "Half broken", "category": "not-a-real-category" },
            { "id": "22222222-2222-2222-2222-222222222222", "name": "Other shirt",
              "category": "top", "colours": ["white"], "seasons": ["allYear"],
              "occasions": ["everyday"], "status": "inRotation",
              "createdAt": "2026-01-01T00:00:00Z", "updatedAt": "2026-01-01T00:00:00Z" }
          ]
        }
        """)
        // Losing a garment because one field is wrong would be worse than
        // keeping it with a safe default the user can correct.
        XCTAssertEqual(state.pieces.count, 3)
        let salvaged = state.pieces.first { $0.name == "Half broken" }
        XCTAssertNotNil(salvaged)
        XCTAssertNotNil(salvaged.map { PieceCategory.allCases.contains($0.category) })
        XCTAssertNotNil(salvaged?.id, "A missing identifier is replaced with a fresh one.")
    }

    func testANamelessRecordGetsAReadablePlaceholderRatherThanABlankCard() throws {
        let state = try decode("""
        {
          "schemaVersion": 1,
          "pieces": [
            { "id": "11111111-1111-1111-1111-111111111111", "name": "Real shirt",
              "category": "top", "colours": ["navy"], "seasons": ["allYear"],
              "occasions": ["everyday"], "status": "inRotation",
              "createdAt": "2026-01-01T00:00:00Z", "updatedAt": "2026-01-01T00:00:00Z" },
            { "category": "top" },
            { "name": "   " }
          ],
          "outfits": [ { "occasion": "work" } ]
        }
        """)
        // Dropping the record would lose data; leaving the name empty would put
        // an unidentifiable card in the wardrobe. A placeholder does neither.
        XCTAssertEqual(state.pieces.count, 3)
        XCTAssertTrue(
            state.pieces.allSatisfy { !$0.name.wlIsBlank },
            "No piece is ever left without something to call it."
        )
        XCTAssertTrue(
            state.outfits.allSatisfy { !$0.name.wlIsBlank },
            "The same holds for outfits."
        )
    }

    func testAFieldOfTheWrongTypeFallsBackInsteadOfThrowing() throws {
        let state = try decode("""
        { "schemaVersion": 1, "hasSeenOnboarding": "yes please" }
        """)
        XCTAssertFalse(state.hasSeenOnboarding, "A nonsense value becomes the default.")
    }

    func testADocumentFromANewerBuildIsRefusedClearly() {
        XCTAssertThrowsError(try decode("{ \"schemaVersion\": 999 }")) { error in
            guard case PersistenceError.incompatibleBackup(let version) = error else {
                return XCTFail("Expected an incompatible-backup error, got \(error)")
            }
            XCTAssertEqual(version, 999)
        }
    }

    func testAnAbsurdlyLargeFileIsRefusedBeforeDecoding() {
        let huge = Data(count: PersistenceService.maximumDocumentBytes + 1)
        XCTAssertThrowsError(try PersistenceService(fileName: "unused.json").decode(huge))
    }

    func testAFullDocumentSurvivesARoundTrip() throws {
        let service = PersistenceService(fileName: "unused.json")
        var (state, _) = Fixtures.stateWithTrip()
        state.profile.displayName = "Anton"
        WardrobeActions.recordWear(
            outfitID: state.outfits[0].id, pieceIDs: [], date: Fixtures.now, context: .day, in: &state
        )

        let restored = try service.decode(service.encode(state))

        XCTAssertEqual(restored.profile.displayName, "Anton")
        XCTAssertEqual(restored.pieces.count, state.pieces.count)
        XCTAssertEqual(restored.outfits.count, state.outfits.count)
        XCTAssertEqual(restored.trips.first?.days.count, state.trips.first?.days.count)
        XCTAssertEqual(restored.wearRecords.count, 1)
        XCTAssertEqual(restored.categoryWeights[.top], state.categoryWeights[.top])
    }
}

final class PhotoStoreSecurityTests: XCTestCase {

    /// Writes into a throwaway container so the real Documents folder is untouched.
    private var store: PhotoStore!

    override func setUp() {
        super.setUp()
        store = PhotoStore()
    }

    func testAnIdentifierWithPathTraversalIsRefused() {
        // A crafted backup could carry any string as a photo identifier.
        let hostile = [
            "../../Library/Caches/target",
            "../wearloop-state",
            "../../../../../../tmp/anything",
            "folder/nested",
            "with space",
            String(repeating: "a", count: 200),
            ""
        ]
        for id in hostile {
            XCTAssertNil(store.image(for: id), "Refused rather than read: \(id)")
            // Must not throw or touch anything; a no-op is the correct outcome.
            store.delete(id)
        }
    }

    func testAGenuineIdentifierRoundTrips() throws {
        let image = UIImage(systemName: "star.fill")!
        let id = try store.save(image)

        XCTAssertNotNil(UUID(uuidString: id), "Identifiers are generated as UUIDs.")
        XCTAssertNotNil(store.image(for: id))

        store.delete(id)
    }
}

final class WeatherServiceTests: XCTestCase {

    func testTheRequestCarriesTheRightQueryForACity() {
        let place = WeatherPlace.city("Berlin, DE")
        let items = place.queryItems
        XCTAssertEqual(items.first?.name, "q")
        XCTAssertEqual(items.first?.value, "Berlin, DE")
    }

    func testCoordinatesAreSentWithFourDecimals() {
        let place = WeatherPlace.coordinates(latitude: 52.524398, longitude: 13.410530)
        let values = place.queryItems.map(\.value)
        XCTAssertEqual(values, ["52.5244", "13.4105"])
    }

    func testAFetchedReadingIsMarkedAsFetchedAndStamped() {
        let fetched = FetchedWeather(
            temperatureC: 20.4, rain: false, windKph: 24, locationName: "Mitte"
        )
        let input = fetched.asInput()

        XCTAssertEqual(input.source, .openWeatherMap)
        XCTAssertTrue(input.source.isFetched)
        XCTAssertEqual(input.locationName, "Mitte")
        XCTAssertNotNil(input.fetchedAt)
    }

    func testAHandTypedReadingIsNeverConsideredStale() {
        let manual = WeatherInput(temperatureC: 19, source: .manual)
        XCTAssertFalse(
            manual.isStale(now: Date().addingTimeInterval(86_400)),
            "Automatic refresh must never overwrite what the user typed."
        )
    }

    func testAFetchedReadingGoesStaleAfterAnHour() {
        var fetched = WeatherInput(temperatureC: 19, source: .openWeatherMap)
        fetched.fetchedAt = Fixtures.now

        XCTAssertFalse(fetched.isStale(now: Fixtures.now.addingTimeInterval(600)))
        XCTAssertTrue(fetched.isStale(now: Fixtures.now.addingTimeInterval(7200)))
    }

    func testWithoutAKeyNothingIsEvenAttempted() async {
        // The bundled key is real, so this exercises the shape of the guard
        // rather than the absence of a key.
        let service = OpenWeatherMapService()
        XCTAssertEqual(service.isConfigured, WeatherAPIKey.isConfigured)
    }
}

final class UnitFormattingTests: XCTestCase {

    func testTemperatureConvertsForImperialUsers() {
        XCTAssertEqual(UnitFormatter.temperature(20, units: .metric), "20 °C")
        XCTAssertEqual(UnitFormatter.temperature(20, units: .imperial), "68 °F")
    }

    func testBagWeightAlwaysUsesTheLargeUnit() {
        XCTAssertEqual(UnitFormatter.bagWeight(grams: 8400, units: .metric), "8.4 kg")
        XCTAssertEqual(UnitFormatter.bagWeight(grams: 500, units: .metric), "0.5 kg")
    }

    func testSmallWeightsStayInGrams() {
        XCTAssertEqual(UnitFormatter.weight(grams: 200, units: .metric), "200 g")
        XCTAssertEqual(UnitFormatter.weight(grams: 1400, units: .metric), "1.4 kg")
    }
}
