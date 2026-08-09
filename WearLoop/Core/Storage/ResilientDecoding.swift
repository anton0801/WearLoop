//
//  ResilientDecoding.swift
//  WearLoop
//
//  Swift's synthesised Decodable ignores default values: one missing key makes
//  the whole document fail to load. For an app whose only copy of the data is
//  this file, that would mean losing everything the moment the format grows.
//
//  Every persisted type therefore decodes leniently — a missing or malformed
//  field falls back to its default, and one unreadable record is skipped rather
//  than taking the rest of the wardrobe down with it.
//

import Foundation

// MARK: - Helpers

extension KeyedDecodingContainer {
    /// Decodes a value, falling back when the key is missing or unreadable.
    /// `try?` flattens the nested optional, so a nil here covers both cases.
    func wl<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        guard let value = try? decodeIfPresent(T.self, forKey: key) else { return fallback }
        return value
    }

    /// Decodes an optional value, treating a malformed one as absent.
    func wlOptional<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        guard let value = try? decodeIfPresent(T.self, forKey: key) else { return nil }
        return value
    }

    /// Decodes a name, falling back when the key is missing *or* holds nothing
    /// but whitespace. A blank name would render as a card with no label.
    func wlName(_ key: Key, _ fallback: String) -> String {
        let decoded = wl(key, "")
        return decoded.wlIsBlank ? fallback : decoded
    }

    /// Decodes an array, dropping only the elements that cannot be read at all.
    func wlArray<T: Decodable>(_ type: T.Type, _ key: Key) -> [T] {
        // The fast path: the whole array is well formed.
        if let whole = try? decodeIfPresent([T].self, forKey: key) {
            return whole
        }
        // Otherwise salvage element by element.
        guard var nested = try? nestedUnkeyedContainer(forKey: key) else { return [] }
        var result: [T] = []
        while !nested.isAtEnd {
            if let element = try? nested.decode(T.self) {
                result.append(element)
            } else if (try? nested.decode(AnySkipped.self)) == nil {
                // The element cannot even be stepped over; stop rather than loop.
                break
            }
        }
        return result
    }
}

/// Consumes one value of unknown shape so a bad element can be skipped.
private struct AnySkipped: Decodable {
    init(from decoder: Decoder) throws {
        _ = try? decoder.singleValueContainer()
    }
}
