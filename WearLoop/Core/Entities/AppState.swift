//
//  AppState.swift
//  WearLoop
//
//  The whole persisted document. One Codable tree, written atomically.
//

import Foundation

/// Basic wardrobe parameters captured in Initial Setup.
struct WardrobeProfile: Codable, Hashable {
    var displayName: String = ""
    var homeClimate: HomeClimate = .temperate
    var seasons: [Season] = []
    var occasions: [Occasion] = []
    var laundryCycle: LaundryCycle = .weekly
    var units: MeasurementUnits = .metric
    /// Set once Initial Setup has been saved.
    var isComplete: Bool = false

    var greetingName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Setup cannot be saved without at least one season and one occasion.
    var isValid: Bool { !seasons.isEmpty && !occasions.isEmpty }
}

struct NotificationSettings: Codable, Hashable {
    /// The user has been shown the explanation and said yes.
    var hasGrantedConsent: Bool = false
    var tripStartsInTwoDays: Bool = true
    var laundryReadyToReturn: Bool = true
    var eventTomorrowWithoutOutfit: Bool = true
    var repairPending: Bool = true

    var anyEnabled: Bool {
        hasGrantedConsent && (tripStartsInTwoDays || laundryReadyToReturn || eventTomorrowWithoutOutfit || repairPending)
    }
}

/// How the app finds weather. Everything still works with all of this empty —
/// weather can always be typed in by hand.
struct WeatherSettings: Codable, Hashable {
    /// City looked up when the device's own location is not used, e.g. "Berlin"
    /// or "Berlin, DE".
    var cityName: String = ""
    /// Prefer the device's location over the city above.
    var useDeviceLocation: Bool = true
    /// Refresh today's weather on its own when the app opens. A reading you
    /// typed yourself is never overwritten.
    var updateAutomatically: Bool = true

    var hasPlace: Bool { useDeviceLocation || !cityName.wlIsBlank }
}

struct AppearanceSettings: Codable, Hashable {
    /// Trip Mode is the one dark screen in the app; it can be turned off.
    var useDarkTripMode: Bool = true
    /// Halftone dot motif behind empty states and headers.
    var showHalftoneMotif: Bool = true
    /// Reduce the spring animations app-wide.
    var reduceMotion: Bool = false
}

// MARK: - Root document

struct AppState: Codable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = AppState.currentSchemaVersion
    var hasSeenOnboarding: Bool = false

    var profile: WardrobeProfile = WardrobeProfile()

    var pieces: [Piece] = []
    var outfits: [Outfit] = []
    var dayPlans: [DayPlan] = []
    var events: [EventEntity] = []

    // Laundry
    /// Pieces sent to wash but not yet in a started load — the "To Wash" basket.
    var washBasket: [UUID] = []
    var laundryLoads: [LaundryLoad] = []
    var laundryRecords: [LaundryRecord] = []

    var wearRecords: [WearRecord] = []
    var repairs: [RepairIssue] = []

    var trips: [Trip] = []
    var templates: [PackingTemplate] = []
    var essentials: [EssentialItem] = []

    /// Average weights per category in grams, editable in Settings.
    var categoryWeights: [PieceCategory: Double] = AppState.defaultCategoryWeights

    var notificationSettings: NotificationSettings = NotificationSettings()
    var appearance: AppearanceSettings = AppearanceSettings()
    var weatherSettings: WeatherSettings = WeatherSettings()

    static var defaultCategoryWeights: [PieceCategory: Double] {
        Dictionary(uniqueKeysWithValues: PieceCategory.allCases.map { ($0, $0.defaultWeightGrams) })
    }

    /// Essentials offered the first time the user opens the list.
    static var suggestedEssentials: [EssentialItem] {
        [
            EssentialItem(name: "Phone charger", weightGrams: 150),
            EssentialItem(name: "Toothbrush and paste", weightGrams: 120),
            EssentialItem(name: "Documents and tickets", weightGrams: 100),
            EssentialItem(name: "Wallet and cards", weightGrams: 120),
            EssentialItem(name: "Medication", weightGrams: 100)
        ]
    }
}

// MARK: - Lookups

extension AppState {
    func piece(_ id: UUID) -> Piece? { pieces.first { $0.id == id } }
    func outfit(_ id: UUID) -> Outfit? { outfits.first { $0.id == id } }
    func trip(_ id: UUID) -> Trip? { trips.first { $0.id == id } }
    func event(_ id: UUID) -> EventEntity? { events.first { $0.id == id } }
    func wearRecord(_ id: UUID) -> WearRecord? { wearRecords.first { $0.id == id } }

    func pieces(_ ids: [UUID]) -> [Piece] {
        ids.compactMap { id in pieces.first { $0.id == id } }
    }

    /// Pieces available for planning, packing and new outfits.
    var availablePieces: [Piece] { pieces.filter { $0.status.isAvailable } }

    /// Pieces the user still owns, excluding archived ones.
    var activePieces: [Piece] { pieces.filter { $0.status != .archived } }

    var activeOutfits: [Outfit] { outfits.filter { !$0.isArchived } }

    /// Day plan for a date, if one exists.
    func dayPlan(for date: Date) -> DayPlan? {
        let target = Calendar.wl.startOfDay(for: date)
        return dayPlans.first { Calendar.wl.startOfDay(for: $0.date) == target }
    }

    /// All wear records touching a piece, newest first.
    func wearRecords(forPiece pieceID: UUID) -> [WearRecord] {
        wearRecords
            .filter { $0.pieceIDs.contains(pieceID) }
            .sorted { $0.date > $1.date }
    }

    func wearCount(forPiece pieceID: UUID) -> Int {
        wearRecords.reduce(0) { $0 + ($1.pieceIDs.contains(pieceID) ? 1 : 0) }
    }

    func lastWorn(pieceID: UUID) -> Date? {
        wearRecords.filter { $0.pieceIDs.contains(pieceID) }.map(\.date).max()
    }

    func wearCount(forOutfit outfitID: UUID) -> Int {
        wearRecords.reduce(0) { $0 + ($1.outfitID == outfitID ? 1 : 0) }
    }

    func lastWorn(outfitID: UUID) -> Date? {
        wearRecords.filter { $0.outfitID == outfitID }.map(\.date).max()
    }

    /// Cost of one wearing, when both a price and at least one wear exist.
    func costPerWear(pieceID: UUID) -> Double? {
        guard let piece = piece(pieceID), let price = piece.purchasePrice, price > 0 else { return nil }
        let count = wearCount(forPiece: pieceID)
        guard count > 0 else { return nil }
        return price / Double(count)
    }

    /// Outfits that use a given piece.
    func outfits(containing pieceID: UUID) -> [Outfit] {
        outfits.filter { $0.contains(pieceID: pieceID) }
    }

    /// Open repair issue for a piece, if any.
    func openRepair(forPiece pieceID: UUID) -> RepairIssue? {
        repairs.first { $0.pieceID == pieceID && $0.isOpen }
    }

    var openRepairs: [RepairIssue] {
        repairs.filter(\.isOpen).sorted { $0.reportedOn < $1.reportedOn }
    }

    /// Laundry history for a piece, newest first.
    func laundryRecords(forPiece pieceID: UUID) -> [LaundryRecord] {
        laundryRecords.filter { $0.pieceID == pieceID }.sorted { $0.sentAt > $1.sentAt }
    }

    /// Load currently holding a piece.
    func laundryLoad(containing pieceID: UUID) -> LaundryLoad? {
        laundryLoads.first { $0.pieceIDs.contains(pieceID) }
    }

    /// Trips that are not finished and reference a piece.
    func upcomingTrips(using pieceID: UUID) -> [Trip] {
        trips.filter { trip in
            guard trip.phase != .completed else { return false }
            if trip.packing.contains(where: { $0.pieceID == pieceID }) { return true }
            return trip.days.contains { day in
                guard let outfitID = day.outfitID, let outfit = outfit(outfitID) else { return false }
                return outfit.contains(pieceID: pieceID)
            }
        }
    }

    /// The trip currently in progress, if any.
    var tripInProgress: Trip? { trips.first { $0.stage == .inProgress } }

    /// Next trip that has not finished, by start date.
    var nextTrip: Trip? {
        trips
            .filter { $0.phase != .completed && !$0.isDraft }
            .sorted { $0.startDate < $1.startDate }
            .first
    }

    /// Next event from today onward.
    var nextEvent: EventEntity? {
        let today = Calendar.wl.startOfDay(for: Date())
        return events
            .filter { Calendar.wl.startOfDay(for: $0.date) >= today && !$0.isWorn }
            .sorted { $0.date < $1.date }
            .first
    }

    /// Pieces sitting in the wash, whether basketed or in a load.
    var piecesInWash: [Piece] { pieces.filter { $0.status == .inWash } }

    /// Whether the user has enough history for the Insights section.
    var wearRecordDayCount: Int {
        Set(wearRecords.map { Calendar.wl.startOfDay(for: $0.date) }).count
    }
}

// MARK: - Resilient decoding
//
// A missing or malformed field falls back to its default so that one gap in the
// document can never cost the user their whole wardrobe.

// MARK: - Settings

extension WardrobeProfile {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayName = c.wl(.displayName, "")
        homeClimate = c.wl(.homeClimate, .temperate)
        seasons = c.wlArray(Season.self, .seasons)
        occasions = c.wlArray(Occasion.self, .occasions)
        laundryCycle = c.wl(.laundryCycle, .weekly)
        units = c.wl(.units, .metric)
        isComplete = c.wl(.isComplete, false)
    }
}

extension NotificationSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hasGrantedConsent = c.wl(.hasGrantedConsent, false)
        tripStartsInTwoDays = c.wl(.tripStartsInTwoDays, true)
        laundryReadyToReturn = c.wl(.laundryReadyToReturn, true)
        eventTomorrowWithoutOutfit = c.wl(.eventTomorrowWithoutOutfit, true)
        repairPending = c.wl(.repairPending, true)
    }
}

extension WeatherSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cityName = c.wl(.cityName, "")
        useDeviceLocation = c.wl(.useDeviceLocation, true)
        updateAutomatically = c.wl(.updateAutomatically, true)
    }
}

extension AppearanceSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        useDarkTripMode = c.wl(.useDarkTripMode, true)
        showHalftoneMotif = c.wl(.showHalftoneMotif, true)
        reduceMotion = c.wl(.reduceMotion, false)
    }
}

// MARK: - Root document

extension AppState {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = c.wl(.schemaVersion, AppState.currentSchemaVersion)
        hasSeenOnboarding = c.wl(.hasSeenOnboarding, false)
        profile = c.wl(.profile, WardrobeProfile())
        pieces = c.wlArray(Piece.self, .pieces)
        outfits = c.wlArray(Outfit.self, .outfits)
        dayPlans = c.wlArray(DayPlan.self, .dayPlans)
        events = c.wlArray(EventEntity.self, .events)
        washBasket = c.wlArray(UUID.self, .washBasket)
        laundryLoads = c.wlArray(LaundryLoad.self, .laundryLoads)
        laundryRecords = c.wlArray(LaundryRecord.self, .laundryRecords)
        wearRecords = c.wlArray(WearRecord.self, .wearRecords)
        repairs = c.wlArray(RepairIssue.self, .repairs)
        trips = c.wlArray(Trip.self, .trips)
        templates = c.wlArray(PackingTemplate.self, .templates)
        essentials = c.wlArray(EssentialItem.self, .essentials)
        categoryWeights = c.wl(.categoryWeights, AppState.defaultCategoryWeights)
        notificationSettings = c.wl(.notificationSettings, NotificationSettings())
        appearance = c.wl(.appearance, AppearanceSettings())
        weatherSettings = c.wl(.weatherSettings, WeatherSettings())
    }
}
