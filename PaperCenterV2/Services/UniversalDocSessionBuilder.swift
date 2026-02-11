//
//  UniversalDocSessionBuilder.swift
//  PaperCenterV2
//
//  Builds a session representation for UniversalDoc Viewer.
//

import Foundation
import SwiftData

@MainActor
final class UniversalDocSessionBuilder {
    private let modelContext: ModelContext?
    private var bundleCache: [UUID: PDFBundle] = [:]

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    init() {
        self.modelContext = nil
    }

    func buildSession(for doc: Doc) -> UniversalDocSession {
        let slots = doc.allPages.compactMap { buildSlot(for: $0) }
        return UniversalDocSession(
            docID: doc.id,
            slots: slots,
            viewMode: .paged
        )
    }

    private func buildSlot(for page: Page) -> UniversalDocLogicalPageSlot? {
        let ordered = (page.versions ?? []).sorted { lhs, rhs in
            lhs.createdAt < rhs.createdAt
        }
        guard !ordered.isEmpty else { return nil }

        let defaultVersionID = resolveDefaultVersionID(for: page, versions: ordered)
        let versionOptions = ordered.enumerated().map { index, version in
            UniversalDocVersionOption(
                id: version.id,
                pdfBundleID: version.pdfBundleID,
                pageNumber: version.pageNumber,
                createdAt: version.createdAt,
                ordinal: index + 1,
                isCurrentDefault: version.id == defaultVersionID
            )
        }

        guard let defaultOption = versionOptions.first(where: { $0.id == defaultVersionID }) else {
            return nil
        }

        let defaultSource = resolveDefaultSource(for: defaultOption)

        return UniversalDocLogicalPageSlot(
            id: page.id,
            pageID: page.id,
            versionOptions: versionOptions,
            defaultVersionID: defaultVersionID,
            defaultSource: defaultSource,
            canPreviewOtherVersions: versionOptions.count > 1,
            canSwitchSource: true,
            canAnnotate: true
        )
    }

    private func resolveDefaultVersionID(for page: Page, versions: [PageVersion]) -> UUID {
        if let matchedCurrent = versions.first(where: { version in
            version.pdfBundleID == page.currentPDFBundleID && version.pageNumber == page.currentPageNumber
        }) {
            return matchedCurrent.id
        }

        return versions.max(by: { $0.createdAt < $1.createdAt })?.id ?? versions[versions.count - 1].id
    }

    private func resolveDefaultSource(for version: UniversalDocVersionOption) -> UniversalDocViewerSource {
        guard let bundle = fetchBundle(id: version.pdfBundleID) else {
            return .display
        }
        if bundle.displayPDFPath != nil { return .display }
        if bundle.originalPDFPath != nil { return .original }
        return .ocr
    }

    private func fetchBundle(id: UUID) -> PDFBundle? {
        if let cached = bundleCache[id] {
            return cached
        }

        guard let modelContext else {
            return nil
        }

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
}
