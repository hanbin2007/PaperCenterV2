//
//  PDFBundleListViewModel.swift
//  PaperCenterV2
//
//  Created by Claude on 2025-11-09.
//

import Foundation
import SwiftData
import PDFKit

/// ViewModel for managing the PDFBundle list
@MainActor
@Observable
final class PDFBundleListViewModel {

    // MARK: - Properties

    private let modelContext: ModelContext
    private let importService: PDFImportService

    // MARK: - Initialization

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.importService = PDFImportService(modelContext: modelContext)
    }

    // MARK: - Bundle Management

    func addPDF(from url: URL, type: PDFType, to bundle: PDFBundle) async throws {
        _ = try await importService.importPDF(from: url, type: type, into: bundle)
        try modelContext.save()
    }

    /// Delete a PDFBundle if it's safe to do so
    /// - Parameter bundle: Bundle to delete
    /// - Throws: Deletion errors
    func deleteBundle(_ bundle: PDFBundle) throws {
        try importService.deleteBundle(bundle)
    }

    /// Check if a bundle can be safely deleted
    /// - Parameter bundle: Bundle to check
    /// - Returns: True if bundle has no references
    func canDelete(_ bundle: PDFBundle) -> Bool {
        return bundle.canDelete
    }

    /// Get formatted info for displaying a bundle
    /// - Parameter bundle: Bundle to format
    /// - Returns: Formatted bundle info
    func formatBundleInfo(_ bundle: PDFBundle) -> BundleDisplayInfo {
        let hasDisplay = bundle.displayPDFPath != nil
        let hasOCR = bundle.ocrPDFPath != nil
        let hasOriginal = bundle.originalPDFPath != nil

        // Get page count from display PDF if available
        var pageCount = 0
        if let displayURL = bundle.fileURL(for: .display),
           let pdfDocument = PDFKit.PDFDocument(url: displayURL) {
            pageCount = pdfDocument.pageCount
        }

        let referenceCount = bundle.referencingPages?.count ?? 0

        return BundleDisplayInfo(
            hasDisplay: hasDisplay,
            hasOCR: hasOCR,
            hasOriginal: hasOriginal,
            pageCount: pageCount,
            referenceCount: referenceCount,
            createdAt: bundle.createdAt
        )
    }
}

// MARK: - Supporting Types

/// Display information for a PDFBundle
struct BundleDisplayInfo {
    let hasDisplay: Bool
    let hasOCR: Bool
    let hasOriginal: Bool
    let pageCount: Int
    let referenceCount: Int
    let createdAt: Date
}
