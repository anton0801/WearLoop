//
//  Outfit.swift
//  WearLoop
//
//  A set of pieces assembled once and reused. Outfits are what the app plans with.
//

import Foundation

struct OutfitItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var pieceID: UUID
    var layer: OutfitLayer
}

struct Outfit: Identifiable, Codable, Hashable {
    var id: UUID = UUID()

    var name: String
    var occasion: Occasion
    var items: [OutfitItem] = []

    /// Seasons and temperature range are derived from the pieces on creation and
    /// then owned by the user — `isRangeManual` records that override.
    var seasons: [Season] = []
    var temperatureMin: Double = 5
    var temperatureMax: Double = 20
    var isRangeManual: Bool = false
    var isSeasonManual: Bool = false

    var formality: Formality = .casual
    var notes: String = ""

    var isFavorite: Bool = false
    var isArchived: Bool = false

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var pieceIDs: [UUID] { items.map(\.pieceID) }

    func items(in layer: OutfitLayer) -> [OutfitItem] {
        items.filter { $0.layer == layer }
    }

    var temperatureText: String {
        "\(Int(temperatureMin.rounded())) to \(Int(temperatureMax.rounded())) °C"
    }

    func contains(pieceID: UUID) -> Bool {
        items.contains { $0.pieceID == pieceID }
    }
}

// MARK: - Derived facts about an outfit

/// Everything the app can say about an outfit right now. Rebuilt on demand from
/// the current wardrobe rather than stored, so it can never go stale.
struct OutfitCheck: Hashable {
    var status: OutfitStatus
    /// Plain-language lines shown in "Outfit Check".
    var notes: [String]
    var missingPieceIDs: [UUID]
    var inWashPieceIDs: [UUID]
    var needsRepairPieceIDs: [UUID]
    var unavailablePieceIDs: [UUID]
    var earliestReturn: Date?
    var neverWornCount: Int
    var isAvailable: Bool { unavailablePieceIDs.isEmpty && missingPieceIDs.isEmpty }
}

/// A planned calendar day in the two-week planner.
struct DayPlan: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    /// Normalised to the start of the day.
    var date: Date
    var occasion: Occasion?
    var weather: WeatherInput?
    var outfitID: UUID?
    var backupOutfitID: UUID?
    var notes: String = ""
    /// Set only by an explicit "Mark as Worn" — never automatic.
    var wearRecordID: UUID?

    var isWorn: Bool { wearRecordID != nil }
    var hasAssignment: Bool { outfitID != nil }
}

/// Weather for a day or a trip, entered by hand or fetched.
struct WeatherInput: Codable, Hashable {
    enum Source: String, Codable, Hashable {
        case manual
        case system
        case openWeatherMap

        var isFetched: Bool { self != .manual }
    }

    var temperatureC: Double
    var rain: Bool = false
    var windKph: Double?
    var source: Source = .manual
    /// Place the reading came from, when it was fetched.
    var locationName: String?
    /// When it was fetched, so a stale reading can be refreshed.
    var fetchedAt: Date?

    /// A fetched reading older than an hour is worth replacing.
    func isStale(now: Date = Date(), maximumAge: TimeInterval = 3600) -> Bool {
        guard source.isFetched else { return false }
        guard let fetchedAt else { return true }
        return now.timeIntervalSince(fetchedAt) > maximumAge
    }

    func temperatureText(units: MeasurementUnits) -> String {
        UnitFormatter.temperature(temperatureC, units: units)
    }
}

/// A confirmed wearing. The single source of truth for every statistic.
struct WearRecord: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    /// Normalised to the start of the day.
    var date: Date
    var context: WearContext
    var outfitID: UUID?
    /// Name kept separately so a deleted outfit does not blank out history.
    var outfitName: String?
    var pieceSnapshots: [PieceSnapshot]
    var tripID: UUID?
    var eventID: UUID?
    var note: String = ""
    /// True when the user wore something other than what was planned.
    var wasUnplanned: Bool = false

    var pieceIDs: [UUID] { pieceSnapshots.map(\.pieceID) }
}

/// A one-off event outside any trip.
struct EventEntity: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var date: Date
    var occasion: Occasion
    var dressCode: DressCode
    var location: String = ""
    var weather: WeatherInput?
    var outfitID: UUID?
    var backupOutfitID: UUID?
    var notes: String = ""
    var wearRecordID: UUID?
    var createdAt: Date = Date()

    var isWorn: Bool { wearRecordID != nil }

    var isPast: Bool {
        Calendar.wl.startOfDay(for: date) < Calendar.wl.startOfDay(for: Date())
    }
}

/// A wash load grouping pieces that travel through the cycle together.
struct LaundryLoad: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var pieceIDs: [UUID]
    /// Snapshots so a finished load still reads correctly after deletions.
    var snapshots: [PieceSnapshot]
    var temperatureC: Int = 30
    var startedAt: Date?
    var expectedReady: Date?
    var notes: String = ""
    var stage: LaundryStage = .washingNow
    var createdAt: Date = Date()
}

// MARK: - Resilient decoding
//
// A missing or malformed field falls back to its default so that one gap in the
// document can never cost the user their whole wardrobe.

// MARK: - Outfit

extension OutfitItem {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.wl(.id, UUID())
        pieceID = c.wl(.pieceID, UUID())
        layer = c.wl(.layer, .top)
    }
}

extension Outfit {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.wl(.id, UUID())
        name = c.wlName(.name, "Untitled outfit")
        occasion = c.wl(.occasion, .everyday)
        items = c.wlArray(OutfitItem.self, .items)
        seasons = c.wlArray(Season.self, .seasons)
        temperatureMin = c.wl(.temperatureMin, 5)
        temperatureMax = c.wl(.temperatureMax, 20)
        isRangeManual = c.wl(.isRangeManual, false)
        isSeasonManual = c.wl(.isSeasonManual, false)
        formality = c.wl(.formality, .casual)
        notes = c.wl(.notes, "")
        isFavorite = c.wl(.isFavorite, false)
        isArchived = c.wl(.isArchived, false)
        createdAt = c.wl(.createdAt, Date())
        updatedAt = c.wl(.updatedAt, Date())

        // A reversed range would make every check nonsense.
        if temperatureMax < temperatureMin {
            let low = temperatureMax
            temperatureMax = temperatureMin
            temperatureMin = low
        }
    }
}

extension WeatherInput {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        temperatureC = c.wl(.temperatureC, 15)
        rain = c.wl(.rain, false)
        windKph = c.wlOptional(Double.self, .windKph)
        source = c.wl(.source, .manual)
        locationName = c.wlOptional(String.self, .locationName)
        fetchedAt = c.wlOptional(Date.self, .fetchedAt)
    }
}

extension DayPlan {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.wl(.id, UUID())
        date = c.wl(.date, Date())
        occasion = c.wlOptional(Occasion.self, .occasion)
        weather = c.wlOptional(WeatherInput.self, .weather)
        outfitID = c.wlOptional(UUID.self, .outfitID)
        backupOutfitID = c.wlOptional(UUID.self, .backupOutfitID)
        notes = c.wl(.notes, "")
        wearRecordID = c.wlOptional(UUID.self, .wearRecordID)
    }
}

extension WearRecord {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.wl(.id, UUID())
        date = c.wl(.date, Date())
        context = c.wl(.context, .day)
        outfitID = c.wlOptional(UUID.self, .outfitID)
        outfitName = c.wlOptional(String.self, .outfitName)
        pieceSnapshots = c.wlArray(PieceSnapshot.self, .pieceSnapshots)
        tripID = c.wlOptional(UUID.self, .tripID)
        eventID = c.wlOptional(UUID.self, .eventID)
        note = c.wl(.note, "")
        wasUnplanned = c.wl(.wasUnplanned, false)
    }
}

extension EventEntity {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.wl(.id, UUID())
        name = c.wlName(.name, "Untitled event")
        date = c.wl(.date, Date())
        occasion = c.wl(.occasion, .goingOut)
        dressCode = c.wl(.dressCode, .smartCasual)
        location = c.wl(.location, "")
        weather = c.wlOptional(WeatherInput.self, .weather)
        outfitID = c.wlOptional(UUID.self, .outfitID)
        backupOutfitID = c.wlOptional(UUID.self, .backupOutfitID)
        notes = c.wl(.notes, "")
        wearRecordID = c.wlOptional(UUID.self, .wearRecordID)
        createdAt = c.wl(.createdAt, Date())
    }
}

extension LaundryLoad {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.wl(.id, UUID())
        name = c.wlName(.name, "Wash load")
        pieceIDs = c.wlArray(UUID.self, .pieceIDs)
        snapshots = c.wlArray(PieceSnapshot.self, .snapshots)
        temperatureC = c.wl(.temperatureC, 30)
        startedAt = c.wlOptional(Date.self, .startedAt)
        expectedReady = c.wlOptional(Date.self, .expectedReady)
        notes = c.wl(.notes, "")
        stage = c.wl(.stage, .washingNow)
        createdAt = c.wl(.createdAt, Date())
    }
}
