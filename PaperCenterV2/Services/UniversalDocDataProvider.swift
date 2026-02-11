//
//  UniversalDocDataProvider.swift
//  PaperCenterV2
//
//  Resolves session selections into concrete render data.
//

import Foundation
import SwiftData
import PDFKit

struct UniversalDocRenderablePage {
    let logicalPageID: UUID
    let pageVersionID: UUID
    let source: UniversalDocViewerSource
    let fileURL: URL?
    let pageNumber: Int
    let bundleDisplayName: String
    let ocrText: String?
    let noteBlocks: [NoteBlock]
}

@MainActor
final class UniversalDocDataProvider {
    private let modelContext: ModelContext
    private var bundleCache: [UUID: PDFBundle] = [:]
    private var pageCountCache: [String: Int] = [:]

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func availableSources(for version: UniversalDocVersionOption) -> [UniversalDocViewerSource] {
        guard let bundle = bundle(for: version.pdfBundleID) else { return [] }
        return UniversalDocViewerSource.allCases.filter { source in
            isSourceAvailable(bundle: bundle, source: source, pageNumber: version.pageNumber)
        }
    }

    func preferredSource(for version: UniversalDocVersionOption) -> UniversalDocViewerSource? {
        let available = availableSources(for: version)
        if available.contains(.display) { return .display }
        if available.contains(.original) { return .original }
        if available.contains(.ocr) { return .ocr }
        return nil
    }

    func resolve(
        slot: UniversalDocLogicalPageSlot,
        selectedVersionID: UUID,
        selectedSource: UniversalDocViewerSource
    ) -> UniversalDocRenderablePage? {
        guard let version = slot.versionOptions.first(where: { $0.id == selectedVersionID }) else {
            return nil
        }
        guard let bundle = bundle(for: version.pdfBundleID) else {
            return nil
        }

        let availableSources = availableSources(for: version)
        let source = availableSources.contains(selectedSource)
            ? selectedSource
            : (preferredSource(for: version) ?? selectedSource)

        let fileURL = bundle.fileURL(for: source.toPDFType)
        let ocrText = bundle.ocrTextByPage[version.pageNumber]
        let notes = fetchNotes(pageVersionID: version.id)

        return UniversalDocRenderablePage(
            logicalPageID: slot.id,
            pageVersionID: version.id,
            source: source,
            fileURL: fileURL,
            pageNumber: version.pageNumber,
            bundleDisplayName: bundle.displayName,
            ocrText: ocrText,
            noteBlocks: notes
        )
    }

    func page(for id: UUID) -> Page? {
        let descriptor = FetchDescriptor<Page>(
            predicate: #Predicate { page in
                page.id == id
            }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchNotes(pageVersionID: UUID) -> [NoteBlock] {
        let descriptor = FetchDescriptor<NoteBlock>(
            predicate: #Predicate { note in
                note.pageVersionID == pageVersionID && note.isDeleted == false
            }
        )

        let notes = (try? modelContext.fetch(descriptor)) ?? []
        return notes.sorted { lhs, rhs in
            if lhs.pageOrderIndex == rhs.pageOrderIndex {
                return lhs.verticalOrderHint < rhs.verticalOrderHint
            }
            return lhs.pageOrderIndex < rhs.pageOrderIndex
        }
    }

    private func bundle(for id: UUID) -> PDFBundle? {
        if let cached = bundleCache[id] { return cached }

        let descriptor = FetchDescriptor<PDFBundle>(
            predicate: #Predicate { bundle in
                bundle.id == id
            }
        )

        guard let fetched = try? modelContext.fetch(descriptor).first else {
            return nil
        }
        bundleCache[id] = fetched
        return fetched
    }

    private func isSourceAvailable(
        bundle: PDFBundle,
        source: UniversalDocViewerSource,
        pageNumber: Int
    ) -> Bool {
        guard pageNumber > 0 else { return false }

        if source == .ocr {
            let hasOCRText = bundle.ocrTextByPage[pageNumber]?.isEmpty == false
            if hasOCRText {
                return true
            }
            guard let ocrURL = bundle.fileURL(for: .ocr) else { return false }
            return containsPage(at: pageNumber, url: ocrURL)
        }

        guard let url = bundle.fileURL(for: source.toPDFType) else { return false }
        return containsPage(at: pageNumber, url: url)
    }

    private func containsPage(at pageNumber: Int, url: URL) -> Bool {
        let key = url.absoluteString
        let pageCount: Int
        if let cached = pageCountCache[key] {
            pageCount = cached
        } else {
            guard let document = PDFDocument(url: url) else {
                return false
            }
            pageCount = document.pageCount
            pageCountCache[key] = pageCount
        }
        return pageNumber <= pageCount
    }
}

private extension UniversalDocViewerSource {
    var toPDFType: PDFType {
        switch self {
        case .display:
            return .display
        case .original:
            return .original
        case .ocr:
            return .ocr
        }
    }
}
