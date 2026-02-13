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
    private let fileManager = FileManager.default

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
        let displayVariant = variantInfo(for: .display, in: bundle)
        let ocrVariant = variantInfo(for: .ocr, in: bundle)
        let originalVariant = variantInfo(for: .original, in: bundle)
        let pageCount = resolvePageCount(for: bundle)

        let referenceCount = bundle.referencingPages?.count ?? 0

        return BundleDisplayInfo(
            displayVariant: displayVariant,
            ocrVariant: ocrVariant,
            originalVariant: originalVariant,
            pageCount: pageCount,
            referenceCount: referenceCount,
            createdAt: bundle.createdAt
        )
    }

    private func variantInfo(for type: PDFType, in bundle: PDFBundle) -> BundleVariantInfo {
        guard let path = bundle.path(for: type), !path.isEmpty else {
            return BundleVariantInfo(type: type, status: .missing)
        }

        guard let url = bundle.fileURL(for: type), fileManager.fileExists(atPath: url.path) else {
            return BundleVariantInfo(type: type, status: .fileMissing)
        }

        return BundleVariantInfo(type: type, status: .available)
    }

    private func resolvePageCount(for bundle: PDFBundle) -> Int {
        for type in PDFType.pageCountPriority {
            guard let url = bundle.fileURL(for: type),
                  let document = PDFDocument(url: url) else {
                continue
            }
            return document.pageCount
        }
        return 0
    }
}

// MARK: - Supporting Types

/// Display information for a PDFBundle
struct BundleDisplayInfo {
    let displayVariant: BundleVariantInfo
    let ocrVariant: BundleVariantInfo
    let originalVariant: BundleVariantInfo
    let pageCount: Int
    let referenceCount: Int
    let createdAt: Date

    var variants: [BundleVariantInfo] {
        [displayVariant, ocrVariant, originalVariant]
    }

    var missingVariants: [BundleVariantInfo] {
        variants.filter(\.status.requiresSupplement)
    }

    var missingTypes: [PDFType] {
        missingVariants.map(\.type)
    }

    var missingCount: Int {
        missingVariants.count
    }

    var availableCount: Int {
        variants.filter { $0.status == .available }.count
    }

    var completionRatio: Double {
        guard !variants.isEmpty else { return 0.0 }
        return Double(availableCount) / Double(variants.count)
    }

    var hasDisplay: Bool {
        displayVariant.status == .available
    }

    var hasOCR: Bool {
        ocrVariant.status == .available
    }

    var hasOriginal: Bool {
        originalVariant.status == .available
    }

    var isComplete: Bool {
        missingCount == 0
    }

    static var placeholder: BundleDisplayInfo {
        BundleDisplayInfo(
            displayVariant: BundleVariantInfo(type: .display, status: .missing),
            ocrVariant: BundleVariantInfo(type: .ocr, status: .missing),
            originalVariant: BundleVariantInfo(type: .original, status: .missing),
            pageCount: 0,
            referenceCount: 0,
            createdAt: Date()
        )
    }
}

struct BundleVariantInfo: Identifiable {
    var id: PDFType { type }
    let type: PDFType
    let status: BundleVariantStatus
}

enum BundleVariantStatus: Equatable {
    case available
    case missing
    case fileMissing

    var requiresSupplement: Bool {
        self != .available
    }
}

extension PDFType: CaseIterable {
    static var allCases: [PDFType] {
        [.display, .ocr, .original]
    }

    static var pageCountPriority: [PDFType] {
        [.display, .original, .ocr]
    }

    var title: String {
        switch self {
        case .display:
            return "Display PDF"
        case .ocr:
            return "OCR PDF"
        case .original:
            return "Original PDF"
        }
    }

    var shortTitle: String {
        switch self {
        case .display:
            return "Display"
        case .ocr:
            return "OCR"
        case .original:
            return "Original"
        }
    }

    var requirementText: String {
        switch self {
        case .display:
            return "Required"
        case .ocr:
            return "Optional"
        case .original:
            return "Optional"
        }
    }

    var summaryDescription: String {
        switch self {
        case .display:
            return "Primary source for rendering and page navigation."
        case .ocr:
            return "Used for text extraction and OCR-based reading."
        case .original:
            return "Original source for comparison and verification."
        }
    }
}
