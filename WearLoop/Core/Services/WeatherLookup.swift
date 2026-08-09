//
//  WeatherLookup.swift
//  WearLoop
//
//  The one place that decides where to look weather up, so Home, the planner,
//  events and trips all behave identically and report the same messages.
//

import Foundation

/// What a fetch produced, ready to show.
enum WeatherLookupOutcome: Equatable {
    case fetched(WeatherInput)
    case failed(String)

    var input: WeatherInput? {
        if case .fetched(let input) = self { return input }
        return nil
    }

    var message: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

/// Shared by every interactor that offers a fetch button.
struct WeatherLookup {
    let service: WeatherServiceProtocol
    let location: LocationProviderProtocol
    let settings: WeatherSettings

    var isAvailable: Bool { service.isConfigured }

    /// Why fetching cannot be offered yet, if it cannot.
    var unavailableReason: String? {
        if !service.isConfigured { return WeatherError.missingKey.errorDescription }
        if !settings.hasPlace { return WeatherError.noLocation.errorDescription }
        return nil
    }

    /// Conditions for one date: now if it is today, otherwise the forecast.
    func weather(on date: Date) async -> WeatherLookupOutcome {
        await run { place in
            try await service.forecast(for: place, on: date)
        }
    }

    /// A single range across a span of days, for trip conditions.
    func range(from start: Date, to end: Date) async -> WeatherLookupOutcome {
        await run { place in
            try await service.forecastRange(for: place, from: start, to: end)
        }
    }

    // MARK: - Plumbing

    private func run(_ work: (WeatherPlace) async throws -> FetchedWeather) async -> WeatherLookupOutcome {
        guard service.isConfigured else {
            return .failed(WeatherError.missingKey.errorDescription ?? "No key.")
        }
        do {
            let place = try await resolvePlace()
            let fetched = try await work(place)
            return .fetched(fetched.asInput())
        } catch let error as WeatherError {
            return .failed(error.errorDescription ?? "The weather could not be fetched.")
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// The device's own position when allowed, otherwise the saved city.
    private func resolvePlace() async throws -> WeatherPlace {
        let city = settings.cityName.wlTrimmed

        if settings.useDeviceLocation, !location.isDenied {
            if let coordinate = try? await location.currentCoordinate() {
                return .coordinates(latitude: coordinate.latitude, longitude: coordinate.longitude)
            }
            // Fall through to the city rather than failing outright.
        }

        guard !city.isEmpty else { throw WeatherError.noLocation }
        return .city(city)
    }
}

/// A range fetch also carries the day's low and high, which the trip wizard uses.
extension WeatherServiceProtocol {
    func rangeBounds(for place: WeatherPlace, from start: Date, to end: Date) async throws -> (min: Double, max: Double) {
        let fetched = try await forecastRange(for: place, from: start, to: end)
        return (
            fetched.minTemperatureC ?? fetched.temperatureC - 3,
            fetched.maxTemperatureC ?? fetched.temperatureC + 3
        )
    }
}
