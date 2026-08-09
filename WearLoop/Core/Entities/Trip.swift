//
//  Trip.swift
//  WearLoop
//
//  A trip is a project: its own days, outfits, packing list and luggage budget.
//

import Foundation

struct TripDay: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    /// Zero-based position in the trip.
    var index: Int
    var date: Date
    var occasions: [TripDayOccasion] = []

    // Plan
    var outfitID: UUID?
    var isUndecided: Bool = false

    // Actual, filled in during Trip Mode
    var wearRecordID: UUID?
    var notWorn: Bool = false

    var dayNumber: Int { index + 1 }
    var title: String { "Day \(dayNumber)" }
    var isPlanned: Bool { outfitID != nil || isUndecided }
    var isLogged: Bool { wearRecordID != nil || notWorn }

    var occasionText: String {
        occasions.isEmpty ? "No occasion" : occasions.map(\.title).joined(separator: " · ")
    }

    /// Highest formality required by the day's occasions.
    var requiredFormality: Formality? {
        occasions.map(\.expectedFormality).max(by: { $0.rank < $1.rank })
    }
}

struct PackingEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var source: PackingSource
    /// Set for wardrobe pieces. Nil for manual free-text lines and essentials.
    var pieceID: UUID?
    /// Set for manual lines and essentials.
    var manualName: String?
    /// Manual lines can carry their own weight so the estimate stays honest.
    var manualWeightGrams: Double?
    var isPacked: Bool = false
    /// The user pulled it off the trip without deleting the reason it appeared.
    var isNotPacking: Bool = false
    /// Day numbers (1-based) that need this piece.
    var dayNumbers: [Int] = []
    /// True when the user put this piece on the list themselves, even if an
    /// outfit later came to need it too.
    var wasAddedManually: Bool = false

    var isFromWardrobe: Bool { pieceID != nil }
}

/// Result of a finished trip: what was planned against what was actually worn.
struct TripRecapData: Codable, Hashable {
    var packedCount: Int
    var wornCount: Int
    var neverWornPieceIDs: [UUID]
    var wornNotPackedPieceIDs: [UUID]
    var outfitsChangedCount: Int
    var laundryLoadsDone: Int
    var finalWeightKg: Double
    var savedAt: Date
    var note: String = ""
    /// Set when the user closed the trip without logging what was worn.
    var finishedWithoutRecords: Bool = false
}

struct Trip: Identifiable, Codable, Hashable {
    var id: UUID = UUID()

    // Step 1
    var name: String = ""
    var destination: String = ""
    var startDate: Date = Calendar.wl.startOfDay(for: Date())
    var endDate: Date = Calendar.wl.startOfDay(for: Date().addingTimeInterval(86_400 * 3))
    var type: TripType = .leisure

    // Step 2
    var days: [TripDay] = []

    // Step 3
    var temperatureMin: Double = 10
    var temperatureMax: Double = 22
    var rainExpected: Bool = false
    var laundryAvailable: Bool = false
    var dressCodeNotes: String = ""
    var conditionsReviewed: Bool = false

    // Step 4
    var luggageType: LuggageType = .cabinBag
    var weightLimitKg: Double? = 8
    var volumeNotes: String = ""

    // Workspace
    var stage: TripStage = .setup
    var isDraft: Bool = true
    /// Wizard step reached, so a draft resumes where the user left off.
    var draftStep: Int = 1
    var packing: [PackingEntry] = []
    var recap: TripRecapData?
    /// Trip-mode laundry loads are counted here.
    var laundryOnRoadCount: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // MARK: Derived

    var dayCount: Int { days.count }

    var plannedDayCount: Int { days.filter(\.isPlanned).count }

    var undecidedDayCount: Int { days.filter { $0.isUndecided && $0.outfitID == nil }.count }

    var daysWithoutPlan: [TripDay] { days.filter { !$0.isPlanned } }

    var daysWithoutOccasion: [TripDay] { days.filter { $0.occasions.isEmpty } }

    /// Entries actually going into the bag.
    var activePacking: [PackingEntry] { packing.filter { !$0.isNotPacking } }

    var packedCount: Int { activePacking.filter(\.isPacked).count }

    var phase: TripPhase {
        if recap != nil || stage == .recap { return .completed }
        if stage == .inProgress { return .inProgress }
        return .upcoming
    }

    var dateRangeText: String {
        DateFormatterCache.rangeText(startDate, endDate)
    }

    /// 1-based day number for a date, if the date is inside the trip.
    func dayNumber(for date: Date) -> Int? {
        let target = Calendar.wl.startOfDay(for: date)
        return days.first { Calendar.wl.startOfDay(for: $0.date) == target }?.dayNumber
    }

    /// Day matching today, used by Trip Mode.
    func currentDay(now: Date = Date()) -> TripDay? {
        let today = Calendar.wl.startOfDay(for: now)
        if let exact = days.first(where: { Calendar.wl.startOfDay(for: $0.date) == today }) {
            return exact
        }
        // Before the trip starts show day 1, after it ends show the last day.
        if today < Calendar.wl.startOfDay(for: startDate) { return days.first }
        return days.last
    }

    func packingEntry(pieceID: UUID) -> PackingEntry? {
        packing.first { $0.pieceID == pieceID }
    }
}

/// A reusable packing set built from a finished trip.
struct PackingTemplate: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var tripType: TripType
    var dayCount: Int
    /// Wardrobe pieces referenced by the template.
    var pieceIDs: [UUID]
    /// Snapshots so the template still reads after a piece is deleted.
    var snapshots: [PieceSnapshot]
    /// Free-text lines that were added manually to the source trip.
    var manualItems: [String]
    var sourceTripName: String
    var createdAt: Date = Date()
}

/// A permanent item the user always packs, kept outside the wardrobe.
struct EssentialItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var weightGrams: Double?
    var isEnabled: Bool = true
}

// MARK: - Resilient decoding
//
// A missing or malformed field falls back to its default so that one gap in the
// document can never cost the user their whole wardrobe.

// MARK: - Trip

extension TripDay {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.wl(.id, UUID())
        index = c.wl(.index, 0)
        date = c.wl(.date, Date())
        occasions = c.wlArray(TripDayOccasion.self, .occasions)
        outfitID = c.wlOptional(UUID.self, .outfitID)
        isUndecided = c.wl(.isUndecided, false)
        wearRecordID = c.wlOptional(UUID.self, .wearRecordID)
        notWorn = c.wl(.notWorn, false)
    }
}

extension PackingEntry {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.wl(.id, UUID())
        source = c.wl(.source, .manual)
        pieceID = c.wlOptional(UUID.self, .pieceID)
        manualName = c.wlOptional(String.self, .manualName)
        manualWeightGrams = c.wlOptional(Double.self, .manualWeightGrams)
        isPacked = c.wl(.isPacked, false)
        isNotPacking = c.wl(.isNotPacking, false)
        dayNumbers = c.wlArray(Int.self, .dayNumbers)
        wasAddedManually = c.wl(.wasAddedManually, false)
    }
}

extension TripRecapData {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        packedCount = c.wl(.packedCount, 0)
        wornCount = c.wl(.wornCount, 0)
        neverWornPieceIDs = c.wlArray(UUID.self, .neverWornPieceIDs)
        wornNotPackedPieceIDs = c.wlArray(UUID.self, .wornNotPackedPieceIDs)
        outfitsChangedCount = c.wl(.outfitsChangedCount, 0)
        laundryLoadsDone = c.wl(.laundryLoadsDone, 0)
        finalWeightKg = c.wl(.finalWeightKg, 0)
        savedAt = c.wl(.savedAt, Date())
        note = c.wl(.note, "")
        finishedWithoutRecords = c.wl(.finishedWithoutRecords, false)
    }
}

extension Trip {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.wl(.id, UUID())
        name = c.wl(.name, "")
        destination = c.wl(.destination, "")
        startDate = c.wl(.startDate, Date().wlStartOfDay)
        endDate = c.wl(.endDate, Date().wlStartOfDay)
        type = c.wl(.type, .leisure)
        days = c.wlArray(TripDay.self, .days)
        temperatureMin = c.wl(.temperatureMin, 10)
        temperatureMax = c.wl(.temperatureMax, 22)
        rainExpected = c.wl(.rainExpected, false)
        laundryAvailable = c.wl(.laundryAvailable, false)
        dressCodeNotes = c.wl(.dressCodeNotes, "")
        conditionsReviewed = c.wl(.conditionsReviewed, false)
        luggageType = c.wl(.luggageType, .cabinBag)
        weightLimitKg = c.wlOptional(Double.self, .weightLimitKg)
        volumeNotes = c.wl(.volumeNotes, "")
        stage = c.wl(.stage, .setup)
        isDraft = c.wl(.isDraft, false)
        draftStep = c.wl(.draftStep, 1)
        packing = c.wlArray(PackingEntry.self, .packing)
        recap = c.wlOptional(TripRecapData.self, .recap)
        laundryOnRoadCount = c.wl(.laundryOnRoadCount, 0)
        createdAt = c.wl(.createdAt, Date())
        updatedAt = c.wl(.updatedAt, Date())

        if endDate < startDate { endDate = startDate }
        // Day indexes are authoritative for ordering, so rebuild them.
        for position in days.indices { days[position].index = position }
    }
}

extension PackingTemplate {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.wl(.id, UUID())
        name = c.wlName(.name, "Template")
        tripType = c.wl(.tripType, .leisure)
        dayCount = c.wl(.dayCount, 0)
        pieceIDs = c.wlArray(UUID.self, .pieceIDs)
        snapshots = c.wlArray(PieceSnapshot.self, .snapshots)
        manualItems = c.wlArray(String.self, .manualItems)
        sourceTripName = c.wl(.sourceTripName, "")
        createdAt = c.wl(.createdAt, Date())
    }
}

extension EssentialItem {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.wl(.id, UUID())
        name = c.wlName(.name, "Item")
        weightGrams = c.wlOptional(Double.self, .weightGrams)
        isEnabled = c.wl(.isEnabled, true)
    }
}
