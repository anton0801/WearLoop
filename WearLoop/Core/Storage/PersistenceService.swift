//
//  PersistenceService.swift
//  WearLoop
//
//  Local JSON document store. No account, no network.
//

import Foundation

enum PersistenceError: LocalizedError {
    case readFailed(String)
    case writeFailed(String)
    case decodeFailed(String)
    case incompatibleBackup(Int)

    var errorDescription: String? {
        switch self {
        case .readFailed(let detail): return "Could not read your wardrobe. \(detail)"
        case .writeFailed(let detail): return "Could not save your changes. \(detail)"
        case .decodeFailed(let detail): return "Your saved data could not be read. \(detail)"
        case .incompatibleBackup(let version):
            return "This backup was made by a newer version of Wear Loop (format \(version))."
        }
    }
}

protocol PersistenceServiceProtocol: AnyObject {
    func load() throws -> AppState
    func save(_ state: AppState) throws
    func encode(_ state: AppState) throws -> Data
    func decode(_ data: Data) throws -> AppState
    func wipeEverything() throws
    /// Moves an unreadable document aside and returns where it was put, so the
    /// user can start again without anything being destroyed.
    func setAsideUnreadableDocument() throws -> URL
    var documentURL: URL { get }
}

final class PersistenceService: PersistenceServiceProtocol {
    private let fileName: String
    private let fileManager = FileManager.default

    init(fileName: String = "wearloop-state.json") {
        self.fileName = fileName
    }

    private var directoryURL: URL {
        let urls = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        return urls.first ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }

    var documentURL: URL { directoryURL.appendingPathComponent(fileName) }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: - Load

    func load() throws -> AppState {
        guard fileManager.fileExists(atPath: documentURL.path) else {
            // First launch: a clean document, no demo content.
            return AppState()
        }
        let data: Data
        do {
            data = try Data(contentsOf: documentURL)
        } catch {
            throw PersistenceError.readFailed(error.localizedDescription)
        }
        guard !data.isEmpty else { return AppState() }
        return try decode(data)
    }

    /// A hand-picked backup is untrusted input. This is far larger than any
    /// real wardrobe document and only exists to stop a hostile or corrupt file
    /// exhausting memory while being decoded.
    static let maximumDocumentBytes = 64 * 1024 * 1024

    func decode(_ data: Data) throws -> AppState {
        guard data.count <= PersistenceService.maximumDocumentBytes else {
            throw PersistenceError.decodeFailed("The file is too large to be a Wear Loop backup.")
        }
        do {
            let state = try decoder.decode(AppState.self, from: data)
            guard state.schemaVersion <= AppState.currentSchemaVersion else {
                throw PersistenceError.incompatibleBackup(state.schemaVersion)
            }
            return state
        } catch let error as PersistenceError {
            throw error
        } catch {
            throw PersistenceError.decodeFailed(error.localizedDescription)
        }
    }

    // MARK: - Save

    func encode(_ state: AppState) throws -> Data {
        do {
            return try encoder.encode(state)
        } catch {
            throw PersistenceError.writeFailed(error.localizedDescription)
        }
    }

    /// Writes through a temporary file so a crash mid-write cannot corrupt the document.
    func save(_ state: AppState) throws {
        let data = try encode(state)
        let tempURL = documentURL.appendingPathExtension("tmp")
        do {
            try data.write(to: tempURL, options: .atomic)
            if fileManager.fileExists(atPath: documentURL.path) {
                _ = try fileManager.replaceItemAt(documentURL, withItemAt: tempURL)
            } else {
                try fileManager.moveItem(at: tempURL, to: documentURL)
            }
        } catch {
            try? fileManager.removeItem(at: tempURL)
            throw PersistenceError.writeFailed(error.localizedDescription)
        }
    }

    func setAsideUnreadableDocument() throws -> URL {
        let stamp = DateFormatterCache.fileStamp.string(from: Date())
        let target = directoryURL.appendingPathComponent("wearloop-unreadable-\(stamp).json")
        do {
            if fileManager.fileExists(atPath: documentURL.path) {
                try fileManager.moveItem(at: documentURL, to: target)
            }
        } catch {
            throw PersistenceError.writeFailed(error.localizedDescription)
        }
        return target
    }

    func wipeEverything() throws {
        if fileManager.fileExists(atPath: documentURL.path) {
            do {
                try fileManager.removeItem(at: documentURL)
            } catch {
                throw PersistenceError.writeFailed(error.localizedDescription)
            }
        }
    }
}
