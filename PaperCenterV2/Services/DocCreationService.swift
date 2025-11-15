//
//  DocCreationService.swift
//  PaperCenterV2
//
//  Created by Claude on 2025-11-09.
//

import Foundation
import SwiftData
import PDFKit

/// Service for creating Docs from PDFBundles
@MainActor
final class DocCreationService {

    // MARK: - Properties

    private let modelContext: ModelContext

    // MARK: - Initialization

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Doc Creation

    /// Create a Doc from a PDFBundle with a default PageGroup
    /// - Parameters:
    ///   - bundle: PDFBundle to create Doc from
    ///   - title: Doc title (also used for PageGroup title)
    /// - Returns: The created Doc with all pages
    /// - Throws: Creation errors
    func createDoc(from bundle: PDFBundle, title: String) throws -> Doc {
        // Validate bundle has at least display PDF
        guard let displayURL = bundle.fileURL(for: .display) else {
            throw DocCreationError.noDisplayPDF
        }

        // Load PDF to get page count
        guard let pdfDocument = PDFDocument(url: displayURL) else {
            throw DocCreationError.invalidPDF
        }

        let pageCount = pdfDocument.pageCount
        guard pageCount > 0 else {
            throw DocCreationError.emptyPDF
        }

        // Create Doc
        let doc = Doc(title: title)
        modelContext.insert(doc)

        // Create default PageGroup (using Doc title)
        let pageGroup = PageGroup(title: title, doc: doc)
        modelContext.insert(pageGroup)
        doc.addPageGroup(pageGroup)

        // Create Page for each PDF page
        for pageNumber in 1...pageCount {
            let page = Page(
                pdfBundle: bundle,
                pageNumber: pageNumber,
                pageGroup: pageGroup
            )
            modelContext.insert(page)
            pageGroup.addPage(page)
        }

        return doc
    }

    /// Create a Doc from a PDFBundle with custom PageGroup title
    /// - Parameters:
    ///   - bundle: PDFBundle to create Doc from
    ///   - docTitle: Doc title
    ///   - pageGroupTitle: PageGroup title
    /// - Returns: The created Doc with all pages
    /// - Throws: Creation errors
    func createDoc(from bundle: PDFBundle, docTitle: String, pageGroupTitle: String) throws -> Doc {
        // Validate bundle has at least display PDF
        guard let displayURL = bundle.fileURL(for: .display) else {
            throw DocCreationError.noDisplayPDF
        }

        // Load PDF to get page count
        guard let pdfDocument = PDFDocument(url: displayURL) else {
            throw DocCreationError.invalidPDF
        }

        let pageCount = pdfDocument.pageCount
        guard pageCount > 0 else {
            throw DocCreationError.emptyPDF
        }

        // Create Doc
        let doc = Doc(title: docTitle)
        modelContext.insert(doc)

        // Create default PageGroup
        let pageGroup = PageGroup(title: pageGroupTitle, doc: doc)
        modelContext.insert(pageGroup)
        doc.addPageGroup(pageGroup)

        // Create Page for each PDF page
        for pageNumber in 1...pageCount {
            let page = Page(
                pdfBundle: bundle,
                pageNumber: pageNumber,
                pageGroup: pageGroup
            )
            modelContext.insert(page)
            pageGroup.addPage(page)
        }

        return doc
    }
}

// MARK: - Errors

enum DocCreationError: LocalizedError {
    case noDisplayPDF
    case invalidPDF
    case emptyPDF

    var errorDescription: String? {
        switch self {
        case .noDisplayPDF:
            return "PDFBundle must have a display PDF to create a Doc"
        case .invalidPDF:
            return "Unable to load PDF document"
        case .emptyPDF:
            return "PDF document contains no pages"
        }
    }
}
