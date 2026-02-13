//
//  PDFImportService.swift
//  PaperCenterV2
//
//  Created by Claude on 2025-11-09.
//

import Foundation
import SwiftData
import PDFKit
import Vision
import CoreImage
import UIKit

/// Service for importing PDF files into the app sandbox and managing PDFBundles
@MainActor
final class PDFImportService {

    // MARK: - Properties

    private let modelContext: ModelContext
    private let fileManager = FileManager.default

    /// Base directory for storing PDF bundles
    private var pdfBundlesDirectory: URL {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsURL.appendingPathComponent("PDFBundles", isDirectory: true)
    }

    // MARK: - Initialization

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        ensureDirectoryExists()
    }

    // MARK: - Directory Management

    /// Ensure the PDFBundles directory exists
    private func ensureDirectoryExists() {
        do {
            try fileManager.createDirectory(
                at: pdfBundlesDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            print("Error creating PDFBundles directory: \(error)")
        }
    }

    /// Get the directory URL for a specific bundle
    private func bundleDirectory(for bundleID: UUID) -> URL {
        return pdfBundlesDirectory.appendingPathComponent(bundleID.uuidString, isDirectory: true)
    }

    // MARK: - PDF Import

    /// Import multiple PDF files as a complete bundle
    /// - Parameters:
    ///   - name: Bundle name
    ///   - displayPDF: Display PDF URL (required)
    ///   - ocrPDF: OCR PDF URL (optional)
    ///   - originalPDF: Original PDF URL (optional)
    /// - Returns: PDFBundle containing all imported files
    /// - Throws: Import errors
    func importPDFBundle(
        name: String,
        displayPDF: URL,
        ocrPDF: URL? = nil,
        originalPDF: URL? = nil,
        selectedDisplayPages: [Int]? = nil
    ) async throws -> PDFBundle {
        // Create new bundle with name
        let bundle = PDFBundle(name: name)
        modelContext.insert(bundle)

        var cleanupURLs: [URL] = []
        defer {
            cleanupURLs.forEach { try? fileManager.removeItem(at: $0) }
        }

        do {
            guard let displaySource = try filteredSourceURL(for: displayPDF, selectedPages: selectedDisplayPages, required: true) else {
                throw PDFImportError.noSelectedPages
            }
            if displaySource.isTemporary { cleanupURLs.append(displaySource.url) }

            // Import display PDF (required)
            let _ = try await importPDF(from: displaySource.url, type: .display, into: bundle)

            // Import original PDF if provided
            if let originalURL = originalPDF {
                if let originalSource = try filteredSourceURL(for: originalURL, selectedPages: selectedDisplayPages, required: false) {
                    if originalSource.isTemporary { cleanupURLs.append(originalSource.url) }
                    let _ = try await importPDF(from: originalSource.url, type: .original, into: bundle)
                }
            }

            // Import OCR PDF last so OCR background extraction only starts after other variants succeed.
            if let ocrURL = ocrPDF {
                if let ocrSource = try filteredSourceURL(for: ocrURL, selectedPages: selectedDisplayPages, required: false) {
                    if ocrSource.isTemporary { cleanupURLs.append(ocrSource.url) }
                    let _ = try await importPDF(from: ocrSource.url, type: .ocr, into: bundle)
                }
            }

            return bundle
        } catch {
            rollbackBundleImport(bundle)
            throw error
        }
    }

    /// Import a PDF file into a new or existing PDFBundle
    /// - Parameters:
    ///   - sourceURL: External URL of the PDF file
    ///   - type: PDF type (display, OCR, or original)
    ///   - bundle: Existing bundle to add to, or nil to create new
    /// - Returns: The PDFBundle with the imported file
    /// - Throws: Import errors
    func importPDF(
        from sourceURL: URL,
        type: PDFType,
        into bundle: PDFBundle? = nil
    ) async throws -> PDFBundle {
        // Validate it's a PDF by extension
        guard sourceURL.pathExtension.lowercased() == "pdf" else {
            throw PDFImportError.invalidFileType
        }

        // Access security-scoped resource (needed for file picker URLs)
        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        // Validate the source file (inside security scope)
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw PDFImportError.sourceFileNotFound
        }

        // Validate it's a readable PDF
        guard let _ = PDFDocument(url: sourceURL) else {
            throw PDFImportError.invalidPDF
        }

        // Get or create the bundle
        let targetBundle = bundle ?? PDFBundle()

        // Create bundle directory
        let bundleDir = bundleDirectory(for: targetBundle.id)
        try fileManager.createDirectory(at: bundleDir, withIntermediateDirectories: true, attributes: nil)

        // Determine target filename
        let targetFilename: String
        switch type {
        case .display:
            targetFilename = "display.pdf"
        case .ocr:
            targetFilename = "ocr.pdf"
        case .original:
            targetFilename = "original.pdf"
        }

        // Copy file to sandbox
        let targetURL = bundleDir.appendingPathComponent(targetFilename)

        // Never replace an existing variant on an existing bundle while the file still exists.
        // Replacing files would invalidate historical Page/PageVersion references.
        // If the recorded path exists but the file is missing, allow restoring that variant.
        if bundle != nil,
           targetBundle.path(for: type) != nil,
           let existingURL = targetBundle.fileURL(for: type),
           fileManager.fileExists(atPath: existingURL.path) {
            throw PDFImportError.bundleVariantAlreadyExists
        }

        // Remove existing file only for brand-new bundles.
        if fileManager.fileExists(atPath: targetURL.path) {
            if bundle == nil {
                try fileManager.removeItem(at: targetURL)
            } else {
                throw PDFImportError.bundleVariantAlreadyExists
            }
        }

        // Copy the file
        try fileManager.copyItem(at: sourceURL, to: targetURL)

        // Update bundle with relative path
        let relativePath = "PDFBundles/\(targetBundle.id.uuidString)/\(targetFilename)"
        targetBundle.setPath(relativePath, for: type)

        // If this is a new bundle, insert it into the context
        if bundle == nil {
            modelContext.insert(targetBundle)
        }

        // If OCR PDF, extract text in background
        if type == .ocr {
            let bundleID = targetBundle.id
            let useVisionOCR = OCRSettings.shared.isVisionOCREnabled
            let language = OCRSettings.shared.ocrLanguage
            let container = modelContext.container

            // Set initial status
            targetBundle.ocrExtractionStatus = "inProgress"
            targetBundle.ocrExtractionProgress = 0.0

            Task.detached {
                let backgroundContext = ModelContext(container)
                await Self.extractOCRText(
                    bundleID: bundleID,
                    pdfURL: targetURL,
                    modelContext: backgroundContext,
                    useVisionOCR: useVisionOCR,
                    language: language
                )
            }
        }

        return targetBundle
    }

    // MARK: - OCR Text Extraction

    /// Extract OCR text from a PDF file using Vision framework
    /// - Parameters:
    ///   - bundleID: ID of the bundle to update
    ///   - pdfURL: URL of the PDF file
    ///   - modelContext: Model context for database updates
    ///   - useVisionOCR: Whether to use Vision framework OCR for image-based pages
    ///   - language: OCR language to use
    private static func extractOCRText(
        bundleID: UUID,
        pdfURL: URL,
        modelContext: ModelContext,
        useVisionOCR: Bool,
        language: OCRLanguage
    ) async {
        guard let pdfDocument = PDFDocument(url: pdfURL) else {
            print("OCR Error: Unable to load PDF document at \(pdfURL)")
            await updateBundleStatus(bundleID: bundleID, modelContext: modelContext, status: "failed", progress: 0.0)
            return
        }

        var extractedText: [Int: String] = [:]
        let pageCount = pdfDocument.pageCount

        print("Starting OCR extraction for \(pageCount) pages (Vision OCR: \(useVisionOCR ? "enabled" : "disabled"))...")

        // Extract text from each page
        for pageIndex in 0..<pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else { continue }

            // First try: Extract embedded text (faster)
            if let embeddedText = page.string, !embeddedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                extractedText[pageIndex + 1] = embeddedText
            } else if useVisionOCR {
                // Second try: Use Vision framework for image-based OCR (only if enabled)
                // Render on main thread but do it async
                if let pageImage = await renderPageToImageOnMain(page) {
                    if let ocrText = await performVisionOCR(on: pageImage, language: language) {
                        extractedText[pageIndex + 1] = ocrText
                    }
                }
            }

            // Update progress only every 5 pages or at the end
            let shouldUpdateProgress = (pageIndex + 1) % 5 == 0 || pageIndex == pageCount - 1
            if shouldUpdateProgress {
                let progress = Double(pageIndex + 1) / Double(pageCount)
                await updateBundleProgress(bundleID: bundleID, modelContext: modelContext, progress: progress)
            }
        }

        print("OCR extraction complete: \(extractedText.count) pages with text")

        // Update the bundle with final results
        await MainActor.run {
            // Fetch the bundle and update it
            let descriptor = FetchDescriptor<PDFBundle>(
                predicate: #Predicate { bundle in
                    bundle.id == bundleID
                }
            )

            if let bundles = try? modelContext.fetch(descriptor),
               let bundle = bundles.first {
                bundle.ocrTextByPage = extractedText
                bundle.ocrExtractionStatus = "completed"
                bundle.ocrExtractionProgress = 1.0
                bundle.touch()

                // Save the context
                try? modelContext.save()
            }
        }
    }

    /// Update bundle OCR progress (without saving to reduce UI lag)
    private static func updateBundleProgress(
        bundleID: UUID,
        modelContext: ModelContext,
        progress: Double
    ) async {
        await MainActor.run {
            let descriptor = FetchDescriptor<PDFBundle>(
                predicate: #Predicate { bundle in
                    bundle.id == bundleID
                }
            )

            if let bundles = try? modelContext.fetch(descriptor),
               let bundle = bundles.first {
                bundle.ocrExtractionProgress = progress
                // Don't save immediately - reduces UI lag
                // Final save happens in extractOCRText when complete
            }
        }
    }

    /// Update bundle OCR status
    private static func updateBundleStatus(
        bundleID: UUID,
        modelContext: ModelContext,
        status: String,
        progress: Double
    ) async {
        await MainActor.run {
            let descriptor = FetchDescriptor<PDFBundle>(
                predicate: #Predicate { bundle in
                    bundle.id == bundleID
                }
            )

            if let bundles = try? modelContext.fetch(descriptor),
               let bundle = bundles.first {
                bundle.ocrExtractionStatus = status
                bundle.ocrExtractionProgress = progress
                try? modelContext.save()
            }
        }
    }

    /// Render a PDF page to an image for Vision OCR (optimized for speed)
    /// Runs on background thread to avoid blocking UI
    private static func renderPageToImageOnMain(_ page: PDFPage) async -> CIImage? {
        // PDFPage rendering is thread-safe, run on background thread
        return await Task.detached(priority: .userInitiated) {
            // Use thumbnail method which is faster than full rendering
            let pageRect = page.bounds(for: .mediaBox)
            // Use reasonable size for OCR - don't need full resolution
            let maxDimension: CGFloat = 2000
            let scale = min(1.0, maxDimension / max(pageRect.width, pageRect.height))
            let thumbnailSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)

            // PDFPage.thumbnail is optimized and faster
            let thumbnail = page.thumbnail(of: thumbnailSize, for: .mediaBox)
            return CIImage(image: thumbnail)
        }.value
    }

    /// Perform Vision framework OCR on an image
    /// Runs on background queue to avoid blocking UI
    private static func performVisionOCR(on image: CIImage, language: OCRLanguage) async -> String? {
        return await withCheckedContinuation { continuation in
            // Run Vision request on background queue
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest { request, error in
                    if let error = error {
                        print("Vision OCR error: \(error)")
                        continuation.resume(returning: nil)
                        return
                    }

                    guard let observations = request.results as? [VNRecognizedTextObservation] else {
                        continuation.resume(returning: nil)
                        return
                    }

                    let recognizedText = observations.compactMap { observation in
                        observation.topCandidates(1).first?.string
                    }.joined(separator: "\n")

                    continuation.resume(returning: recognizedText.isEmpty ? nil : recognizedText)
                }

                // Configure for accurate text recognition
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true

                // Set recognition languages based on selected language
                request.recognitionLanguages = [language.rawValue]

                let handler = VNImageRequestHandler(ciImage: image, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    print("Failed to perform Vision request: \(error)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Bundle Deletion

    /// Delete a PDFBundle and its associated files
    /// - Parameter bundle: Bundle to delete
    /// - Throws: Deletion errors
    func deleteBundle(_ bundle: PDFBundle) throws {
        // Check if bundle can be deleted
        guard bundle.canDelete else {
            throw PDFImportError.bundleInUse
        }

        // Delete physical files
        let bundleDir = bundleDirectory(for: bundle.id)
        if fileManager.fileExists(atPath: bundleDir.path) {
            try fileManager.removeItem(at: bundleDir)
        }

        // Delete from context
        modelContext.delete(bundle)
    }

    // MARK: - File Access

    /// Get the file URL for a specific PDF type in a bundle
    /// - Parameters:
    ///   - type: PDF type
    ///   - bundle: PDFBundle to get file from
    /// - Returns: Full file URL, or nil if not set
    func fileURL(for type: PDFType, in bundle: PDFBundle) -> URL? {
        return bundle.fileURL(for: type)
    }

    /// Check if a PDF file exists for a specific type
    /// - Parameters:
    ///   - type: PDF type
    ///   - bundle: PDFBundle to check
    /// - Returns: True if file exists
    func fileExists(for type: PDFType, in bundle: PDFBundle) -> Bool {
        guard let url = bundle.fileURL(for: type) else { return false }
        return fileManager.fileExists(atPath: url.path)
    }
}

// MARK: - Errors

enum PDFImportError: LocalizedError {
    case sourceFileNotFound
    case invalidFileType
    case invalidPDF
    case bundleInUse
    case bundleVariantAlreadyExists
    case copyFailed
    case noSelectedPages

    var errorDescription: String? {
        switch self {
        case .sourceFileNotFound:
            return "Source PDF file not found"
        case .invalidFileType:
            return "File is not a PDF"
        case .invalidPDF:
            return "PDF file is corrupted or unreadable"
        case .bundleInUse:
            return "Cannot delete bundle: still referenced by pages"
        case .bundleVariantAlreadyExists:
            return "This PDF type already exists in the bundle. Replacing existing files is blocked to protect historical references."
        case .copyFailed:
            return "Failed to copy PDF file to app storage"
        case .noSelectedPages:
            return "No pages available for the selected filters"
        }
    }
}

private extension PDFImportService {
    typealias FilteredSource = (url: URL, isTemporary: Bool)

    func filteredSourceURL(
        for url: URL,
        selectedPages: [Int]?,
        required: Bool
    ) throws -> FilteredSource? {
        guard let selectedPages, !selectedPages.isEmpty else {
            return (url, false)
        }

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let subsetURL = try subsetPDF(at: url, keeping: selectedPages)

        if let subsetURL {
            let isTemporary = subsetURL.standardizedFileURL != url.standardizedFileURL
            return (subsetURL, isTemporary)
        }

        if required {
            throw PDFImportError.noSelectedPages
        } else {
            return nil
        }
    }

    func subsetPDF(at url: URL, keeping pages: [Int]) throws -> URL? {
        let uniquePages = Array(Set(pages)).sorted()
        guard let document = PDFDocument(url: url) else {
            throw PDFImportError.invalidPDF
        }

        guard document.pageCount > 0 else {
            return nil
        }

        var extractedPages: [PDFPage] = []
        for pageNumber in uniquePages {
            let zeroIndex = pageNumber - 1
            guard zeroIndex >= 0, zeroIndex < document.pageCount,
                  let page = document.page(at: zeroIndex) else { continue }
            extractedPages.append(page)
        }

        guard !extractedPages.isEmpty else {
            return nil
        }

        // Selecting the full range should reuse the original file to avoid unnecessary rewrites.
        if extractedPages.count == document.pageCount,
           uniquePages.first == 1,
           uniquePages.last == document.pageCount {
            return url
        }

        let newDocument = PDFDocument()
        for (index, page) in extractedPages.enumerated() {
            newDocument.insert(page, at: index)
        }

        let tempURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")

        guard newDocument.write(to: tempURL) else {
            throw PDFImportError.copyFailed
        }

        return tempURL
    }

    func rollbackBundleImport(_ bundle: PDFBundle) {
        let bundleDir = bundleDirectory(for: bundle.id)
        if fileManager.fileExists(atPath: bundleDir.path) {
            try? fileManager.removeItem(at: bundleDir)
        }
        modelContext.delete(bundle)
    }
}
