//
//  Enums.swift
//  WearLoop
//
//  Domain vocabulary. Every list here is closed and finite so that
//  stored data stays readable across app versions.
//

import SwiftUI

// MARK: - Piece category

enum PieceCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case top
    case bottom
    case outerwear
    case footwear
    case dress
    case accessory
    case bag
    case underlayer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .top: return "Top"
        case .bottom: return "Bottom"
        case .outerwear: return "Outerwear"
        case .footwear: return "Footwear"
        case .dress: return "Dress"
        case .accessory: return "Accessory"
        case .bag: return "Bag"
        case .underlayer: return "Underlayer"
        }
    }

    /// Fallback weight used by the luggage estimate when a piece has no real weight.
    var defaultWeightGrams: Double {
        switch self {
        case .top: return 220
        case .bottom: return 420
        case .outerwear: return 900
        case .footwear: return 800
        case .dress: return 350
        case .accessory: return 110
        case .bag: return 600
        case .underlayer: return 120
        }
    }

    /// Layer this category naturally belongs to when building an outfit.
    var naturalLayer: OutfitLayer {
        switch self {
        case .outerwear: return .outer
        case .top: return .top
        case .bottom, .dress: return .bottomOrDress
        case .footwear: return .footwear
        case .accessory, .bag: return .accessories
        case .underlayer: return .top
        }
    }
}

// MARK: - Season

enum Season: String, Codable, CaseIterable, Identifiable, Hashable {
    case winter
    case spring
    case summer
    case autumn
    case allYear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .winter: return "Winter"
        case .spring: return "Spring"
        case .summer: return "Summer"
        case .autumn: return "Autumn"
        case .allYear: return "All Year"
        }
    }

    /// Celsius band this season stands for. Used to derive outfit temperature ranges.
    var temperatureBand: ClosedRange<Double> {
        switch self {
        case .winter: return -15 ... 6
        case .spring: return 6 ... 18
        case .summer: return 17 ... 36
        case .autumn: return 4 ... 16
        case .allYear: return -5 ... 30
        }
    }

    /// Season a calendar month falls into on the northern hemisphere.
    static func forMonth(_ month: Int) -> Season {
        switch month {
        case 12, 1, 2: return .winter
        case 3, 4, 5: return .spring
        case 6, 7, 8: return .summer
        default: return .autumn
        }
    }
}

// MARK: - Occasion

enum Occasion: String, Codable, CaseIterable, Identifiable, Hashable {
    case everyday
    case work
    case formal
    case sport
    case home
    case goingOut

    var id: String { rawValue }

    var title: String {
        switch self {
        case .everyday: return "Everyday"
        case .work: return "Work"
        case .formal: return "Formal"
        case .sport: return "Sport"
        case .home: return "Home"
        case .goingOut: return "Going Out"
        }
    }

    /// Formality this occasion usually implies, used for soft warnings only.
    var impliedFormality: Formality {
        switch self {
        case .everyday, .home, .sport: return .casual
        case .work: return .business
        case .goingOut: return .smartCasual
        case .formal: return .formal
        }
    }
}

// MARK: - Condition & status

enum PieceCondition: String, Codable, CaseIterable, Identifiable, Hashable {
    case new
    case good
    case worn
    case needsRepair

    var id: String { rawValue }

    var title: String {
        switch self {
        case .new: return "New"
        case .good: return "Good"
        case .worn: return "Worn"
        case .needsRepair: return "Needs Repair"
        }
    }
}

/// Where a piece is right now. Drives availability everywhere in the app.
enum PieceStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case inRotation
    case inWash
    case needsRepair
    case storedAway
    case archived

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inRotation: return "In Rotation"
        case .inWash: return "In the Wash"
        case .needsRepair: return "Needs Repair"
        case .storedAway: return "Stored Away"
        case .archived: return "Archived"
        }
    }

    /// Short uppercase text for the corner tag on a card.
    var tagText: String {
        switch self {
        case .inRotation: return "IN ROTATION"
        case .inWash: return "IN THE WASH"
        case .needsRepair: return "NEEDS REPAIR"
        case .storedAway: return "STORED"
        case .archived: return "ARCHIVED"
        }
    }

    /// A piece must be in rotation to be planned, packed or worn.
    var isAvailable: Bool { self == .inRotation }
}

// MARK: - Formality & dress code

enum Formality: String, Codable, CaseIterable, Identifiable, Hashable {
    case casual
    case smartCasual
    case business
    case formal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .casual: return "Casual"
        case .smartCasual: return "Smart Casual"
        case .business: return "Business"
        case .formal: return "Formal"
        }
    }

    /// Comparable rank so the app can say "outfit is below the dress code".
    var rank: Int {
        switch self {
        case .casual: return 0
        case .smartCasual: return 1
        case .business: return 2
        case .formal: return 3
        }
    }
}

enum DressCode: String, Codable, CaseIterable, Identifiable, Hashable {
    case casual
    case smartCasual
    case business
    case cocktail
    case formal
    case themed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .casual: return "Casual"
        case .smartCasual: return "Smart Casual"
        case .business: return "Business"
        case .cocktail: return "Cocktail"
        case .formal: return "Formal"
        case .themed: return "Themed"
        }
    }

    /// Formality this dress code expects. `themed` has no ranking.
    var expectedFormality: Formality? {
        switch self {
        case .casual: return .casual
        case .smartCasual: return .smartCasual
        case .business: return .business
        case .cocktail: return .formal
        case .formal: return .formal
        case .themed: return nil
        }
    }
}

// MARK: - Profile settings

enum LaundryCycle: String, Codable, CaseIterable, Identifiable, Hashable {
    case every2Days
    case weekly
    case every2Weeks
    case irregular

    var id: String { rawValue }

    var title: String {
        switch self {
        case .every2Days: return "Every 2 Days"
        case .weekly: return "Weekly"
        case .every2Weeks: return "Every 2 Weeks"
        case .irregular: return "Irregular"
        }
    }

    /// Days the app assumes a wash takes. `irregular` gets a neutral week.
    var expectedDays: Int {
        switch self {
        case .every2Days: return 2
        case .weekly: return 7
        case .every2Weeks: return 14
        case .irregular: return 7
        }
    }
}

enum MeasurementUnits: String, Codable, CaseIterable, Identifiable, Hashable {
    case metric
    case imperial

    var id: String { rawValue }

    var title: String {
        switch self {
        case .metric: return "Metric (kg, °C)"
        case .imperial: return "Imperial (lb, °F)"
        }
    }
}

enum HomeClimate: String, Codable, CaseIterable, Identifiable, Hashable {
    case cold
    case temperate
    case warm
    case hot
    case variable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cold: return "Cold"
        case .temperate: return "Temperate"
        case .warm: return "Warm"
        case .hot: return "Hot"
        case .variable: return "Highly Variable"
        }
    }
}

// MARK: - Outfit layers

enum OutfitLayer: String, Codable, CaseIterable, Identifiable, Hashable {
    case outer
    case top
    case bottomOrDress
    case footwear
    case accessories

    var id: String { rawValue }

    var title: String {
        switch self {
        case .outer: return "Outer Layer"
        case .top: return "Top"
        case .bottomOrDress: return "Bottom or Dress"
        case .footwear: return "Footwear"
        case .accessories: return "Accessories"
        }
    }

    /// Categories offered when filling this layer.
    var allowedCategories: [PieceCategory] {
        switch self {
        case .outer: return [.outerwear]
        case .top: return [.top, .underlayer]
        case .bottomOrDress: return [.bottom, .dress]
        case .footwear: return [.footwear]
        case .accessories: return [.accessory, .bag]
        }
    }

    /// Stacking order in the flat-lay, bottom of the pile first.
    var flatLayOrder: Int {
        switch self {
        case .bottomOrDress: return 0
        case .top: return 1
        case .outer: return 2
        case .footwear: return 3
        case .accessories: return 4
        }
    }
}

// MARK: - Outfit availability

enum OutfitStatus: String, Codable, Hashable {
    case ready
    case partlyUnavailable
    case outOfSeason
    case needsRepair

    var title: String {
        switch self {
        case .ready: return "Ready"
        case .partlyUnavailable: return "Partly Unavailable"
        case .outOfSeason: return "Out of Season"
        case .needsRepair: return "Needs Repair"
        }
    }
}

// MARK: - Trips

enum TripType: String, Codable, CaseIterable, Identifiable, Hashable {
    case work
    case leisure
    case familyVisit
    case mixed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .work: return "Work"
        case .leisure: return "Leisure"
        case .familyVisit: return "Family Visit"
        case .mixed: return "Mixed"
        }
    }
}

enum TripDayOccasion: String, Codable, CaseIterable, Identifiable, Hashable {
    case travelDay
    case work
    case sightseeing
    case dinnerOut
    case beach
    case formalEvent
    case restDay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .travelDay: return "Travel Day"
        case .work: return "Work"
        case .sightseeing: return "Sightseeing"
        case .dinnerOut: return "Dinner Out"
        case .beach: return "Beach"
        case .formalEvent: return "Formal Event"
        case .restDay: return "Rest Day"
        }
    }

    /// Wardrobe occasion this trip occasion maps onto.
    var wardrobeOccasion: Occasion {
        switch self {
        case .travelDay: return .everyday
        case .work: return .work
        case .sightseeing: return .everyday
        case .dinnerOut: return .goingOut
        case .beach: return .sport
        case .formalEvent: return .formal
        case .restDay: return .home
        }
    }

    var expectedFormality: Formality {
        switch self {
        case .formalEvent: return .formal
        case .dinnerOut: return .smartCasual
        case .work: return .business
        default: return .casual
        }
    }
}

enum LuggageType: String, Codable, CaseIterable, Identifiable, Hashable {
    case cabinBag
    case checkedBag
    case backpack
    case noLimit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cabinBag: return "Cabin Bag"
        case .checkedBag: return "Checked Bag"
        case .backpack: return "Backpack"
        case .noLimit: return "No Limit"
        }
    }

    /// Suggested default limit in kilograms. `noLimit` has none.
    var suggestedLimitKg: Double? {
        switch self {
        case .cabinBag: return 8
        case .checkedBag: return 23
        case .backpack: return 10
        case .noLimit: return nil
        }
    }

    var allowsLimit: Bool { self != .noLimit }
}

/// Stages of the trip workspace indicator.
enum TripStage: String, Codable, CaseIterable, Identifiable, Hashable {
    case setup
    case dayPlan
    case packingList
    case weightCheck
    case ready
    case inProgress
    case recap

    var id: String { rawValue }

    var title: String {
        switch self {
        case .setup: return "Setup"
        case .dayPlan: return "Day Plan"
        case .packingList: return "Packing List"
        case .weightCheck: return "Weight Check"
        case .ready: return "Ready"
        case .inProgress: return "In Progress"
        case .recap: return "Recap"
        }
    }

    var order: Int { TripStage.allCases.firstIndex(of: self) ?? 0 }
}

/// Bucket a trip falls into on the trips list.
enum TripPhase: String, Codable, CaseIterable, Identifiable, Hashable {
    case upcoming
    case inProgress
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .upcoming: return "Upcoming"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        }
    }
}

// MARK: - Laundry

enum LaundryStage: String, Codable, CaseIterable, Identifiable, Hashable {
    case toWash
    case washingNow
    case drying
    case readyToReturn

    var id: String { rawValue }

    var title: String {
        switch self {
        case .toWash: return "To Wash"
        case .washingNow: return "Washing Now"
        case .drying: return "Drying"
        case .readyToReturn: return "Ready to Return"
        }
    }
}

// MARK: - Packing

/// Why a piece is on the packing list.
enum PackingSource: String, Codable, CaseIterable, Hashable {
    case fromOutfits
    case manual
    case essential

    var title: String {
        switch self {
        case .fromOutfits: return "From Outfits"
        case .manual: return "Added Manually"
        case .essential: return "Essentials"
        }
    }
}

// MARK: - Wear context

/// What the wear record was logged against.
enum WearContext: String, Codable, Hashable {
    case day
    case event
    case trip

    var title: String {
        switch self {
        case .day: return "Planned Day"
        case .event: return "Event"
        case .trip: return "Trip"
        }
    }
}

// MARK: - Piece colour

/// Fixed colour vocabulary. The hex is used only for the generated cover of a
/// piece with no photograph — real photographs are never tinted.
enum PieceColour: String, Codable, CaseIterable, Identifiable, Hashable {
    case black
    case charcoal
    case grey
    case white
    case cream
    case beige
    case brown
    case tan
    case navy
    case blue
    case lightBlue
    case denim
    case teal
    case green
    case olive
    case yellow
    case orange
    case red
    case burgundy
    case pink
    case purple
    case multicolour
    case metallic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .black: return "Black"
        case .charcoal: return "Charcoal"
        case .grey: return "Grey"
        case .white: return "White"
        case .cream: return "Cream"
        case .beige: return "Beige"
        case .brown: return "Brown"
        case .tan: return "Tan"
        case .navy: return "Navy"
        case .blue: return "Blue"
        case .lightBlue: return "Light Blue"
        case .denim: return "Denim"
        case .teal: return "Teal"
        case .green: return "Green"
        case .olive: return "Olive"
        case .yellow: return "Yellow"
        case .orange: return "Orange"
        case .red: return "Red"
        case .burgundy: return "Burgundy"
        case .pink: return "Pink"
        case .purple: return "Purple"
        case .multicolour: return "Multicolour"
        case .metallic: return "Metallic"
        }
    }

    var hex: String {
        switch self {
        case .black: return "#1A1A1A"
        case .charcoal: return "#3B3B3B"
        case .grey: return "#8E8E8E"
        case .white: return "#F4F4F0"
        case .cream: return "#EFE3C8"
        case .beige: return "#D8C4A0"
        case .brown: return "#6B4A2F"
        case .tan: return "#B58A5A"
        case .navy: return "#1F2A44"
        case .blue: return "#2C5CA8"
        case .lightBlue: return "#8AB4DC"
        case .denim: return "#4A6D93"
        case .teal: return "#2E7C74"
        case .green: return "#3F7A44"
        case .olive: return "#6B7141"
        case .yellow: return "#E8C33C"
        case .orange: return "#D9782E"
        case .red: return "#B8342C"
        case .burgundy: return "#6E2036"
        case .pink: return "#D98BA6"
        case .purple: return "#6A4A8C"
        case .multicolour: return "#8E6FA8"
        case .metallic: return "#A8A6A0"
        }
    }

    var colour: Color { Color(hex: hex) }

    /// Whether white text reads on top of this colour.
    var prefersLightText: Bool {
        switch self {
        case .white, .cream, .beige, .yellow, .lightBlue, .tan, .metallic, .grey:
            return false
        default:
            return true
        }
    }
}
