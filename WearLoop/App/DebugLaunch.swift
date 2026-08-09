//
//  DebugLaunch.swift
//  WearLoop
//
//  Development-only hook that opens a named screen straight from a launch
//  argument, so every screen can be inspected during development without
//  tapping through the app. It is compiled out of release builds entirely and
//  is not reachable from anywhere in the interface.
//

#if DEBUG
import Foundation

enum DebugLaunch {

    /// True when any development flag was passed on the command line.
    static var hasArguments: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-wlSection")
            || arguments.contains("-wlRoute")
            || arguments.contains("-wlRoot")
            || arguments.contains("-wlSheet")
    }

    /// Section named by `-wlSection <name>`, if any.
    static var section: AppSection? {
        guard let raw = value(for: "-wlSection") else { return nil }
        return AppSection(rawValue: raw)
    }

    /// Routes that need no lookup, so they can be applied before the document
    /// has even loaded.
    static var stateIndependentRoute: AppRoute? {
        guard let token = value(for: "-wlRoute") else { return nil }
        switch token {
        case "planner": return .planner
        case "laundry": return .laundry
        case "events": return .events
        case "repairs": return .repairs
        case "templates": return .templates
        case "settings": return .settings
        case "howItWorks": return .howItWorks
        case "wardrobeSetup": return .wardrobeSetup
        case "essentials": return .essentialsList
        case "categoryWeights": return .categoryWeights
        case "notifications": return .notificationSettings
        case "about": return .aboutApp
        case "pieceForm": return .pieceForm(pieceID: nil)
        case "outfitBuilder": return .outfitBuilder(outfitID: nil, prefillPieceID: nil)
        case "tripWizard": return .tripWizard(tripID: nil)
        case "eventNew": return .eventForm(eventID: nil)
        default:
            if token.hasPrefix("insight:") {
                return InsightKind(rawValue: String(token.dropFirst("insight:".count)))
                    .map { .insightDetail($0) }
            }
            return nil
        }
    }

    /// Route named by `-wlRoute <token>`, resolved against the given state.
    /// Tokens take a zero-based index into the matching array, e.g.
    /// `-wlRoute pieceDetails:0` or `-wlRoute tripWorkspace:0`.
    static func route(in state: AppState) -> AppRoute? {
        guard let token = value(for: "-wlRoute") else { return nil }
        return resolve(token: token, in: state)
    }

    private static func resolve(token: String, in state: AppState) -> AppRoute? {
        let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
        let name = parts[0]
        let index = parts.count > 1 ? Int(parts[1]) ?? 0 : 0

        func piece(_ i: Int) -> UUID? { state.pieces.indices.contains(i) ? state.pieces[i].id : nil }
        func outfit(_ i: Int) -> UUID? { state.outfits.indices.contains(i) ? state.outfits[i].id : nil }
        func trip(_ i: Int) -> UUID? { state.trips.indices.contains(i) ? state.trips[i].id : nil }
        func event(_ i: Int) -> UUID? { state.events.indices.contains(i) ? state.events[i].id : nil }

        switch name {
        case "planner": return .planner
        case "laundry": return .laundry
        case "events": return .events
        case "repairs": return .repairs
        case "templates": return .templates
        case "settings": return .settings
        case "howItWorks": return .howItWorks
        case "wardrobeSetup": return .wardrobeSetup
        case "essentials": return .essentialsList
        case "categoryWeights": return .categoryWeights
        case "notifications": return .notificationSettings
        case "about": return .aboutApp
        case "pieceForm": return .pieceForm(pieceID: nil)
        case "pieceEdit": return piece(index).map { .pieceForm(pieceID: $0) }
        case "pieceDetails": return piece(index).map { .pieceDetails($0) }
        case "outfitBuilder": return .outfitBuilder(outfitID: nil, prefillPieceID: nil)
        case "outfitEdit": return outfit(index).map { .outfitBuilder(outfitID: $0, prefillPieceID: nil) }
        case "outfitDetails": return outfit(index).map { .outfitDetails($0) }
        case "tripWizard": return .tripWizard(tripID: nil)
        case "tripEdit": return trip(index).map { .tripWizard(tripID: $0) }
        case "tripWorkspace": return trip(index).map { .tripWorkspace($0) }
        case "tripDayPlan": return trip(index).map { .tripDayPlan($0) }
        case "packingList": return trip(index).map { .packingList($0) }
        case "weightCheck": return trip(index).map { .weightCheck($0) }
        case "tripReadiness": return trip(index).map { .tripReadiness($0) }
        case "tripRecap": return trip(index).map { .tripRecap($0) }
        case "eventForm": return event(index).map { .eventForm(eventID: $0) }
        case "eventNew": return .eventForm(eventID: nil)
        case "insight":
            let kindRaw = parts.count > 1 ? parts[1] : InsightKind.mostWorn.rawValue
            return InsightKind(rawValue: kindRaw).map { .insightDetail($0) }
        default: return nil
        }
    }

    /// Screen named by `-wlRoot <token>`, rendered in place of the section.
    static func rootRoute(in state: AppState) -> AppRoute? {
        guard let token = value(for: "-wlRoot") else { return nil }
        return resolve(token: token, in: state)
    }

    /// Trip index named by `-wlSheet tripMode:<index>`.
    static func sheet(in state: AppState) -> AppSheet? {
        guard let token = value(for: "-wlSheet") else { return nil }
        let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts[0] == "tripMode" else { return nil }
        let index = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        guard state.trips.indices.contains(index) else { return nil }
        return .tripMode(state.trips[index].id)
    }

    private static func value(for flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let position = arguments.firstIndex(of: flag),
              arguments.indices.contains(position + 1) else { return nil }
        return arguments[position + 1]
    }
}
#endif
