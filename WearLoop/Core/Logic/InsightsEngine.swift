//
//  InsightsEngine.swift
//  WearLoop
//
//  Statistics built only from real records. When there is not enough history the
//  engine says so instead of drawing an empty chart.
//

import Foundation

/// The metrics available in the Insights section.
enum InsightKind: String, CaseIterable, Identifiable, Hashable, Codable {
    case mostWorn
    case neverWorn
    case costPerWear
    case wardrobeInRotation
    case coloursWorn
    case occasionsDressedFor
    case packingAccuracy
    case boughtNeverUsed
    case repairBacklog

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mostWorn: return "Most Worn Pieces"
        case .neverWorn: return "Never Worn"
        case .costPerWear: return "Cost per Wear"
        case .wardrobeInRotation: return "Wardrobe in Rotation"
        case .coloursWorn: return "Colours You Actually Wear"
        case .occasionsDressedFor: return "Occasions You Dress For"
        case .packingAccuracy: return "Packing Accuracy"
        case .boughtNeverUsed: return "Pieces Bought and Never Used"
        case .repairBacklog: return "Repair Backlog"
        }
    }
}

/// One row of a metric: a label, a number, and the records behind it.
struct InsightRow: Identifiable, Hashable {
    var id: String
    var label: String
    var valueText: String
    /// 0...1, used for the bar length. Nil for rows with no bar.
    var fraction: Double?
    var pieceID: UUID?
    var colour: PieceColour?
    var detail: String?
}

struct InsightMetric: Identifiable {
    var id: String { kind.rawValue }
    var kind: InsightKind
    var headline: String
    /// A short explanation of what the number means.
    var subtitle: String
    var rows: [InsightRow]
    /// Set when the metric cannot be computed yet.
    var lockedMessage: String?

    var isLocked: Bool { lockedMessage != nil }
}

enum InsightsEngine {

    /// Days of wear history needed before the patterns section unlocks.
    static let requiredWearDays = 10

    static func isUnlocked(state: AppState) -> Bool {
        state.wearRecordDayCount >= requiredWearDays
    }

    static func lockMessage(state: AppState) -> String {
        let remaining = max(requiredWearDays - state.wearRecordDayCount, 0)
        return "Mark at least \(requiredWearDays) days as worn to unlock wardrobe patterns. \(Plural.count(remaining, "day")) to go."
    }

    // MARK: - All metrics

    static func metrics(state: AppState, now: Date = Date()) -> [InsightMetric] {
        InsightKind.allCases.map { metric($0, state: state, now: now) }
    }

    static func metric(_ kind: InsightKind, state: AppState, now: Date = Date()) -> InsightMetric {
        switch kind {
        case .mostWorn: return mostWorn(state: state)
        case .neverWorn: return neverWorn(state: state, now: now)
        case .costPerWear: return costPerWear(state: state)
        case .wardrobeInRotation: return wardrobeInRotation(state: state)
        case .coloursWorn: return coloursWorn(state: state)
        case .occasionsDressedFor: return occasionsDressedFor(state: state)
        case .packingAccuracy: return packingAccuracy(state: state)
        case .boughtNeverUsed: return boughtNeverUsed(state: state, now: now)
        case .repairBacklog: return repairBacklog(state: state, now: now)
        }
    }

    // MARK: - Individual metrics

    private static func mostWorn(state: AppState) -> InsightMetric {
        let counted = state.activePieces
            .map { (piece: $0, count: state.wearCount(forPiece: $0.id)) }
            .filter { $0.count > 0 }
            .sorted { $0.count > $1.count }

        guard let top = counted.first else {
            return InsightMetric(
                kind: .mostWorn,
                headline: "—",
                subtitle: "No wear records yet.",
                rows: [],
                lockedMessage: "Mark a day as worn and your most used pieces appear here."
            )
        }

        let rows = counted.prefix(12).map { entry in
            InsightRow(
                id: entry.piece.id.uuidString,
                label: entry.piece.name,
                valueText: Plural.count(entry.count, "wear"),
                fraction: Double(entry.count) / Double(top.count),
                pieceID: entry.piece.id,
                colour: entry.piece.primaryColour,
                detail: entry.piece.category.title
            )
        }

        return InsightMetric(
            kind: .mostWorn,
            headline: "\(top.count)",
            subtitle: "\(top.piece.name): worn more than anything else you own.",
            rows: Array(rows),
            lockedMessage: nil
        )
    }

    private static func neverWorn(state: AppState, now: Date) -> InsightMetric {
        let never = state.activePieces.filter { state.wearCount(forPiece: $0.id) == 0 }
        let rows = never
            .sorted { $0.createdAt < $1.createdAt }
            .map { piece in
                InsightRow(
                    id: piece.id.uuidString,
                    label: piece.name,
                    valueText: "\(Plural.count(Calendar.wl.dayCount(from: piece.createdAt, to: now), "day")) owned",
                    fraction: nil,
                    pieceID: piece.id,
                    colour: piece.primaryColour,
                    detail: piece.category.title
                )
            }

        let share = state.activePieces.isEmpty ? 0 : Double(never.count) / Double(state.activePieces.count)
        return InsightMetric(
            kind: .neverWorn,
            headline: "\(never.count)",
            subtitle: never.isEmpty
                ? "Everything you own has been worn at least once."
                : "\(UnitFormatter.percent(share)) of your wardrobe has never been worn.",
            rows: rows,
            lockedMessage: state.activePieces.isEmpty ? "Add pieces to your wardrobe first." : nil
        )
    }

    private static func costPerWear(state: AppState) -> InsightMetric {
        let priced = state.activePieces.compactMap { piece -> (Piece, Double)? in
            guard let cost = state.costPerWear(pieceID: piece.id) else { return nil }
            return (piece, cost)
        }.sorted { $0.1 > $1.1 }

        guard let worst = priced.first else {
            return InsightMetric(
                kind: .costPerWear,
                headline: "—",
                subtitle: "Needs a purchase price and at least one wear.",
                rows: [],
                lockedMessage: "Add purchase prices to your pieces and mark days as worn to see cost per wear."
            )
        }

        let rows = priced.prefix(15).map { entry in
            InsightRow(
                id: entry.0.id.uuidString,
                label: entry.0.name,
                valueText: UnitFormatter.money(entry.1),
                fraction: entry.1 / worst.1,
                pieceID: entry.0.id,
                colour: entry.0.primaryColour,
                detail: "\(Plural.count(state.wearCount(forPiece: entry.0.id), "wear")) · \(UnitFormatter.money(entry.0.purchasePrice ?? 0))"
            )
        }

        return InsightMetric(
            kind: .costPerWear,
            headline: UnitFormatter.money(worst.1),
            subtitle: "\(worst.0.name): the highest cost per wearing in your wardrobe.",
            rows: Array(rows),
            lockedMessage: nil
        )
    }

    private static func wardrobeInRotation(state: AppState) -> InsightMetric {
        let active = state.activePieces
        guard !active.isEmpty else {
            return InsightMetric(
                kind: .wardrobeInRotation,
                headline: "—",
                subtitle: "No pieces yet.",
                rows: [],
                lockedMessage: "Add pieces to your wardrobe first."
            )
        }
        var counts: [PieceStatus: Int] = [:]
        for piece in state.pieces { counts[piece.status, default: 0] += 1 }
        let total = state.pieces.count
        let rotating = counts[.inRotation] ?? 0

        let rows = PieceStatus.allCases.compactMap { status -> InsightRow? in
            let count = counts[status] ?? 0
            guard count > 0 else { return nil }
            return InsightRow(
                id: status.rawValue,
                label: status.title,
                valueText: Plural.count(count, "piece"),
                fraction: Double(count) / Double(total),
                pieceID: nil,
                colour: nil,
                detail: UnitFormatter.percent(Double(count) / Double(total))
            )
        }

        return InsightMetric(
            kind: .wardrobeInRotation,
            headline: UnitFormatter.percent(Double(rotating) / Double(total)),
            subtitle: "\(Plural.count(rotating, "piece")) of \(total) are in rotation right now.",
            rows: rows,
            lockedMessage: nil
        )
    }

    private static func coloursWorn(state: AppState) -> InsightMetric {
        var counts: [PieceColour: Int] = [:]
        for record in state.wearRecords {
            for snapshot in record.pieceSnapshots {
                counts[snapshot.colour, default: 0] += 1
            }
        }
        let sorted = counts.sorted { $0.value > $1.value }
        guard let top = sorted.first else {
            return InsightMetric(
                kind: .coloursWorn,
                headline: "—",
                subtitle: "No wear records yet.",
                rows: [],
                lockedMessage: "Mark days as worn to see which colours you really reach for."
            )
        }
        let total = counts.values.reduce(0, +)
        let rows = sorted.map { entry in
            InsightRow(
                id: entry.key.rawValue,
                label: entry.key.title,
                valueText: UnitFormatter.percent(Double(entry.value) / Double(total)),
                fraction: Double(entry.value) / Double(top.value),
                pieceID: nil,
                colour: entry.key,
                detail: Plural.count(entry.value, "wear")
            )
        }
        return InsightMetric(
            kind: .coloursWorn,
            headline: top.key.title,
            subtitle: "\(UnitFormatter.percent(Double(top.value) / Double(total))) of everything you wear is \(top.key.title.lowercased()).",
            rows: rows,
            lockedMessage: nil
        )
    }

    private static func occasionsDressedFor(state: AppState) -> InsightMetric {
        var counts: [Occasion: Int] = [:]
        for record in state.wearRecords {
            guard let outfitID = record.outfitID, let outfit = state.outfit(outfitID) else { continue }
            counts[outfit.occasion, default: 0] += 1
        }
        let sorted = counts.sorted { $0.value > $1.value }
        guard let top = sorted.first else {
            return InsightMetric(
                kind: .occasionsDressedFor,
                headline: "—",
                subtitle: "No wear records linked to an outfit yet.",
                rows: [],
                lockedMessage: "Mark days as worn using your outfits to see which occasions you dress for."
            )
        }
        let total = counts.values.reduce(0, +)
        let rows = sorted.map { entry in
            InsightRow(
                id: entry.key.rawValue,
                label: entry.key.title,
                valueText: Plural.count(entry.value, "day"),
                fraction: Double(entry.value) / Double(top.value),
                pieceID: nil,
                colour: nil,
                detail: UnitFormatter.percent(Double(entry.value) / Double(total))
            )
        }
        return InsightMetric(
            kind: .occasionsDressedFor,
            headline: top.key.title,
            subtitle: "You dress for \(top.key.title.lowercased()) more than anything else.",
            rows: rows,
            lockedMessage: nil
        )
    }

    private static func packingAccuracy(state: AppState) -> InsightMetric {
        let finished = state.trips.filter { $0.recap != nil }
        guard !finished.isEmpty else {
            return InsightMetric(
                kind: .packingAccuracy,
                headline: "—",
                subtitle: "No finished trips yet.",
                rows: [],
                lockedMessage: "Finish a trip and record what you wore to measure how well you pack."
            )
        }

        var packedTotal = 0
        var wornTotal = 0
        var rows: [InsightRow] = []

        for trip in finished.sorted(by: { $0.startDate > $1.startDate }) {
            guard let recap = trip.recap else { continue }
            packedTotal += recap.packedCount
            wornTotal += recap.wornCount
            let accuracy = recap.packedCount > 0 ? Double(recap.wornCount) / Double(recap.packedCount) : 0
            rows.append(
                InsightRow(
                    id: trip.id.uuidString,
                    label: trip.name,
                    valueText: UnitFormatter.percent(accuracy),
                    fraction: accuracy,
                    pieceID: nil,
                    colour: nil,
                    detail: "Packed \(recap.packedCount), wore \(recap.wornCount)"
                )
            )
        }

        let overall = packedTotal > 0 ? Double(wornTotal) / Double(packedTotal) : 0
        return InsightMetric(
            kind: .packingAccuracy,
            headline: UnitFormatter.percent(overall),
            subtitle: "Across \(Plural.count(finished.count, "trip")) you wore \(wornTotal) of \(packedTotal) packed pieces.",
            rows: rows,
            lockedMessage: nil
        )
    }

    private static func boughtNeverUsed(state: AppState, now: Date) -> InsightMetric {
        let wasted = state.activePieces.filter { piece in
            state.wearCount(forPiece: piece.id) == 0 && (piece.purchasePrice ?? 0) > 0
        }
        let total = wasted.reduce(0) { $0 + ($1.purchasePrice ?? 0) }
        let rows = wasted
            .sorted { ($0.purchasePrice ?? 0) > ($1.purchasePrice ?? 0) }
            .map { piece in
                InsightRow(
                    id: piece.id.uuidString,
                    label: piece.name,
                    valueText: UnitFormatter.money(piece.purchasePrice ?? 0),
                    fraction: total > 0 ? (piece.purchasePrice ?? 0) / total : nil,
                    pieceID: piece.id,
                    colour: piece.primaryColour,
                    detail: piece.purchaseDate.map { "Bought \(DateFormatterCache.dayMonthYear.string(from: $0))" }
                        ?? "\(Plural.count(Calendar.wl.dayCount(from: piece.createdAt, to: now), "day")) owned"
                )
            }
        return InsightMetric(
            kind: .boughtNeverUsed,
            headline: wasted.isEmpty ? UnitFormatter.money(0) : UnitFormatter.money(total),
            subtitle: wasted.isEmpty
                ? "Nothing with a price has gone unworn."
                : "\(Plural.count(wasted.count, "piece")) with a price have never been worn.",
            rows: rows,
            lockedMessage: state.activePieces.contains(where: { $0.purchasePrice != nil })
                ? nil
                : "Add purchase prices to see what your wardrobe is wasting."
        )
    }

    private static func repairBacklog(state: AppState, now: Date) -> InsightMetric {
        let open = state.openRepairs
        let rows = open.map { repair in
            InsightRow(
                id: repair.id.uuidString,
                label: repair.snapshot.name,
                valueText: "\(Plural.count(repair.daysOpen(now: now), "day"))",
                fraction: nil,
                pieceID: repair.pieceID,
                colour: repair.snapshot.colour,
                detail: repair.issue
            )
        }
        let oldest = open.map { $0.daysOpen(now: now) }.max() ?? 0
        return InsightMetric(
            kind: .repairBacklog,
            headline: "\(open.count)",
            subtitle: open.isEmpty
                ? "Nothing is waiting to be repaired."
                : "The oldest issue has been open for \(Plural.count(oldest, "day")).",
            rows: rows,
            lockedMessage: nil
        )
    }

    // MARK: - Related records

    /// Wear records behind a metric row, for "View Related Records".
    static func relatedRecords(for row: InsightRow, kind: InsightKind, state: AppState) -> [WearRecord] {
        if let pieceID = row.pieceID {
            return state.wearRecords(forPiece: pieceID)
        }
        switch kind {
        case .coloursWorn:
            guard let colour = row.colour else { return [] }
            return state.wearRecords
                .filter { $0.pieceSnapshots.contains { $0.colour == colour } }
                .sorted { $0.date > $1.date }
        case .occasionsDressedFor:
            guard let occasion = Occasion(rawValue: row.id) else { return [] }
            return state.wearRecords
                .filter { record in
                    guard let outfitID = record.outfitID, let outfit = state.outfit(outfitID) else { return false }
                    return outfit.occasion == occasion
                }
                .sorted { $0.date > $1.date }
        case .packingAccuracy:
            guard let tripID = UUID(uuidString: row.id) else { return [] }
            return state.wearRecords.filter { $0.tripID == tripID }.sorted { $0.date > $1.date }
        case .wardrobeInRotation:
            guard let status = PieceStatus(rawValue: row.id) else { return [] }
            let ids = Set(state.pieces.filter { $0.status == status }.map(\.id))
            return state.wearRecords
                .filter { !ids.isDisjoint(with: Set($0.pieceIDs)) }
                .sorted { $0.date > $1.date }
        default:
            return []
        }
    }
}
