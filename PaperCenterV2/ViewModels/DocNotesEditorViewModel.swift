//
//  DocNotesEditorViewModel.swift
//  PaperCenterV2
//
//  Editing and persistence layer for NoteBlock trees bound to a page version.
//

import CoreGraphics
import Foundation
import SwiftData

@MainActor
@Observable
final class DocNotesEditorViewModel {
    private let modelContext: ModelContext

    var currentPageVersionIDs: [UUID] = []
    var notes: [NoteBlock] = []
    var selectedNoteID: UUID?

    var statusMessage: String?
    var errorMessage: String?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    var noteIndex: [UUID: NoteBlock] {
        Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
    }

    var rootNotes: [NoteBlock] {
        notes
            .filter { $0.parentNoteID == nil }
            .sorted { lhs, rhs in
                if lhs.pageOrderIndex != rhs.pageOrderIndex {
                    return lhs.pageOrderIndex < rhs.pageOrderIndex
                }
                if lhs.verticalOrderHint == rhs.verticalOrderHint {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.verticalOrderHint < rhs.verticalOrderHint
            }
    }

    func loadNotes(pageVersionID: UUID) {
        loadNotes(pageVersionIDs: [pageVersionID])
    }

    func loadNotes(pageVersionIDs: [UUID]) {
        currentPageVersionIDs = pageVersionIDs
        let targetIDs = Set(pageVersionIDs)
        guard !targetIDs.isEmpty else {
            notes = []
            selectedNoteID = nil
            return
        }

        let descriptor = FetchDescriptor<NoteBlock>(
            predicate: #Predicate { note in
                note.isDeleted == false
            }
        )

        do {
            let fetched = try modelContext.fetch(descriptor)
            notes = fetched
                .filter { targetIDs.contains($0.pageVersionID) }
                .sorted { lhs, rhs in
                if lhs.pageOrderIndex != rhs.pageOrderIndex {
                    return lhs.pageOrderIndex < rhs.pageOrderIndex
                }
                if lhs.verticalOrderHint != rhs.verticalOrderHint {
                    return lhs.verticalOrderHint < rhs.verticalOrderHint
                }
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.createdAt < rhs.createdAt
            }

            if let selectedNoteID,
               notes.contains(where: { $0.id == selectedNoteID }) == false {
                self.selectedNoteID = nil
            }
        } catch {
            errorMessage = "Failed to load notes: \(error.localizedDescription)"
        }
    }

    func rootNotes(for pageVersionID: UUID) -> [NoteBlock] {
        rootNotes.filter { $0.pageVersionID == pageVersionID }
    }

    func orderedChildren(of noteID: UUID) -> [NoteBlock] {
        guard let note = noteIndex[noteID] else { return [] }
        return note.orderedChildren(from: notes).filter { !$0.isDeleted }
    }

    func createRoot(
        pageVersionID: UUID,
        page: Page,
        normalizedRect: CGRect,
        title: String?,
        body: String
    ) {
        guard let pageVersion = fetchPageVersion(id: pageVersionID) else {
            errorMessage = "Unable to resolve page version for note creation."
            return
        }

        let rect = clampRect(normalizedRect)
        let rootHints = rootNotes.map(\.verticalOrderHint)
        let nextHint = max(rootHints.max() ?? 0, rect.minY)

        let note = NoteBlock(
            pageVersionID: pageVersion.id,
            pageVersion: pageVersion,
            pageId: page.id,
            docId: page.pageGroup?.doc?.id,
            pdfBundleId: pageVersion.pdfBundleID,
            pageIndexInBundle: max(pageVersion.pageNumber - 1, 0),
            pageOrderIndex: computePageOrderIndex(for: page),
            verticalOrderHint: nextHint,
            rectX: rect.origin.x,
            rectY: rect.origin.y,
            rectWidth: rect.size.width,
            rectHeight: rect.size.height,
            title: trimToOptional(title),
            body: body.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        modelContext.insert(note)
        persist(success: "Note created")
        selectedNoteID = note.id
    }

    func createReply(parentID: UUID, title: String?, body: String) {
        guard let parent = noteIndex[parentID] else {
            errorMessage = "Parent note not found."
            return
        }

        do {
            let reply = parent.makeReply(
                title: trimToOptional(title),
                body: body.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            try parent.addChild(reply)
            modelContext.insert(reply)
            persist(success: "Reply added")
            selectedNoteID = reply.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateNote(noteID: UUID, title: String?, body: String) {
        guard let note = noteIndex[noteID] else {
            errorMessage = "Note not found."
            return
        }

        note.title = trimToOptional(title)
        note.body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        note.touch()
        persist(success: "Note updated")
    }

    func updateRect(noteID: UUID, normalizedRect: CGRect) {
        guard let note = noteIndex[noteID] else {
            errorMessage = "Note not found."
            return
        }

        let rect = clampRect(normalizedRect)
        note.rectX = rect.origin.x
        note.rectY = rect.origin.y
        note.rectWidth = rect.size.width
        note.rectHeight = rect.size.height
        note.verticalOrderHint = rect.minY
        note.touch()
        persist(success: "Anchor updated")
    }

    func moveSibling(noteID: UUID, from: Int, to: Int) {
        guard let note = noteIndex[noteID] else {
            errorMessage = "Note not found."
            return
        }

        if let parentID = note.parentNoteID,
           let parent = noteIndex[parentID] {
            parent.moveChild(from: from, to: to)
            parent.touch()
            persist(success: "Reply order updated")
            return
        }

        var orderedRoots = rootNotes
        guard !orderedRoots.isEmpty else { return }

        let sourceIndex = orderedRoots.firstIndex(where: { $0.id == noteID }) ?? from
        guard sourceIndex >= 0, sourceIndex < orderedRoots.count else { return }

        let destination = min(max(to, 0), orderedRoots.count)
        let moved = orderedRoots.remove(at: sourceIndex)
        let adjustedDestination = destination > sourceIndex ? destination - 1 : destination
        orderedRoots.insert(moved, at: adjustedDestination)

        resequenceRootOrder(orderedRoots)
        persist(success: "Root note order updated")
    }

    func moveToParent(noteID: UUID, newParentID: UUID?, at index: Int?) {
        guard let note = noteIndex[noteID] else {
            errorMessage = "Note not found."
            return
        }

        do {
            if let currentParentID = note.parentNoteID,
               let currentParent = noteIndex[currentParentID] {
                _ = currentParent.removeChild(note)
            }

            if let newParentID,
               let newParent = noteIndex[newParentID] {
                guard newParent.pageVersionID == note.pageVersionID else {
                    errorMessage = "Cannot move note across page versions."
                    return
                }
                _ = try newParent.addChild(note, at: index)
                newParent.touch()
            } else {
                note.parent = nil
                note.parentNoteID = nil

                var roots = rootNotes.filter { $0.id != note.id }
                let insertionIndex = min(max(index ?? roots.count, 0), roots.count)
                roots.insert(note, at: insertionIndex)
                resequenceRootOrder(roots)
            }

            note.touch()
            persist(success: "Note moved")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteSubtree(noteID: UUID) {
        guard let root = noteIndex[noteID] else {
            errorMessage = "Note not found."
            return
        }

        if let parentID = root.parentNoteID,
           let parent = noteIndex[parentID] {
            _ = parent.removeChild(root)
            parent.touch()
        }

        let all = collectSubtree(rootID: noteID)
        for note in all {
            note.isDeleted = true
            note.touch()
        }

        selectedNoteID = nil
        persist(success: "Note deleted")
    }

    // MARK: - Helpers

    private func fetchPageVersion(id: UUID) -> PageVersion? {
        let descriptor = FetchDescriptor<PageVersion>(
            predicate: #Predicate { version in
                version.id == id
            }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func resequenceRootOrder(_ roots: [NoteBlock]) {
        guard !roots.isEmpty else { return }
        let step = 1.0 / Double(max(roots.count, 1) + 1)
        for (index, root) in roots.enumerated() {
            root.verticalOrderHint = step * Double(index + 1)
            root.touch()
        }
    }

    private func collectSubtree(rootID: UUID) -> [NoteBlock] {
        guard let root = noteIndex[rootID] else { return [] }
        return root.flattenedThread(from: notes)
    }

    private func computePageOrderIndex(for page: Page) -> Int {
        guard let pageGroup = page.pageGroup, let doc = pageGroup.doc else { return 0 }
        let orderedPages = doc.orderedPageGroups.flatMap { $0.orderedPages }
        return orderedPages.firstIndex(where: { $0.id == page.id }) ?? 0
    }

    private func clampRect(_ rect: CGRect) -> CGRect {
        let minSize: CGFloat = 0.01
        let clampedX = max(0, min(1, rect.origin.x))
        let clampedY = max(0, min(1, rect.origin.y))
        let clampedWidth = max(minSize, min(1 - clampedX, rect.width))
        let clampedHeight = max(minSize, min(1 - clampedY, rect.height))
        return CGRect(x: clampedX, y: clampedY, width: clampedWidth, height: clampedHeight)
    }

    private func trimToOptional(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed
        }
        return nil
    }

    private func persist(success: String) {
        do {
            try modelContext.save()
            if !currentPageVersionIDs.isEmpty {
                loadNotes(pageVersionIDs: currentPageVersionIDs)
            }
            statusMessage = success
            errorMessage = nil
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
        }
    }
}
