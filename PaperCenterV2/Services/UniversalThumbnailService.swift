//
//  UniversalThumbnailService.swift
//  PaperCenterV2
//
//  Created by zhb on 2025-11-09.
//

import Foundation
import PDFKit
import UIKit

/// Error cases for thumbnail generation
enum ThumbnailError: Error {
    case missingBundleReference
    case missingPDFFile
    case invalidPageNumber
    case renderingFailed
}

/// Descriptor returned by UniversalThumbnailService
struct ThumbnailDescriptor: Identifiable {
    enum Source {
        case page(UUID)
        case doc(UUID)
        case bundle(UUID)
    }

    let id: UUID
    let source: Source
    let pageNumber: Int
    let image: UIImage
}

/// Service responsible for generating and caching thumbnails across Docs/Pages/PDFBundles
actor UniversalThumbnailService {

    // MARK: - Properties

    static let shared = UniversalThumbnailService()

    private let fileManager = FileManager.default
    private let memoryCache = NSCache<NSString, UIImage>()
    private var inFlightTasks: [String: Task<UIImage, Error>] = [:]

    private let thumbnailsDirectory: URL
    private let maxDiskBytes: Int64 = 50_000_000 // ~50 MB cap

    // MARK: - Initialization

    init() {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        thumbnailsDirectory = documentsURL.appendingPathComponent("Thumbnails", isDirectory: true)
        if !fileManager.fileExists(atPath: thumbnailsDirectory.path) {
            try? fileManager.createDirectory(
                at: thumbnailsDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }

    // MARK: - Public API

    func thumbnail(
        for page: Page,
        size: CGSize,
        scale: CGFloat = UIScreen.main.scale
    ) async throws -> ThumbnailDescriptor {
        guard let bundle = page.pdfBundle else {
            throw ThumbnailError.missingBundleReference
        }

        let image = try await renderThumbnail(
            identifier: page.id,
            bundle: bundle,
            pageNumber: page.currentPageNumber,
            size: size,
            scale: scale,
            variant: "page"
        )

        return ThumbnailDescriptor(
            id: page.id,
            source: .page(page.id),
            pageNumber: page.currentPageNumber,
            image: image
        )
    }

    func thumbnails(
        for doc: Doc,
        limit: Int? = nil,
        size: CGSize,
        scale: CGFloat = UIScreen.main.scale
    ) async throws -> [ThumbnailDescriptor] {
        let pages = doc.allPages
        let limitedPages: [Page]
        if let limit = limit {
            limitedPages = Array(pages.prefix(limit))
        } else {
            limitedPages = pages
        }

        var results: [ThumbnailDescriptor] = []
        for page in limitedPages {
            let descriptor = try await thumbnail(for: page, size: size, scale: scale)
            results.append(
                ThumbnailDescriptor(
                    id: page.id,
                    source: .doc(doc.id),
                    pageNumber: descriptor.pageNumber,
                    image: descriptor.image
                )
            )
        }
        return results
    }

    func thumbnail(
        for bundle: PDFBundle,
        page pageNumber: Int,
        size: CGSize,
        scale: CGFloat = UIScreen.main.scale
    ) async throws -> ThumbnailDescriptor {
        let image = try await renderThumbnail(
            identifier: bundle.id,
            bundle: bundle,
            pageNumber: pageNumber,
            size: size,
            scale: scale,
            variant: "bundle"
        )

        return ThumbnailDescriptor(
            id: UUID(),
            source: .bundle(bundle.id),
            pageNumber: pageNumber,
            image: image
        )
    }

    func purgeThumbnails(for bundleID: UUID) {
        let bundleDirectory = thumbnailsDirectory.appendingPathComponent(bundleID.uuidString, isDirectory: true)
        try? fileManager.removeItem(at: bundleDirectory)
    }

    // MARK: - Rendering

    private func renderThumbnail(
        identifier: UUID,
        bundle: PDFBundle,
        pageNumber: Int,
        size: CGSize,
        scale: CGFloat,
        variant: String
    ) async throws -> UIImage {
        guard pageNumber > 0 else {
            throw ThumbnailError.invalidPageNumber
        }

        let cacheKey = makeCacheKey(
            id: identifier,
            pageNumber: pageNumber,
            size: size,
            scale: scale,
            variant: variant
        )

        if let cached = memoryCache.object(forKey: cacheKey as NSString) {
            return cached
        }

        if let diskImage = loadFromDisk(bundleID: bundle.id, key: cacheKey) {
            memoryCache.setObject(diskImage, forKey: cacheKey as NSString)
            return diskImage
        }

        if let task = inFlightTasks[cacheKey] {
            return try await task.value
        }

        let task = Task<UIImage, Error> {
            guard let documentURL = bundlePreferredURL(bundle) else {
                throw ThumbnailError.missingPDFFile
            }

            guard let document = PDFDocument(url: documentURL) else {
                throw ThumbnailError.missingPDFFile
            }

            guard let page = document.page(at: pageNumber - 1) else {
                throw ThumbnailError.invalidPageNumber
            }

            let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
            guard let rendered = page.thumbnail(of: targetSize, for: .mediaBox).normalized(scale: scale) else {
                throw ThumbnailError.renderingFailed
            }

            try saveToDisk(rendered, bundleID: bundle.id, key: cacheKey)
            memoryCache.setObject(rendered, forKey: cacheKey as NSString)
            return rendered
        }

        inFlightTasks[cacheKey] = task

        defer { inFlightTasks[cacheKey] = nil }

        return try await task.value
    }

    // MARK: - Helpers

    private func bundlePreferredURL(_ bundle: PDFBundle) -> URL? {
        if let displayURL = bundle.fileURL(for: .display) {
            return displayURL
        }
        if let originalURL = bundle.fileURL(for: .original) {
            return originalURL
        }
        return bundle.fileURL(for: .ocr)
    }

    private func makeCacheKey(
        id: UUID,
        pageNumber: Int,
        size: CGSize,
        scale: CGFloat,
        variant: String
    ) -> String {
        return "\(variant)-\(id.uuidString)-p\(pageNumber)-\(Int(size.width))x\(Int(size.height))@\(String(format: "%.1f", scale))"
    }

    private func cacheDirectory(for bundleID: UUID) -> URL {
        let directory = thumbnailsDirectory.appendingPathComponent(bundleID.uuidString, isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }
        return directory
    }

    private func loadFromDisk(bundleID: UUID, key: String) -> UIImage? {
        let fileURL = cacheDirectory(for: bundleID).appendingPathComponent("\(key).png")
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else {
            return nil
        }
        return image
    }

    private func saveToDisk(_ image: UIImage, bundleID: UUID, key: String) throws {
        let fileURL = cacheDirectory(for: bundleID).appendingPathComponent("\(key).png")
        guard let data = image.pngData() else { return }
        try data.write(to: fileURL, options: .atomic)
        enforceDiskLimitIfNeeded()
    }

    private func enforceDiskLimitIfNeeded() {
        guard let enumerator = fileManager.enumerator(
            at: thumbnailsDirectory,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
            options: .skipsHiddenFiles
        ) else {
            return
        }

        var files: [(url: URL, size: Int64, date: Date)] = []
        var totalSize: Int64 = 0

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "png" else { continue }
            let resource = try? fileURL.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
            let size = Int64(resource?.fileSize ?? 0)
            let date = resource?.creationDate ?? Date()
            files.append((fileURL, size, date))
            totalSize += size
        }

        guard totalSize > maxDiskBytes else { return }

        let sorted = files.sorted { $0.date < $1.date }
        var currentSize = totalSize

        for file in sorted {
            try? fileManager.removeItem(at: file.url)
            currentSize -= file.size
            if currentSize <= maxDiskBytes {
                break
            }
        }
    }
}

// MARK: - UIImage helpers

private extension UIImage {
    func normalized(scale: CGFloat) -> UIImage? {
        if imageOrientation == .up && self.scale == scale {
            return self
        }

        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}
