//
//  SuggestionEngine.swift
//  WearLoop
//
//  Picks an outfit for today and explains why, and works out the single most
//  useful next step. Both answer questions, never decorate the screen.
//

import Foundation

struct OutfitSuggestion {
    var outfit: Outfit
    /// Reasons the outfit was picked, shown under "Why This Outfit".
    var reasons: [String]
}

enum SuggestionEngine {

    /// Best available outfit for a date, with the reasoning behind it.
    static func suggest(
        for date: Date,
        state: AppState,
        weather: WeatherInput?,
        occasion: Occasion?
    ) -> OutfitSuggestion? {
        let season = Season.forMonth(Calendar.wl.component(.month, from: date))
        let candidates = state.activeOutfits.filter { AvailabilityEngine.isAssignable(outfit: $0, state: state) }
        guard !candidates.isEmpty else { return nil }

        var best: (outfit: Outfit, score: Double, reasons: [String])?

        for outfit in candidates {
            var score: Double = 0
            var reasons: [String] = []

            // Season
            if outfit.seasons.contains(.allYear) || outfit.seasons.contains(season) {
                score += 30
                reasons.append("Set for \(season.title.lowercased())")
            } else if !outfit.seasons.isEmpty {
                score -= 25
            }

            // Weather against the outfit's own range
            if let weather {
                let temperature = weather.temperatureC
                if temperature >= outfit.temperatureMin && temperature <= outfit.temperatureMax {
                    score += 40
                    reasons.append("Fits \(UnitFormatter.temperature(temperature, units: state.profile.units)) today")
                } else {
                    let distance = min(abs(temperature - outfit.temperatureMin), abs(temperature - outfit.temperatureMax))
                    score -= min(distance * 4, 50)
                }
                if weather.rain {
                    let hasOuter = outfit.items.contains { $0.layer == .outer }
                    if hasOuter {
                        score += 12
                        reasons.append("Has an outer layer for the rain")
                    } else {
                        score -= 18
                    }
                }
            }

            // Occasion: the day's own, otherwise the user's usual ones
            if let occasion {
                if outfit.occasion == occasion {
                    score += 35
                    reasons.append("Made for \(occasion.title.lowercased())")
                } else {
                    score -= 10
                }
            } else if state.profile.occasions.contains(outfit.occasion) {
                score += 12
                reasons.append("One of your usual occasions")
            }

            // Rotation: prefer something not worn recently
            if let lastWorn = state.lastWorn(outfitID: outfit.id) {
                let days = Calendar.wl.dayCount(from: lastWorn, to: date)
                if days <= 2 {
                    score -= 40
                } else if days >= 21 {
                    score += 18
                    reasons.append("Not worn in \(Plural.count(days, "day"))")
                } else if days >= 7 {
                    score += 8
                }
            } else {
                score += 22
                reasons.append("Never worn yet")
            }

            if outfit.isFavorite {
                score += 10
                reasons.append("One of your favourites")
            }

            // Nudge towards pieces that have never been used
            let neverWorn = outfit.pieceIDs.filter { state.wearCount(forPiece: $0) == 0 }.count
            if neverWorn > 0 {
                score += Double(min(neverWorn, 3)) * 4
            }

            if let current = best {
                if score > current.score { best = (outfit, score, reasons) }
            } else {
                best = (outfit, score, reasons)
            }
        }

        guard let best else { return nil }
        var reasons = best.reasons
        if reasons.isEmpty {
            reasons.append("Every piece is in rotation")
        }
        return OutfitSuggestion(outfit: best.outfit, reasons: reasons)
    }

    /// Outfits ordered by how well they fit a set of requirements, for pickers.
    static func rank(
        outfits: [Outfit],
        state: AppState,
        temperature: Double?,
        occasion: Occasion?,
        requiredFormality: Formality?
    ) -> [Outfit] {
        outfits.sorted { a, b in
            score(a, state: state, temperature: temperature, occasion: occasion, requiredFormality: requiredFormality)
                > score(b, state: state, temperature: temperature, occasion: occasion, requiredFormality: requiredFormality)
        }
    }

    private static func score(
        _ outfit: Outfit,
        state: AppState,
        temperature: Double?,
        occasion: Occasion?,
        requiredFormality: Formality?
    ) -> Double {
        var score: Double = 0
        if AvailabilityEngine.isAssignable(outfit: outfit, state: state) { score += 50 }
        if let temperature, temperature >= outfit.temperatureMin, temperature <= outfit.temperatureMax { score += 30 }
        if let occasion, outfit.occasion == occasion { score += 25 }
        if let requiredFormality, outfit.formality.rank >= requiredFormality.rank { score += 20 }
        if outfit.isFavorite { score += 5 }
        return score
    }
}

// MARK: - Next step

/// The one thing most worth doing right now.
struct NextStep: Identifiable, Hashable {
    enum Action: Hashable {
        case addPiece
        case buildOutfit
        case assignEventOutfit(UUID)
        case planTripDays(UUID)
        case returnLaundry
        case fixRepairs
        case planTomorrow
        case completeSetup
        case reviewTripWeight(UUID)
    }

    var id: String { title }
    var title: String
    var detail: String
    var action: Action
}

enum NextStepEngine {

    /// Highest-value next step, or nil when nothing needs attention.
    static func nextStep(state: AppState, now: Date = Date()) -> NextStep? {
        let today = now.wlStartOfDay

        // Nothing to work with yet.
        if state.pieces.isEmpty {
            return NextStep(
                title: "Add Your First Piece",
                detail: "The app needs a few pieces before it can build anything.",
                action: .addPiece
            )
        }
        if state.activeOutfits.isEmpty {
            return NextStep(
                title: "Build First Outfit",
                detail: "You have \(Plural.count(state.activePieces.count, "piece")) and no outfits yet. Outfits are what the app plans with.",
                action: .buildOutfit
            )
        }

        // Pieces stuck in the wash longer than the user's own cycle.
        let cycleDays = state.profile.laundryCycle.expectedDays
        let stuck = state.piecesInWash.filter { piece in
            guard let back = piece.expectedBackDate else { return false }
            return back < today
        }
        if stuck.count >= 3 {
            return NextStep(
                title: "\(Plural.count(stuck.count, "Piece")) Stuck in the Wash",
                detail: "They were due back more than \(Plural.count(cycleDays, "day")) ago.",
                action: .returnLaundry
            )
        }

        // An event within a week with no outfit assigned.
        let soonEvents = state.events
            .filter { !$0.isWorn && $0.date.wlStartOfDay >= today }
            .sorted { $0.date < $1.date }
        if let event = soonEvents.first(where: { $0.outfitID == nil }),
           Calendar.wl.dayCount(from: today, to: event.date) <= 10 {
            let dayText = DateFormatterCache.relativeDayText(event.date, now: now)
            return NextStep(
                title: "Assign an Outfit for \(dayText.capitalizedFirst)",
                detail: "\(event.name) has no outfit yet.",
                action: .assignEventOutfit(event.id)
            )
        }

        // A trip with days that have no outfit.
        if let trip = state.trips
            .filter({ $0.phase != .completed && !$0.isDraft })
            .sorted(by: { $0.startDate < $1.startDate })
            .first(where: { !$0.daysWithoutPlan.isEmpty }) {
            let count = trip.daysWithoutPlan.count
            return NextStep(
                title: count == 1 ? "One Day Has No Outfit" : "\(Plural.count(count, "Day")) Have No Outfit",
                detail: "\(trip.name) starts \(DateFormatterCache.relativeDayText(trip.startDate, now: now)).",
                action: .planTripDays(trip.id)
            )
        }

        // A trip that is over its weight limit.
        if let trip = state.trips.first(where: { $0.phase == .upcoming && !$0.isDraft && !$0.packing.isEmpty }) {
            let estimate = LuggageEngine.estimate(trip: trip, state: state)
            if estimate.isOverLimit {
                let over = UnitFormatter.bagWeight(grams: estimate.overByGrams, units: state.profile.units)
                return NextStep(
                    title: "Bag Is Over by \(over)",
                    detail: "\(trip.name) needs \(over) taken out of the bag.",
                    action: .reviewTripWeight(trip.id)
                )
            }
        }

        // Laundry waiting to go back into the wardrobe.
        let readyLoads = state.laundryLoads.filter { $0.stage == .readyToReturn }
        if !readyLoads.isEmpty {
            let count = readyLoads.reduce(0) { $0 + $1.pieceIDs.count }
            return NextStep(
                title: "Return \(Plural.count(count, "Piece")) to the Wardrobe",
                detail: readyLoads.count == 1
                    ? "\(readyLoads[0].name) is dry and ready."
                    : "\(Plural.count(readyLoads.count, "load")) are dry and ready.",
                action: .returnLaundry
            )
        }

        // Repairs open for a long time.
        let oldRepairs = state.openRepairs.filter { $0.daysOpen(now: now) >= 30 }
        if !oldRepairs.isEmpty {
            return NextStep(
                title: "\(Plural.count(oldRepairs.count, "Repair")) Still Open",
                detail: "Reported more than a month ago.",
                action: .fixRepairs
            )
        }

        // Tomorrow has nothing planned.
        let tomorrow = Calendar.wl.addingDays(1, to: today)
        let tomorrowPlan = state.dayPlan(for: tomorrow)
        if tomorrowPlan?.outfitID == nil {
            return NextStep(
                title: "Plan Tomorrow",
                detail: "No outfit assigned for \(DateFormatterCache.weekdayLong.string(from: tomorrow)) yet.",
                action: .planTomorrow
            )
        }

        return nil
    }
}

extension String {
    /// "friday" -> "Friday", leaving the rest of the string alone.
    var capitalizedFirst: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
