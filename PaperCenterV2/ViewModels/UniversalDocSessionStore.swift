//
//  UniversalDocSessionStore.swift
//  PaperCenterV2
//
//  Session-local state holder for UniversalDoc Viewer.
//

import Foundation

@MainActor
@Observable
final class UniversalDocSessionStore {
    let session: UniversalDocSession

    var currentPageIndex: Int = 0

    private var previewVersionByLogicalPageID: [UUID: UUID]
    private var sourceByLogicalPageID: [UUID: UniversalDocViewerSource]

    init(session: UniversalDocSession) {
        self.session = session
        self.previewVersionByLogicalPageID = Dictionary(
            uniqueKeysWithValues: session.slots.map { ($0.id, $0.defaultVersionID) }
        )
        self.sourceByLogicalPageID = Dictionary(
            uniqueKeysWithValues: session.slots.map { ($0.id, $0.defaultSource) }
        )
    }

    var hasPages: Bool {
        !session.slots.isEmpty
    }

    var currentSlot: UniversalDocLogicalPageSlot? {
        guard currentPageIndex >= 0, currentPageIndex < session.slots.count else {
            return nil
        }
        return session.slots[currentPageIndex]
    }

    func slot(for logicalPageID: UUID) -> UniversalDocLogicalPageSlot? {
        session.slots.first(where: { $0.id == logicalPageID })
    }

    func currentPreviewVersionID(for logicalPageID: UUID) -> UUID? {
        previewVersionByLogicalPageID[logicalPageID]
    }

    func currentSource(for logicalPageID: UUID) -> UniversalDocViewerSource? {
        sourceByLogicalPageID[logicalPageID]
    }

    func changePreviewVersion(logicalPageID: UUID, to pageVersionID: UUID) {
        guard let slot = slot(for: logicalPageID) else { return }
        guard slot.versionOptions.contains(where: { $0.id == pageVersionID }) else { return }
        previewVersionByLogicalPageID[logicalPageID] = pageVersionID
    }

    func changeSource(logicalPageID: UUID, to source: UniversalDocViewerSource) {
        guard slot(for: logicalPageID) != nil else { return }
        sourceByLogicalPageID[logicalPageID] = source
    }

    func navigate(to index: Int) {
        guard index >= 0, index < session.slots.count else { return }
        currentPageIndex = index
    }

    func logicalPageID(at index: Int) -> UUID? {
        guard index >= 0, index < session.slots.count else { return nil }
        return session.slots[index].id
    }

    func selectionSnapshots() -> (
        preview: [UUID: UUID],
        source: [UUID: UniversalDocViewerSource],
        pageIndex: Int
    ) {
        (previewVersionByLogicalPageID, sourceByLogicalPageID, currentPageIndex)
    }

    func applySelectionSnapshots(
        preview: [UUID: UUID],
        source: [UUID: UniversalDocViewerSource],
        fallbackLogicalPageID: UUID?
    ) {
        for slot in session.slots {
            if let selectedVersion = preview[slot.id],
               slot.versionOptions.contains(where: { $0.id == selectedVersion }) {
                previewVersionByLogicalPageID[slot.id] = selectedVersion
            }
            if let selectedSource = source[slot.id] {
                sourceByLogicalPageID[slot.id] = selectedSource
            }
        }

        guard let fallbackLogicalPageID,
              let index = session.slots.firstIndex(where: { $0.id == fallbackLogicalPageID }) else {
            return
        }
        currentPageIndex = index
    }
}
