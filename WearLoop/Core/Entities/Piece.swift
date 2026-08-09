//
//  Piece.swift
//  WearLoop
//
//  A single garment. Entered once, used by outfits, plans, trips and stats.
//

import Foundation

struct Piece: Identifiable, Codable, Hashable {
    var id: UUID = UUID()

    // Required
    var name: String
    var category: PieceCategory
    var colours: [PieceColour]
    var seasons: [Season]
    var occasions: [Occasion]

    // Optional detail
    var material: String = ""
    var size: String = ""
    var condition: PieceCondition = .good
    var storagePlace: String = ""
    var purchasePrice: Double?
    var purchaseDate: Date?
    var photoID: String?
    var tags: [String] = []
    var careNotes: String = ""
    var privateNote: String = ""

    /// Real weight in grams. When nil the luggage estimate falls back to the
    /// category average and says so explicitly.
    var weightGrams: Double?

    // Lifecycle
    var status: PieceStatus = .inRotation
    /// Date the piece is expected back from the wash, when it is in the wash.
    var expectedBackDate: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var primaryColour: PieceColour { colours.first ?? .grey }

    var hasPhoto: Bool { photoID != nil }

    /// Weight used by estimates, plus whether it was a guess.
    func estimatedWeight(categoryWeights: [PieceCategory: Double]) -> (grams: Double, isEstimate: Bool) {
        if let weightGrams, weightGrams > 0 {
            return (weightGrams, false)
        }
        let fallback = categoryWeights[category] ?? category.defaultWeightGrams
        return (fallback, true)
    }

    /// Celsius band the piece is comfortable in, from its seasons.
    var temperatureBand: ClosedRange<Double> {
        guard let first = seasons.first else { return Season.allYear.temperatureBand }
        var lower = first.temperatureBand.lowerBound
        var upper = first.temperatureBand.upperBound
        for season in seasons.dropFirst() {
            lower = min(lower, season.temperatureBand.lowerBound)
            upper = max(upper, season.temperatureBand.upperBound)
        }
        return lower ... upper
    }

    /// Text used when searching.
    var searchHaystack: String {
        ([name, material, size, storagePlace, careNotes] + tags + colours.map(\.title) + [category.title])
            .joined(separator: " ")
            .lowercased()
    }
}

/// Frozen copy of a piece kept by history records so that deleting a garment
/// never rewrites the past.
struct PieceSnapshot: Codable, Hashable, Identifiable {
    var id: UUID { pieceID }
    var pieceID: UUID
    var name: String
    var category: PieceCategory
    var photoID: String?
    var colour: PieceColour

    init(piece: Piece) {
        self.pieceID = piece.id
        self.name = piece.name
        self.category = piece.category
        self.photoID = piece.photoID
        self.colour = piece.primaryColour
    }

    init(pieceID: UUID, name: String, category: PieceCategory, photoID: String?, colour: PieceColour) {
        self.pieceID = pieceID
        self.name = name
        self.category = category
        self.photoID = photoID
        self.colour = colour
    }
}

/// One completed trip through the wash for one piece.
struct LaundryRecord: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var pieceID: UUID
    var snapshot: PieceSnapshot
    var loadName: String
    var sentAt: Date
    var returnedAt: Date?
    var temperatureC: Int?
}

/// A reported problem with a piece.
struct RepairIssue: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var pieceID: UUID
    var snapshot: PieceSnapshot
    var issue: String
    var reportedOn: Date
    var plannedAction: String = ""
    var cost: Double?
    var completedOn: Date?

    var isOpen: Bool { completedOn == nil }

    /// Days the issue has been open. Used for the 60-day retire suggestion.
    func daysOpen(now: Date = Date()) -> Int {
        guard completedOn == nil else { return 0 }
        return Calendar.wl.dayCount(from: reportedOn, to: now)
    }
}

// MARK: - Resilient decoding
//
// A missing or malformed field falls back to its default so that one gap in the
// document can never cost the user their whole wardrobe.

// MARK: - Piece

extension Piece {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.wl(.id, UUID())
        name = c.wlName(.name, "Untitled piece")
        category = c.wl(.category, .top)
        colours = c.wlArray(PieceColour.self, .colours)
        seasons = c.wlArray(Season.self, .seasons)
        occasions = c.wlArray(Occasion.self, .occasions)
        material = c.wl(.material, "")
        size = c.wl(.size, "")
        condition = c.wl(.condition, .good)
        storagePlace = c.wl(.storagePlace, "")
        purchasePrice = c.wlOptional(Double.self, .purchasePrice)
        purchaseDate = c.wlOptional(Date.self, .purchaseDate)
        photoID = c.wlOptional(String.self, .photoID)
        tags = c.wlArray(String.self, .tags)
        careNotes = c.wl(.careNotes, "")
        privateNote = c.wl(.privateNote, "")
        weightGrams = c.wlOptional(Double.self, .weightGrams)
        status = c.wl(.status, .inRotation)
        expectedBackDate = c.wlOptional(Date.self, .expectedBackDate)
        createdAt = c.wl(.createdAt, Date())
        updatedAt = c.wl(.updatedAt, Date())

        // A piece must always have at least one colour to draw its cover.
        if colours.isEmpty { colours = [.grey] }
    }
}

extension PieceSnapshot {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pieceID = c.wl(.pieceID, UUID())
        name = c.wlName(.name, "Deleted piece")
        category = c.wl(.category, .top)
        photoID = c.wlOptional(String.self, .photoID)
        colour = c.wl(.colour, .grey)
    }
}

extension LaundryRecord {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.wl(.id, UUID())
        pieceID = c.wl(.pieceID, UUID())
        snapshot = c.wl(.snapshot, PieceSnapshot(pieceID: pieceID, name: "Deleted piece", category: .top, photoID: nil, colour: .grey))
        loadName = c.wl(.loadName, "Wash load")
        sentAt = c.wl(.sentAt, Date())
        returnedAt = c.wlOptional(Date.self, .returnedAt)
        temperatureC = c.wlOptional(Int.self, .temperatureC)
    }
}

extension RepairIssue {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.wl(.id, UUID())
        pieceID = c.wl(.pieceID, UUID())
        snapshot = c.wl(.snapshot, PieceSnapshot(pieceID: pieceID, name: "Deleted piece", category: .top, photoID: nil, colour: .grey))
        issue = c.wl(.issue, "Needs repair")
        reportedOn = c.wl(.reportedOn, Date())
        plannedAction = c.wl(.plannedAction, "")
        cost = c.wlOptional(Double.self, .cost)
        completedOn = c.wlOptional(Date.self, .completedOn)
    }
}
