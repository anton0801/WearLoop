//
//  Fixtures.swift
//  WearLoopTests
//
//  Small builders so each test states only what it actually cares about.
//

import Foundation
@testable import WearLoop

enum Fixtures {

    /// A fixed "now" so nothing depends on when the suite happens to run.
    static let now = Calendar.wl.date(from: DateComponents(year: 2026, month: 8, day: 7, hour: 9))!

    static func piece(
        _ name: String,
        category: PieceCategory = .top,
        colours: [PieceColour] = [.navy],
        seasons: [Season] = [.allYear],
        occasions: [Occasion] = [.everyday],
        status: PieceStatus = .inRotation,
        weightGrams: Double? = nil,
        price: Double? = nil,
        material: String = "",
        careNotes: String = "",
        expectedBack: Date? = nil,
        id: UUID = UUID()
    ) -> Piece {
        var p = Piece(
            id: id,
            name: name,
            category: category,
            colours: colours,
            seasons: seasons,
            occasions: occasions
        )
        p.status = status
        p.weightGrams = weightGrams
        p.purchasePrice = price
        p.material = material
        p.careNotes = careNotes
        p.expectedBackDate = expectedBack
        return p
    }

    static func outfit(
        _ name: String,
        pieces: [Piece],
        occasion: Occasion = .everyday,
        formality: Formality = .casual,
        temperature: ClosedRange<Double> = 5...20,
        seasons: [Season] = [.allYear],
        id: UUID = UUID()
    ) -> Outfit {
        var o = Outfit(id: id, name: name, occasion: occasion)
        o.items = pieces.map { OutfitItem(pieceID: $0.id, layer: $0.category.naturalLayer) }
        o.formality = formality
        o.temperatureMin = temperature.lowerBound
        o.temperatureMax = temperature.upperBound
        o.seasons = seasons
        return o
    }

    /// A wardrobe with two complete, available outfits.
    static func populatedState() -> AppState {
        var state = AppState()
        state.hasSeenOnboarding = true
        state.profile.isComplete = true
        state.profile.seasons = [.allYear]
        state.profile.occasions = [.everyday, .work]

        let shirt = piece("Shirt", category: .top, weightGrams: 200, price: 60)
        let trousers = piece("Trousers", category: .bottom, weightGrams: 400, price: 100)
        let shoes = piece("Shoes", category: .footwear, weightGrams: 800, price: 150)
        let coat = piece("Coat", category: .outerwear, weightGrams: 1000, price: 300)

        state.pieces = [shirt, trousers, shoes, coat]
        state.outfits = [
            outfit("Office", pieces: [shirt, trousers, shoes], occasion: .work, formality: .business),
            outfit("Weekend", pieces: [shirt, trousers])
        ]
        return state
    }

    /// A three-day trip whose days are all planned with the first outfit.
    static func stateWithTrip() -> (AppState, UUID) {
        var state = populatedState()
        var trip = Trip(
            name: "Berlin",
            destination: "Berlin",
            startDate: now.wlStartOfDay,
            endDate: Calendar.wl.addingDays(2, to: now.wlStartOfDay),
            type: .work
        )
        WardrobeActions.rebuildDays(for: &trip)
        trip.isDraft = false
        trip.stage = .dayPlan
        trip.weightLimitKg = 8
        trip.luggageType = .cabinBag
        for index in trip.days.indices {
            trip.days[index].outfitID = state.outfits[0].id
            trip.days[index].occasions = [.work]
        }
        state.trips = [trip]
        WardrobeActions.refreshPacking(tripID: trip.id, in: &state)
        return (state, trip.id)
    }
}
