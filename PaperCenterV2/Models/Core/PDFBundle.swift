//
//  PDFBundle.swift
//  PaperCenterV2
//
//  Created by Claude on 2025-11-09.
//

import Foundation
import SwiftData

/// Container for PDF files and their extracted text
///
/// A PDFBundle can contain up to three aligned variants of the same content:
/// - DisplayPDF: For final content display (core, recommended)
/// - OCRPDF: For text extraction (optional)
/// - OriginalPDF: Original exam paper without handwriting (optional)
@Model
final class PDFBundle {
    // MARK: - Properties

    /// Unique identifier
    var id: UUID

    /// User-defined name for this bundle (optional for migration compatibility)
    var name: String?

    /// System-managed creation timestamp
    var createdAt: Date

    /// System-managed update timestamp
    var updatedAt: Date

    /// Sandbox-relative path to display PDF
    var displayPDFPath: String?

    /// Sandbox-relative path to OCR PDF
    var ocrPDFPath: String?

    /// Sandbox-relative path to original PDF
    var originalPDFPath: String?

    /// Custom page alignment overrides (JSON-encoded)
    /// Format: { "display_to_ocr": [page_mappings], "display_to_original": [page_mappings] }
    var pageMapping: Data?

    /// Extracted OCR text indexed by page number
    /// Key: page number (1-based), Value: extracted text
    var ocrTextByPage: [Int: String]

    /// OCR extraction progress (0.0 to 1.0)
    var ocrExtractionProgress: Double

    /// OCR extraction status
    /// Values: "notStarted", "inProgress", "completed", "failed"
    var ocrExtractionStatus: String

    // MARK: - Relationships

    /// Inverse relationship to all Pages referencing this bundle
    @Relationship(deleteRule: .deny, inverse: \Page.pdfBundle)
    var referencingPages: [Page]?

    /// Tags applied to this bundle
    @Relationship(deleteRule: .nullify)
    var tags: [Tag]?

    /// Variable assignments for this bundle
    @Relationship(deleteRule: .cascade, inverse: \PDFBundleVariableAssignment.pdfBundle)
    var variableAssignments: [PDFBundleVariableAssignment]?

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        name: String? = nil,
        displayPDFPath: String? = nil,
        ocrPDFPath: String? = nil,
        originalPDFPath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
        self.displayPDFPath = displayPDFPath
        self.ocrPDFPath = ocrPDFPath
        self.originalPDFPath = originalPDFPath
        self.pageMapping = nil
        self.ocrTextByPage = [:]
        self.ocrExtractionProgress = 0.0
        self.ocrExtractionStatus = "notStarted"
    }

    // MARK: - Helper Methods

    /// Display name with fallback
    var displayName: String {
        return name ?? "Untitled Bundle"
    }

    /// Update the modification timestamp
    func touch() {
        self.updatedAt = Date()
    }

    /// Check if this bundle can be safely deleted
    /// Returns true if no pages reference this bundle
    var canDelete: Bool {
        return referencingPages?.isEmpty ?? true
    }

    /// Get the full file URL for a PDF type
    func fileURL(for type: PDFType) -> URL? {
        guard let path = path(for: type) else { return nil }
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsURL.appendingPathComponent(path)
    }

    /// Get the sandbox-relative path for a PDF type
    func path(for type: PDFType) -> String? {
        switch type {
        case .display:
            return displayPDFPath
        case .ocr:
            return ocrPDFPath
        case .original:
            return originalPDFPath
        }
    }

    /// Set the path for a PDF type
    func setPath(_ path: String?, for type: PDFType) {
        switch type {
        case .display:
            displayPDFPath = path
        case .ocr:
            ocrPDFPath = path
        case .original:
            originalPDFPath = path
        }
        touch()
    }
}

// MARK: - Supporting Types

/// PDF types supported in a bundle
enum PDFType {
    case display
    case ocr
    case original
}
