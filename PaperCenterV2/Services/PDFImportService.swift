//
//  PDFImportService.swift
//  PaperCenterV2
//
//  Created by Claude on 2025-11-09.
//

import Foundation
import SwiftData
import PDFKit

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
        // Validate the source file
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw PDFImportError.sourceFileNotFound
        }

        // Validate it's a PDF
        guard sourceURL.pathExtension.lowercased() == "pdf" else {
            throw PDFImportError.invalidFileType
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

        // Remove existing file if present
        if fileManager.fileExists(atPath: targetURL.path) {
            try fileManager.removeItem(at: targetURL)
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
            Task.detached {
                await self.extractOCRText(for: targetBundle, at: targetURL)
            }
        }

        return targetBundle
    }

    // MARK: - OCR Text Extraction

    /// Extract OCR text from a PDF file
    /// - Parameters:
    ///   - bundle: PDFBundle to update with extracted text
    ///   - pdfURL: URL of the PDF file
    private func extractOCRText(for bundle: PDFBundle, at pdfURL: URL) async {
        guard let pdfDocument = PDFDocument(url: pdfURL) else {
            print("Error: Unable to load PDF document")
            return
        }

        var extractedText: [Int: String] = [:]

        // Extract text from each page
        for pageIndex in 0..<pdfDocument.pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else { continue }

            // PDFPage provides basic text extraction
            if let pageText = page.string {
                // Store with 1-based page number
                extractedText[pageIndex + 1] = pageText
            }
        }

        // Update the bundle on main actor
        await MainActor.run {
            bundle.ocrTextByPage = extractedText
            bundle.touch()
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
    case bundleInUse
    case copyFailed

    var errorDescription: String? {
        switch self {
        case .sourceFileNotFound:
            return "Source PDF file not found"
        case .invalidFileType:
            return "File is not a PDF"
        case .bundleInUse:
            return "Cannot delete bundle: still referenced by pages"
        case .copyFailed:
            return "Failed to copy PDF file to app storage"
        }
    }
}
