//
//  PhotoStore.swift
//  WearLoop
//
//  Garment photographs on disk. Images are stored as they were taken and are
//  never tinted, darkened or recoloured anywhere in the app — the colour of a
//  garment is data, not decoration.
//

import UIKit

protocol PhotoStoreProtocol: AnyObject {
    /// Stores an image and returns its identifier.
    func save(_ image: UIImage) throws -> String
    func image(for id: String) -> UIImage?
    func delete(_ id: String)
    /// Removes photos no longer referenced by any record. Only ever called from
    /// an explicit, confirmed action — never automatically, because a document
    /// that was partly recovered would otherwise lose its images for good.
    func pruneOrphans(keeping referencedIDs: Set<String>) -> Int
    /// How many stored photos nothing refers to any more.
    func orphanCount(keeping referencedIDs: Set<String>) -> Int
    func deleteAll()
}

final class PhotoStore: PhotoStoreProtocol {
    private let fileManager = FileManager.default
    private let cache = NSCache<NSString, UIImage>()
    private let ioQueue = DispatchQueue(label: "wearloop.photostore", qos: .userInitiated)

    /// Longest edge kept on disk. Cards are small; full-resolution originals
    /// would waste space without looking any better.
    private let maxDimension: CGFloat = 1400
    private let compressionQuality: CGFloat = 0.82

    init() {
        cache.countLimit = 120
        createDirectoryIfNeeded()
    }

    private var directoryURL: URL {
        let base = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Photos", isDirectory: true)
    }

    private func createDirectoryIfNeeded() {
        guard !fileManager.fileExists(atPath: directoryURL.path) else { return }
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    /// Identifiers are generated as UUIDs. Anything else is refused rather than
    /// turned into a path: a photo identifier arriving in an imported backup is
    /// untrusted input, and "../.." in one would otherwise let a crafted file
    /// read or delete images outside this folder.
    private func sanitised(_ id: String) -> String? {
        guard !id.isEmpty, id.count <= 64 else { return nil }
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        guard id.allSatisfy({ allowed.contains($0) }) else { return nil }
        return id
    }

    private func url(for id: String) -> URL? {
        guard let safe = sanitised(id) else { return nil }
        return directoryURL.appendingPathComponent(safe).appendingPathExtension("jpg")
    }

    // MARK: - Save

    func save(_ image: UIImage) throws -> String {
        createDirectoryIfNeeded()
        let resized = image.wlResized(maxDimension: maxDimension)
        guard let data = resized.jpegData(compressionQuality: compressionQuality) else {
            throw PersistenceError.writeFailed("The photo could not be prepared.")
        }
        let id = UUID().uuidString
        guard let destination = url(for: id) else {
            throw PersistenceError.writeFailed("The photo could not be stored.")
        }
        do {
            try data.write(to: destination, options: .atomic)
        } catch {
            throw PersistenceError.writeFailed(error.localizedDescription)
        }
        cache.setObject(resized, forKey: id as NSString)
        return id
    }

    // MARK: - Read

    func image(for id: String) -> UIImage? {
        if let cached = cache.object(forKey: id as NSString) { return cached }
        guard let location = url(for: id),
              let image = UIImage(contentsOfFile: location.path) else { return nil }
        cache.setObject(image, forKey: id as NSString)
        return image
    }

    // MARK: - Delete

    func delete(_ id: String) {
        cache.removeObject(forKey: id as NSString)
        guard let target = url(for: id) else { return }
        ioQueue.async { [fileManager] in
            try? fileManager.removeItem(at: target)
        }
    }

    @discardableResult
    func pruneOrphans(keeping referencedIDs: Set<String>) -> Int {
        let orphans = orphanURLs(keeping: referencedIDs)
        for file in orphans {
            cache.removeObject(forKey: file.deletingPathExtension().lastPathComponent as NSString)
            try? fileManager.removeItem(at: file)
        }
        return orphans.count
    }

    func orphanCount(keeping referencedIDs: Set<String>) -> Int {
        orphanURLs(keeping: referencedIDs).count
    }

    private func orphanURLs(keeping referencedIDs: Set<String>) -> [URL] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return files.filter { file in
            file.pathExtension == "jpg"
                && !referencedIDs.contains(file.deletingPathExtension().lastPathComponent)
        }
    }

    func deleteAll() {
        cache.removeAllObjects()
        let directory = directoryURL
        ioQueue.sync { [fileManager] in
            try? fileManager.removeItem(at: directory)
        }
        createDirectoryIfNeeded()
    }
}

// MARK: - Image helpers

extension UIImage {
    /// Scales the image down so its longest edge is at most `maxDimension`,
    /// preserving aspect ratio and orientation. Never upscales.
    func wlResized(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else {
            return wlOrientationNormalised()
        }
        let scale = maxDimension / longest
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// Bakes in the EXIF orientation so drawing is predictable later.
    private func wlOrientationNormalised() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
