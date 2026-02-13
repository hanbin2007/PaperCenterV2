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
    private struct BuildPageContext {
        let doc: Doc
        let pageGroup: PageGroup?
        let page: Page
        let groupOrderKey: Int
        let pageOrderInGroup: Int
    }

    private let modelContext: ModelContext?
    private var bundleCache: [UUID: PDFBundle] = [:]

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    init() {
        self.modelContext = nil
    }

    func buildSession(for doc: Doc) -> UniversalDocSession {
        buildSession(for: doc, pageGroupID: nil)
    }

    func buildSession(for doc: Doc, pageGroupID: UUID?) -> UniversalDocSession {
        let slots = buildSlots(from: buildPageContexts(for: doc, pageGroupID: pageGroupID))
        return UniversalDocSession(
            scope: .singleDoc(doc.id),
            slots: slots,
            viewMode: .continuous
        )
    }

    func buildSession(for docs: [Doc]) -> UniversalDocSession {
        let orderedDocs = sortDocs(docs)
        let slots = buildSlots(from: buildPageContexts(for: orderedDocs, shouldSortDocs: false))
        return UniversalDocSession(
            scope: .allDocuments(orderedDocs.map(\.id)),
            slots: slots,
            viewMode: .continuous
        )
    }

    private func buildSlots(from pageContexts: [BuildPageContext]) -> [UniversalDocLogicalPageSlot] {
        pageContexts.compactMap { buildSlot(for: $0) }
    }

    private func sortDocs(_ docs: [Doc]) -> [Doc] {
        docs.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            if lhs.title != rhs.title {
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func buildPageContexts(for doc: Doc, pageGroupID: UUID?) -> [BuildPageContext] {
        var contexts: [BuildPageContext] = []
        let orderedGroups = doc.orderedPageGroups

        for (groupIndex, pageGroup) in orderedGroups.enumerated() {
            if let pageGroupID, pageGroup.id != pageGroupID {
                continue
            }

            for (pageIndex, page) in pageGroup.orderedPages.enumerated() {
                contexts.append(
                    BuildPageContext(
                        doc: doc,
                        pageGroup: pageGroup,
                        page: page,
                        groupOrderKey: groupIndex,
                        pageOrderInGroup: pageIndex
                    )
                )
            }
        }

        return contexts
    }

    private func buildPageContexts(for docs: [Doc], shouldSortDocs: Bool) -> [BuildPageContext] {
        let orderedDocs = shouldSortDocs ? sortDocs(docs) : docs
        var contexts: [BuildPageContext] = []
        var globalGroupOrder = 0

        for doc in orderedDocs {
            for pageGroup in doc.orderedPageGroups {
                let pages = pageGroup.orderedPages
                for (pageIndex, page) in pages.enumerated() {
                    contexts.append(
                        BuildPageContext(
                            doc: doc,
                            pageGroup: pageGroup,
                            page: page,
                            groupOrderKey: globalGroupOrder,
                            pageOrderInGroup: pageIndex
                        )
                    )
                }
                globalGroupOrder += 1
            }
        }

        return contexts
    }

    private func buildSlot(for context: BuildPageContext) -> UniversalDocLogicalPageSlot? {
        let page = context.page
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
            docID: context.doc.id,
            docTitle: context.doc.title,
            pageGroupID: context.pageGroup?.id,
            pageGroupTitle: context.pageGroup?.title ?? "Ungrouped",
            groupOrderKey: context.groupOrderKey,
            pageOrderInGroup: context.pageOrderInGroup,
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
        if hasReadablePDF(in: bundle, type: .display) { return .display }
        if hasReadablePDF(in: bundle, type: .original) { return .original }
        if hasReadablePDF(in: bundle, type: .ocr) { return .ocr }
        if bundle.ocrTextByPage[version.pageNumber]?.isEmpty == false { return .ocr }
        return .display
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

    private func hasReadablePDF(in bundle: PDFBundle, type: PDFType) -> Bool {
        guard let url = bundle.fileURL(for: type) else {
            return false
        }
        return FileManager.default.fileExists(atPath: url.path)
    }
}
