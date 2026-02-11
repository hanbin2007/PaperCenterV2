//
//  PDFImportViewModel.swift
//  PaperCenterV2
//
//  Created by Claude on 2025-11-09.
//

import Foundation
import SwiftData
import PDFKit
import UIKit

/// ViewModel for managing PDF import
@MainActor
@Observable
final class PDFImportViewModel {

    struct ImportPage: Identifiable, Hashable {
        let id = UUID()
        let pageNumber: Int
        let thumbnail: UIImage?
        let hasOriginal: Bool
        let hasOCR: Bool
    }

    // MARK: - Properties

    private let modelContext: ModelContext
    private let importService: PDFImportService

    // State
    var bundleName = ""
    var displayPDFURL: URL? {
        didSet {
            guard displayPDFURL != oldValue else { return }
            rebuildPageMetadata()
        }
    }
    var ocrPDFURL: URL? {
        didSet {
            guard ocrPDFURL != oldValue else { return }
            rebuildPageMetadata()
        }
    }
    var originalPDFURL: URL? {
        didSet {
            guard originalPDFURL != oldValue else { return }
            rebuildPageMetadata()
        }
    }
    var isImporting = false
    var errorMessage: String?

    var pagePreviews: [ImportPage] = []
    var selectedPageNumbers: Set<Int> = []

    // MARK: - Initialization

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.importService = PDFImportService(modelContext: modelContext)
    }

    // MARK: - Computed Properties

    /// Check if import is valid (display PDF is required)
    var canImport: Bool {
        if pagePreviews.isEmpty {
            return displayPDFURL != nil && !isImporting
        }
        return displayPDFURL != nil && !selectedPageNumbers.isEmpty && !isImporting
    }

    var selectedPageCount: Int {
        selectedPageNumbers.count
    }

    var totalPageCount: Int {
        pagePreviews.count
    }

    // MARK: - Import Actions

    /// Import the selected PDFs as a bundle
    func importBundle() async -> Bool {
        guard let displayURL = displayPDFURL else {
            errorMessage = "Display PDF is required"
            return false
        }

        if !pagePreviews.isEmpty && selectedPageNumbers.isEmpty {
            errorMessage = "Select at least one page to import"
            return false
        }

        isImporting = true
        errorMessage = nil

        do {
            let finalName = bundleName.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = finalName.isEmpty ? "Untitled Bundle" : finalName

            let selectedPages = pagePreviews.isEmpty ? nil : Array(selectedPageNumbers).sorted()

            _ = try await importService.importPDFBundle(
                name: name,
                displayPDF: displayURL,
                ocrPDF: ocrPDFURL,
                originalPDF: originalPDFURL,
                selectedDisplayPages: selectedPages
            )

            // Save context
            try modelContext.save()

            // Clear state
            reset()
            return true
        } catch {
            errorMessage = error.localizedDescription
            isImporting = false
            return false
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
        pagePreviews = []
        selectedPageNumbers.removeAll()
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

    func toggleSelection(for page: ImportPage) {
        if selectedPageNumbers.contains(page.pageNumber) {
            selectedPageNumbers.remove(page.pageNumber)
        } else {
            selectedPageNumbers.insert(page.pageNumber)
        }
    }

    func isSelected(_ page: ImportPage) -> Bool {
        selectedPageNumbers.contains(page.pageNumber)
    }

    func selectAllPages() {
        selectedPageNumbers = Set(pagePreviews.map { $0.pageNumber })
    }

    func clearSelection() {
        selectedPageNumbers.removeAll()
    }

    private func rebuildPageMetadata() {
        guard let displayURL = displayPDFURL else {
            pagePreviews = []
            selectedPageNumbers.removeAll()
            return
        }

        guard let displayDocument = makeDocument(from: displayURL) else {
            pagePreviews = []
            selectedPageNumbers.removeAll()
            errorMessage = "Unable to load Display PDF"
            return
        }

        let originalDocument = makeDocument(from: originalPDFURL)
        let ocrDocument = makeDocument(from: ocrPDFURL)

        var previews: [ImportPage] = []
        let pageCount = displayDocument.pageCount
        for index in 0..<pageCount {
            let pageNumber = index + 1
            let displayPage = displayDocument.page(at: index)
            let thumbnail = displayPage?.thumbnail(of: CGSize(width: 160, height: 220), for: .cropBox)
            let hasOriginal = originalDocument?.page(at: index) != nil
            let hasOCR = ocrDocument?.page(at: index) != nil

            previews.append(
                ImportPage(
                    pageNumber: pageNumber,
                    thumbnail: thumbnail,
                    hasOriginal: hasOriginal,
                    hasOCR: hasOCR
                )
            )
        }

        pagePreviews = previews
        let availableNumbers = Set(previews.map { $0.pageNumber })
        if selectedPageNumbers.isEmpty {
            selectedPageNumbers = availableNumbers
        } else {
            let intersection = selectedPageNumbers.intersection(availableNumbers)
            selectedPageNumbers = intersection.isEmpty ? availableNumbers : intersection
        }
    }

    private func makeDocument(from url: URL?) -> PDFDocument? {
        guard let url else { return nil }
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return PDFDocument(url: url)
    }
}
