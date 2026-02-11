//
//  PageVersionService.swift
//  PaperCenterV2
//
//  Domain operations for creating page versions with inheritance options.
//

import Foundation
import SwiftData

enum PageVersionServiceError: LocalizedError {
    case noteInheritanceRequiresModelContext

    var errorDescription: String? {
        switch self {
        case .noteInheritanceRequiresModelContext:
            return "Cloning note blocks requires a ModelContext."
        }
    }
}

@MainActor
final class PageVersionService {
    private let modelContext: ModelContext?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    init() {
        self.modelContext = nil
    }

    @discardableResult
    func createVersion(
        for page: Page,
        to newBundle: PDFBundle,
        pageNumber newPageNumber: Int,
        basedOn baseVersion: PageVersion?,
        inheritance: VersionInheritanceOptions
    ) throws -> PageVersion? {
        let bundleChanged = newBundle.id != page.currentPDFBundleID
        let pageNumberChanged = newPageNumber != page.currentPageNumber
        guard bundleChanged || pageNumberChanged else {
            return nil
        }

        let sourceVersion = baseVersion ?? page.latestVersion
        let sourceMetadata = try resolveMetadataSnapshot(
            sourceVersion: sourceVersion,
            fallbackPage: page
        )

        let inheritedMetadata = MetadataSnapshot(
            tagIDs: inheritance.inheritTags ? sourceMetadata.tagIDs : [],
            variableAssignments: inheritance.inheritVariables ? sourceMetadata.variableAssignments : []
        )
        let snapshotData = try PageVersion.encodeMetadataSnapshot(inheritedMetadata)

        let newVersion = PageVersion(
            pdfBundleID: newBundle.id,
            pageNumber: newPageNumber,
            metadataSnapshot: snapshotData,
            inheritedTagMetadata: inheritance.inheritTags,
            inheritedVariableMetadata: inheritance.inheritVariables,
            inheritedNoteBlocks: inheritance.inheritNoteBlocks
        )
        newVersion.page = page

        if page.versions == nil {
            page.versions = []
        }
        page.versions?.append(newVersion)

        page.pdfBundle = newBundle
        page.currentPDFBundleID = newBundle.id
        page.currentPageNumber = newPageNumber
        page.touch()

        if inheritance.inheritNoteBlocks, let sourceVersion {
            guard modelContext != nil else {
                throw PageVersionServiceError.noteInheritanceRequiresModelContext
            }
            try cloneNoteBlocks(from: sourceVersion, to: newVersion)
        }

        return newVersion
    }

    private func resolveMetadataSnapshot(
        sourceVersion: PageVersion?,
        fallbackPage: Page
    ) throws -> MetadataSnapshot {
        if let snapshot = try sourceVersion?.decodeMetadataSnapshot() {
            return snapshot
        }

        let variableSnapshots = (fallbackPage.variableAssignments ?? []).map { assignment in
            VariableAssignmentSnapshot(
                variableID: assignment.variable?.id ?? UUID(),
                intValue: assignment.intValue,
                listValue: assignment.listValue,
                textValue: assignment.textValue,
                dateValue: assignment.dateValue
            )
        }

        return MetadataSnapshot(
            tagIDs: fallbackPage.tags?.map { $0.id } ?? [],
            variableAssignments: variableSnapshots
        )
    }

    private func cloneNoteBlocks(from sourceVersion: PageVersion, to targetVersion: PageVersion) throws {
        guard let modelContext else {
            throw PageVersionServiceError.noteInheritanceRequiresModelContext
        }
        let sourceVersionID = sourceVersion.id
        let descriptor = FetchDescriptor<NoteBlock>(
            predicate: #Predicate { note in
                note.pageVersionID == sourceVersionID && note.isDeleted == false
            }
        )
        let sourceNotes = try modelContext.fetch(descriptor)
        guard !sourceNotes.isEmpty else { return }

        let sorted = sourceNotes.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.createdAt < rhs.createdAt
        }

        var mapping: [UUID: NoteBlock] = [:]

        for source in sorted {
            let clone = NoteBlock(
                pageVersionID: targetVersion.id,
                pageVersion: targetVersion,
                pageId: source.pageId,
                docId: source.docId,
                pdfBundleId: source.pdfBundleId,
                pageIndexInBundle: source.pageIndexInBundle,
                pageOrderIndex: source.pageOrderIndex,
                verticalOrderHint: source.verticalOrderHint,
                rectX: source.rectX,
                rectY: source.rectY,
                rectWidth: source.rectWidth,
                rectHeight: source.rectHeight,
                title: source.title,
                body: source.body,
                isDeleted: source.isDeleted
            )
            clone.tags = source.tags

            if let sourceAssignments = source.variableAssignments {
                let clonedAssignments = sourceAssignments.compactMap { assignment -> NoteBlockVariableAssignment? in
                    guard let variable = assignment.variable else { return nil }
                    return NoteBlockVariableAssignment(
                        variable: variable,
                        noteBlock: clone,
                        intValue: assignment.intValue,
                        listValue: assignment.listValue,
                        textValue: assignment.textValue,
                        dateValue: assignment.dateValue
                    )
                }
                clone.variableAssignments = clonedAssignments
                for assignment in clonedAssignments {
                    modelContext.insert(assignment)
                }
            }

            modelContext.insert(clone)
            mapping[source.id] = clone
        }

        for source in sorted {
            guard let clone = mapping[source.id] else { continue }
            if let sourceParentID = source.parentNoteID,
               let parentClone = mapping[sourceParentID] {
                clone.parentNoteID = parentClone.id
                clone.parent = parentClone
            } else {
                clone.parentNoteID = nil
                clone.parent = nil
            }
            clone.childOrder = source.childOrder.compactMap { childID in
                mapping[childID]?.id
            }
            clone.touch()
        }
    }
}
