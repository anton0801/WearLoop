//
//  WeatherService.swift
//  WearLoop
//
//  Optional OpenWeatherMap lookup. The app is still fully usable with no key
//  and no network — fetching only ever replaces what you would otherwise type
//  in by hand, and every reading is attributed on screen.
//
//  Endpoints used (both on the free tier):
//    • /data/2.5/weather  — conditions right now
//    • /data/2.5/forecast — 3-hourly for the next five days
//

import Foundation

// MARK: - Result types

/// One reading, already converted into the app's own units.
struct FetchedWeather: Equatable {
    var temperatureC: Double
    var rain: Bool
    var windKph: Double?
    var locationName: String?

    /// Range across a whole day, used when setting up a trip.
    var minTemperatureC: Double?
    var maxTemperatureC: Double?

    func asInput() -> WeatherInput {
        WeatherInput(
            temperatureC: temperatureC,
            rain: rain,
            windKph: windKph,
            source: .openWeatherMap,
            locationName: locationName,
            fetchedAt: Date()
        )
    }
}

enum WeatherError: LocalizedError, Equatable {
    case missingKey
    case invalidKey
    case placeNotFound(String)
    case noLocation
    case offline
    case dateOutOfRange
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "No OpenWeatherMap key has been added yet, so weather can only be entered by hand."
        case .invalidKey:
            return "OpenWeatherMap rejected the key. A new key can take a couple of hours to become active."
        case .placeNotFound(let place):
            return "OpenWeatherMap does not know a place called \"\(place)\". Try a city name, or a city and country like \"Berlin, DE\"."
        case .noLocation:
            return "No place to look up. Set a city in Settings, or allow Wear Loop to use your location."
        case .offline:
            return "No network connection, so the weather could not be fetched. You can still enter it by hand."
        case .dateOutOfRange:
            return "The free forecast only reaches five days ahead. Enter this day's weather by hand."
        case .server(let detail):
            return "OpenWeatherMap could not be reached. \(detail)"
        }
    }
}

// MARK: - Contract

protocol WeatherServiceProtocol: AnyObject {
    var isConfigured: Bool { get }
    /// Conditions right now for a place.
    func current(for place: WeatherPlace) async throws -> FetchedWeather
    /// Conditions for one day, from the five-day forecast.
    func forecast(for place: WeatherPlace, on date: Date) async throws -> FetchedWeather
    /// Day-by-day range across a span, for setting up a trip.
    func forecastRange(for place: WeatherPlace, from start: Date, to end: Date) async throws -> FetchedWeather
}

/// Where to look the weather up.
enum WeatherPlace: Equatable {
    case coordinates(latitude: Double, longitude: Double)
    case city(String)

    var queryItems: [URLQueryItem] {
        switch self {
        case .coordinates(let latitude, let longitude):
            return [
                URLQueryItem(name: "lat", value: String(format: "%.4f", latitude)),
                URLQueryItem(name: "lon", value: String(format: "%.4f", longitude))
            ]
        case .city(let name):
            return [URLQueryItem(name: "q", value: name.trimmingCharacters(in: .whitespacesAndNewlines))]
        }
    }

    var describedName: String? {
        if case .city(let name) = self { return name }
        return nil
    }
}

// MARK: - Implementation

final class OpenWeatherMapService: WeatherServiceProtocol {

    private let session: URLSession
    private let host = "api.openweathermap.org"

    init(session: URLSession = .shared) {
        self.session = session
    }

    var isConfigured: Bool { WeatherAPIKey.isConfigured }

    // MARK: Current

    func current(for place: WeatherPlace) async throws -> FetchedWeather {
        let payload: CurrentPayload = try await get(path: "/data/2.5/weather", place: place)
        return FetchedWeather(
            temperatureC: payload.main.temp,
            rain: payload.isRaining,
            windKph: payload.wind.map { $0.speed * 3.6 },
            locationName: payload.name ?? place.describedName,
            minTemperatureC: payload.main.temp_min,
            maxTemperatureC: payload.main.temp_max
        )
    }

    // MARK: Forecast

    func forecast(for place: WeatherPlace, on date: Date) async throws -> FetchedWeather {
        let day = date.wlStartOfDay
        let today = Date().wlStartOfDay
        guard day >= today else { throw WeatherError.dateOutOfRange }
        if day == today { return try await current(for: place) }

        // The free forecast reaches five days out.
        guard Calendar.wl.dayCount(from: today, to: day) <= 5 else { throw WeatherError.dateOutOfRange }

        let payload: ForecastPayload = try await get(path: "/data/2.5/forecast", place: place)
        let slots = payload.list.filter { $0.date.wlStartOfDay == day }
        guard !slots.isEmpty else { throw WeatherError.dateOutOfRange }

        return summarise(slots: slots, name: payload.city?.name ?? place.describedName)
    }

    func forecastRange(for place: WeatherPlace, from start: Date, to end: Date) async throws -> FetchedWeather {
        let first = start.wlStartOfDay
        let last = end.wlStartOfDay
        let payload: ForecastPayload = try await get(path: "/data/2.5/forecast", place: place)

        let slots = payload.list.filter { slot in
            let day = slot.date.wlStartOfDay
            return day >= first && day <= last
        }
        guard !slots.isEmpty else { throw WeatherError.dateOutOfRange }
        return summarise(slots: slots, name: payload.city?.name ?? place.describedName)
    }

    /// Turns a set of three-hourly slots into one reading.
    private func summarise(slots: [ForecastPayload.Slot], name: String?) -> FetchedWeather {
        let temperatures = slots.map(\.main.temp)
        let lowest = temperatures.min() ?? 0
        let highest = temperatures.max() ?? 0
        // Daytime slots represent the day better than a 3am reading.
        let daytime = slots.filter { slot in
            let hour = Calendar.wl.component(.hour, from: slot.date)
            return hour >= 9 && hour <= 18
        }
        let representative = (daytime.isEmpty ? slots : daytime).map(\.main.temp)
        let average = representative.reduce(0, +) / Double(representative.count)

        return FetchedWeather(
            temperatureC: (average * 10).rounded() / 10,
            rain: slots.contains { $0.isRaining },
            windKph: slots.compactMap { $0.wind?.speed }.max().map { $0 * 3.6 },
            locationName: name,
            minTemperatureC: lowest.rounded(),
            maxTemperatureC: highest.rounded()
        )
    }

    // MARK: Transport

    private func get<T: Decodable>(path: String, place: WeatherPlace) async throws -> T {
        guard let key = WeatherAPIKey.value else { throw WeatherError.missingKey }

        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        components.queryItems = place.queryItems + [
            URLQueryItem(name: "units", value: "metric"),
            URLQueryItem(name: "appid", value: key)
        ]
        guard let url = components.url else { throw WeatherError.server("The request could not be built.") }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                throw WeatherError.offline
            case .timedOut:
                throw WeatherError.server("The request timed out.")
            default:
                throw WeatherError.server(error.localizedDescription)
            }
        } catch {
            throw WeatherError.server(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw WeatherError.server("The response could not be read.")
        }
        switch http.statusCode {
        case 200:
            break
        case 401:
            throw WeatherError.invalidKey
        case 404:
            throw WeatherError.placeNotFound(place.describedName ?? "that location")
        case 429:
            throw WeatherError.server("The key has hit its request limit for now.")
        default:
            throw WeatherError.server("The service replied with status \(http.statusCode).")
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw WeatherError.server("The reply could not be read.")
        }
    }
}

// MARK: - Payloads

private struct Temperatures: Decodable {
    let temp: Double
    let temp_min: Double?
    let temp_max: Double?
}

private struct Wind: Decodable {
    let speed: Double
}

private struct Condition: Decodable {
    let id: Int
}

/// Weather condition ids in the 2xx, 3xx, 5xx and 6xx groups mean something is
/// falling out of the sky.
private func hasPrecipitation(_ conditions: [Condition]?) -> Bool {
    guard let conditions else { return false }
    return conditions.contains { condition in
        let group = condition.id / 100
        return group == 2 || group == 3 || group == 5 || group == 6
    }
}

private struct CurrentPayload: Decodable {
    let main: Temperatures
    let wind: Wind?
    let weather: [Condition]?
    let name: String?

    var isRaining: Bool { hasPrecipitation(weather) }
}

private struct ForecastPayload: Decodable {
    struct City: Decodable { let name: String? }

    struct Slot: Decodable {
        let dt: TimeInterval
        let main: Temperatures
        let wind: Wind?
        let weather: [Condition]?

        var date: Date { Date(timeIntervalSince1970: dt) }
        var isRaining: Bool { hasPrecipitation(weather) }
    }

    let list: [Slot]
    let city: City?
}
