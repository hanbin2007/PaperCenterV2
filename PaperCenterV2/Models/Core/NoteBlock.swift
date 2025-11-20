//
//  NoteBlock.swift
//  PaperCenterV2
//
//  Created by zhb on 2026-02-02.
//

import Foundation
import CoreGraphics
import SwiftData

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

    // MARK: - Relationships

    /// Optional navigation to the anchored PageVersion (must match `pageVersionID` when present)
    @Relationship(deleteRule: .nullify)
    var pageVersion: PageVersion?

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
        isDeleted: Bool = false
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
}
