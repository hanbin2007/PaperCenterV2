//
//  NoteBlock.swift
//  PaperCenterV2
//
//  Created by zhb on 2026-02-02.
//

import Foundation
import CoreGraphics
import SwiftData

enum NoteHierarchyError: LocalizedError {
    case cannotParentSelf
    case crossAnchorParenting
    case circularReference
    case invalidChildOrder

    var errorDescription: String? {
        switch self {
        case .cannotParentSelf:
            return "A note cannot be its own parent."
        case .crossAnchorParenting:
            return "Parent and child notes must belong to the same page version anchor."
        case .circularReference:
            return "Nested notes cannot form circular references."
        case .invalidChildOrder:
            return "New child order must contain exactly the current child set."
        }
    }
}

/// User-authored note anchored to a PageVersion and a normalized rectangle on that page
@Model
final class NoteBlock {
    // MARK: - Properties

    /// Unique identifier
    var id: UUID

    /// Authoritative anchor pointing to the PageVersion this note belongs to
    var pageVersionID: UUID

    /// Cached navigation fields (best-effort, derived from the authoritative anchor)
    var pageId: UUID?
    var docId: UUID?
    var pdfBundleId: UUID
    var pageIndexInBundle: Int

    /// Sorting hints for list ordering
    var pageOrderIndex: Int
    var verticalOrderHint: Double

    /// Normalized rectangle on the page [0, 1]
    var rectX: Double
    var rectY: Double
    var rectWidth: Double
    var rectHeight: Double

    /// User-authored content
    var title: String?
    var body: String

    /// Metadata
    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool

    /// Parent note identifier for fast filtering/sync
    var parentNoteID: UUID?

    /// Ordered list of child IDs to preserve explicit reply ordering
    var childOrder: [UUID]

    // MARK: - Relationships

    /// Optional navigation to the anchored PageVersion (must match `pageVersionID` when present)
    @Relationship(deleteRule: .nullify)
    var pageVersion: PageVersion?

    /// Optional parent note for nested threads
    @Relationship(deleteRule: .nullify)
    var parent: NoteBlock?

    /// Tags applied to this note (generic tagging system)
    @Relationship(deleteRule: .nullify)
    var tags: [Tag]?

    /// Variable assignments applied to this note
    @Relationship(deleteRule: .cascade, inverse: \NoteBlockVariableAssignment.noteBlock)
    var variableAssignments: [NoteBlockVariableAssignment]?

    // MARK: - Initialization

    /// Primary initializer for already-normalized rectangles
    init(
        id: UUID = UUID(),
        pageVersionID: UUID,
        pageVersion: PageVersion? = nil,
        pageId: UUID?,
        docId: UUID?,
        pdfBundleId: UUID,
        pageIndexInBundle: Int,
        pageOrderIndex: Int,
        verticalOrderHint: Double,
        rectX: Double,
        rectY: Double,
        rectWidth: Double,
        rectHeight: Double,
        title: String? = nil,
        body: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDeleted: Bool = false,
        parentNoteID: UUID? = nil,
        childOrder: [UUID] = []
    ) {
        self.id = id
        self.pageVersionID = pageVersionID
        self.pageVersion = pageVersion
        self.pageId = pageId
        self.docId = docId
        self.pdfBundleId = pdfBundleId
        self.pageIndexInBundle = pageIndexInBundle
        self.pageOrderIndex = pageOrderIndex
        self.verticalOrderHint = verticalOrderHint
        self.rectX = rectX
        self.rectY = rectY
        self.rectWidth = rectWidth
        self.rectHeight = rectHeight
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
        self.parentNoteID = parentNoteID
        self.childOrder = childOrder

        assertAnchorConsistency()
        assertNormalizedRect()
    }

    /// Convenience factory that accepts absolute page coordinates and resolves cached navigation fields.
    /// - Parameters:
    ///   - pageVersion: Anchoring PageVersion (authoritative)
    ///   - absoluteRect: Rectangle in page pixel/point space
    ///   - pageSize: Full page size in the same units as `absoluteRect`
    ///   - title: Optional title
    ///   - body: Note body (required)
    static func createNormalized(
        pageVersion: PageVersion,
        absoluteRect: CGRect,
        pageSize: CGSize,
        title: String? = nil,
        body: String
    ) -> NoteBlock {
        let normalized = normalizeRect(absoluteRect, pageSize: pageSize)

        let page = pageVersion.page
        let pdfBundleId = pageVersion.pdfBundleID
        let pageId = page?.id
        let docId = page?.pageGroup?.doc?.id

        let pageIndexInBundle = max(pageVersion.pageNumber - 1, 0)
        let pageOrderIndex = Self.computePageOrderIndex(for: page)
        let verticalOrderHint = normalized.origin.y

        return NoteBlock(
            pageVersionID: pageVersion.id,
            pageVersion: pageVersion,
            pageId: pageId,
            docId: docId,
            pdfBundleId: pdfBundleId,
            pageIndexInBundle: pageIndexInBundle,
            pageOrderIndex: pageOrderIndex,
            verticalOrderHint: verticalOrderHint,
            rectX: normalized.origin.x,
            rectY: normalized.origin.y,
            rectWidth: normalized.size.width,
            rectHeight: normalized.size.height,
            title: title,
            body: body
        )
    }

    // MARK: - Hierarchy

    var isRoot: Bool {
        parentNoteID == nil
    }

    func orderedChildren(from notes: [NoteBlock]) -> [NoteBlock] {
        let directChildren = notes.filter { $0.parentNoteID == id }
        let childrenDict = Dictionary(uniqueKeysWithValues: directChildren.map { ($0.id, $0) })
        let ordered = childOrder.compactMap { childrenDict[$0] }
        if ordered.count == directChildren.count {
            return ordered
        }

        // If order metadata is stale, append untracked children deterministically.
        let trackedIDs = Set(ordered.map(\.id))
        let untracked = directChildren
            .filter { !trackedIDs.contains($0.id) }
            .sorted { $0.createdAt < $1.createdAt }
        return ordered + untracked
    }

    func nestingLevel(in noteIndex: [UUID: NoteBlock]) -> Int {
        var level = 0
        var currentID = parentNoteID
        var visited = Set<UUID>()
        while let nodeID = currentID, !visited.contains(nodeID) {
            visited.insert(nodeID)
            level += 1
            currentID = noteIndex[nodeID]?.parentNoteID
        }
        return level
    }

    /// Adds a child note under this node while preserving a stable order.
    @discardableResult
    func addChild(_ child: NoteBlock, at index: Int? = nil) throws -> Bool {
        guard child.id != id else { throw NoteHierarchyError.cannotParentSelf }
        guard child.pageVersionID == pageVersionID else { throw NoteHierarchyError.crossAnchorParenting }
        guard !containsAncestor(withID: child.id) else { throw NoteHierarchyError.circularReference }

        if child.parentNoteID == id {
            return false
        }

        if let previousParent = child.parent, previousParent.id != id {
            previousParent.removeChild(child)
        }

        child.parent = self
        child.parentNoteID = id

        // Child replies inherit the same anchor context as their parent.
        child.pageVersionID = pageVersionID
        child.pageVersion = pageVersion
        child.pageId = pageId
        child.docId = docId
        child.pdfBundleId = pdfBundleId
        child.pageIndexInBundle = pageIndexInBundle
        child.pageOrderIndex = pageOrderIndex

        if let index = index, index >= 0, index < childOrder.count {
            childOrder.insert(child.id, at: index)
        } else {
            childOrder.append(child.id)
        }

        child.touch()
        touch()
        return true
    }

    /// Removes a child note link from this parent.
    @discardableResult
    func removeChild(_ child: NoteBlock) -> Bool {
        guard child.parentNoteID == id else { return false }
        childOrder.removeAll { $0 == child.id }
        child.parent = nil
        child.parentNoteID = nil
        child.touch()
        touch()
        return true
    }

    /// Reorders existing children according to a new full-ID list.
    func reorderChildren(_ newOrder: [UUID], from notes: [NoteBlock]) throws {
        let currentIDs = Set(notes.filter { $0.parentNoteID == id }.map(\.id))
        guard currentIDs == Set(newOrder) else {
            throw NoteHierarchyError.invalidChildOrder
        }
        childOrder = newOrder
        touch()
    }

    /// Moves one child index to another index within the current ordering.
    func moveChild(from: Int, to: Int) {
        guard from >= 0, from < childOrder.count else { return }
        guard to >= 0, to <= childOrder.count else { return }
        let childID = childOrder.remove(at: from)
        let adjustedTo = to > from ? to - 1 : to
        childOrder.insert(childID, at: adjustedTo)
        touch()
    }

    /// Creates a detached reply note pre-populated with parent anchor context.
    func makeReply(title: String? = nil, body: String) -> NoteBlock {
        NoteBlock(
            pageVersionID: pageVersionID,
            pageVersion: pageVersion,
            pageId: pageId,
            docId: docId,
            pdfBundleId: pdfBundleId,
            pageIndexInBundle: pageIndexInBundle,
            pageOrderIndex: pageOrderIndex,
            verticalOrderHint: min(1.0, verticalOrderHint + 0.001 * Double(childOrder.count + 1)),
            rectX: rectX,
            rectY: rectY,
            rectWidth: rectWidth,
            rectHeight: rectHeight,
            title: title,
            body: body
        )
    }

    /// Returns this note and all descendants (preorder traversal).
    func flattenedThread(from notes: [NoteBlock]) -> [NoteBlock] {
        [self] + orderedChildren(from: notes).flatMap { $0.flattenedThread(from: notes) }
    }

    // MARK: - Cache Maintenance

    /// Recompute cached navigation fields using the current PageVersion relationship.
    /// Call after doc/page reordering to keep cached data aligned.
    func refreshCachedNavigation() {
        guard let pageVersion else { return }
        pageVersionID = pageVersion.id
        pageId = pageVersion.page?.id
        docId = pageVersion.page?.pageGroup?.doc?.id
        pdfBundleId = pageVersion.pdfBundleID
        pageIndexInBundle = max(pageVersion.pageNumber - 1, 0)
        pageOrderIndex = Self.computePageOrderIndex(for: pageVersion.page)
        verticalOrderHint = rectY
        touch()
        assertAnchorConsistency()
    }

    /// Update the modification timestamp
    func touch() {
        updatedAt = Date()
    }

    // MARK: - Validation

    /// Ensure in-memory anchor matches the stored ID
    func assertAnchorConsistency() {
        if let pageVersion {
            assert(pageVersion.id == pageVersionID, "NoteBlock.pageVersionID must match pageVersion.id")
        }

        if let parent {
            assert(parent.id == parentNoteID, "NoteBlock.parentNoteID must match parent.id")
            assert(parent.pageVersionID == pageVersionID, "Nested notes must share the same pageVersionID")
            assert(!containsAncestor(withID: id), "Circular note hierarchy detected")
        } else {
            assert(parentNoteID == nil, "Root note must not have parentNoteID")
        }
    }

    /// Validate normalized rectangle bounds
    func assertNormalizedRect() {
        assert((0.0...1.0).contains(rectX))
        assert((0.0...1.0).contains(rectY))
        assert((0.0...1.0).contains(rectWidth))
        assert((0.0...1.0).contains(rectHeight))
    }

    // MARK: - Helpers

    /// Normalize an absolute rect into [0, 1] coordinates (clamped)
    private static func normalizeRect(_ rect: CGRect, pageSize: CGSize) -> CGRect {
        guard pageSize.width > 0 && pageSize.height > 0 else { return .zero }

        let x = max(0, min(1, rect.origin.x / pageSize.width))
        let y = max(0, min(1, rect.origin.y / pageSize.height))
        let width = max(0, min(1, rect.size.width / pageSize.width))
        let height = max(0, min(1, rect.size.height / pageSize.height))
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Compute a stable page order index within a Doc, based on current ordering metadata.
    private static func computePageOrderIndex(for page: Page?) -> Int {
        guard let page, let pageGroup = page.pageGroup, let doc = pageGroup.doc else { return 0 }
        let orderedPages = doc.orderedPageGroups.flatMap { $0.orderedPages }
        if let index = orderedPages.firstIndex(where: { $0.id == page.id }) {
            return index
        }
        // Fallback: append to end
        return orderedPages.count
    }

    private func containsAncestor(withID id: UUID) -> Bool {
        var current = parent
        var visited = Set<UUID>()
        while let node = current, !visited.contains(node.id) {
            if node.id == id {
                return true
            }
            visited.insert(node.id)
            current = node.parent
        }
        return false
    }
}
