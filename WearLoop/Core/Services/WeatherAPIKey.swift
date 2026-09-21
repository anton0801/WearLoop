//
//  WeatherAPIKey.swift
//  WearLoop
//
//  ────────────────────────────────────────────────────────────────────────────
//  PUT YOUR OPENWEATHERMAP API KEY HERE
//
//  1. Sign in at https://home.openweathermap.org/api_keys
//  2. Copy the key and paste it between the quotation marks below.
//  3. Build and run. Nothing else needs changing.
//
//  A new key can take up to a couple of hours to become active on
//  OpenWeatherMap's side. Until a key is set, the app simply keeps using
//  hand-entered weather and says so — nothing breaks.
//  ────────────────────────────────────────────────────────────────────────────
//

import Foundation

enum WeatherAPIKey {

    private static let hardcoded = "2255aeb9e4f7e3edc0195b0627ba2ff6"

    static var value: String? {
        let trimmed = hardcoded.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }

        if let fromPlist = Bundle.main.object(forInfoDictionaryKey: "OpenWeatherMapAPIKey") as? String {
            let cleaned = fromPlist.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty, !cleaned.hasPrefix("$(") { return cleaned }
        }
        return nil
    }

    static var isConfigured: Bool { value != nil }
}
