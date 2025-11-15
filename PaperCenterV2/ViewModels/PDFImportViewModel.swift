//
//  PDFImportViewModel.swift
//  PaperCenterV2
//
//  Created by Claude on 2025-11-09.
//

import Foundation
import SwiftData

/// ViewModel for managing PDF import
@MainActor
@Observable
final class PDFImportViewModel {

    // MARK: - Properties

    private let modelContext: ModelContext
    private let importService: PDFImportService

    // State
    var bundleName = ""
    var displayPDFURL: URL?
    var ocrPDFURL: URL?
    var originalPDFURL: URL?
    var isImporting = false
    var errorMessage: String?

    // MARK: - Initialization

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.importService = PDFImportService(modelContext: modelContext)
    }

    // MARK: - Computed Properties

    /// Check if import is valid (display PDF is required)
    var canImport: Bool {
        return displayPDFURL != nil && !isImporting
    }

    // MARK: - Import Actions

    /// Import the selected PDFs as a bundle
    func importBundle() async {
        guard let displayURL = displayPDFURL else {
            errorMessage = "Display PDF is required"
            return
        }

        isImporting = true
        errorMessage = nil

        do {
            let finalName = bundleName.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = finalName.isEmpty ? "Untitled Bundle" : finalName

            _ = try await importService.importPDFBundle(
                name: name,
                displayPDF: displayURL,
                ocrPDF: ocrPDFURL,
                originalPDF: originalPDFURL
            )

            // Save context
            try modelContext.save()

            // Clear state
            reset()
        } catch {
            errorMessage = error.localizedDescription
            isImporting = false
        }
    }

    /// Reset the import state
    func reset() {
        bundleName = ""
        displayPDFURL = nil
        ocrPDFURL = nil
        originalPDFURL = nil
        isImporting = false
        errorMessage = nil
    }

    /// Add a PDF to an existing bundle
    /// - Parameters:
    ///   - url: PDF file URL
    ///   - type: PDF type
    ///   - bundle: Existing bundle
    func addPDF(from url: URL, type: PDFType, to bundle: PDFBundle) async throws {
        let _ = try await importService.importPDF(from: url, type: type, into: bundle)
        try modelContext.save()
    }
}
