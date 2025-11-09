//
//  Doc.swift
//  PaperCenterV2
//
//  Created by Claude on 2025-11-09.
//

import Foundation
import SwiftData

/// Top-level logical container for organizing study materials
///
/// A Doc represents a complete collection of related materials, such as:
/// - A single exam paper
/// - Multiple related exams
/// - A custom collection of pages from various PDFBundles
@Model
final class Doc {
    // MARK: - Properties

    /// Unique identifier
    var id: UUID

    /// Document title (required, user-defined)
    var title: String

    /// System-managed creation timestamp
    var createdAt: Date

    /// System-managed update timestamp
    var updatedAt: Date

    /// Ordered array of PageGroup IDs for preserving group order
    var pageGroupOrder: [UUID]

    // MARK: - Relationships

    /// PageGroups in this document
    @Relationship(deleteRule: .cascade, inverse: \PageGroup.doc)
    var pageGroups: [PageGroup]?

    /// Tags applied to this document
    @Relationship(deleteRule: .nullify)
    var tags: [Tag]?

    /// Variable assignments for this document
    @Relationship(deleteRule: .cascade, inverse: \DocVariableAssignment.doc)
    var variableAssignments: [DocVariableAssignment]?

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        title: String
    ) {
        self.id = id
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
        self.pageGroupOrder = []
    }

    // MARK: - Helper Methods

    /// Update the modification timestamp
    func touch() {
        self.updatedAt = Date()
    }

    /// Add a page group to this document
    /// - Parameter pageGroup: PageGroup to add
    /// - Parameter at: Optional index to insert at (appends if nil)
    func addPageGroup(_ pageGroup: PageGroup, at index: Int? = nil) {
        // Ensure pageGroups array exists
        if pageGroups == nil {
            pageGroups = []
        }

        // Add the page group
        pageGroup.doc = self
        pageGroups?.append(pageGroup)

        // Update order
        if let index = index, index < pageGroupOrder.count {
            pageGroupOrder.insert(pageGroup.id, at: index)
        } else {
            pageGroupOrder.append(pageGroup.id)
        }

        touch()
    }

    /// Remove a page group from this document
    /// - Parameter pageGroup: PageGroup to remove
    func removePageGroup(_ pageGroup: PageGroup) {
        pageGroups?.removeAll { $0.id == pageGroup.id }
        pageGroupOrder.removeAll { $0 == pageGroup.id }
        touch()
    }

    /// Get page groups in the specified order
    var orderedPageGroups: [PageGroup] {
        guard let pageGroups = pageGroups else { return [] }

        // Create a dictionary for quick lookup
        let groupDict = Dictionary(uniqueKeysWithValues: pageGroups.map { ($0.id, $0) })

        // Return groups in the order specified by pageGroupOrder
        return pageGroupOrder.compactMap { groupDict[$0] }
    }

    /// Reorder page groups
    /// - Parameter newOrder: New array of PageGroup IDs in desired order
    func reorderPageGroups(_ newOrder: [UUID]) {
        // Validate that all IDs in newOrder exist in current page groups
        let currentGroupIDs = Set(pageGroups?.map { $0.id } ?? [])
        let newOrderSet = Set(newOrder)

        guard currentGroupIDs == newOrderSet else {
            print("Warning: PageGroup order mismatch. Some groups missing or extra in new order.")
            return
        }

        pageGroupOrder = newOrder
        touch()
    }

    /// Move a page group from one index to another
    /// - Parameters:
    ///   - from: Source index
    ///   - to: Destination index
    func movePageGroup(from: Int, to: Int) {
        guard from >= 0, from < pageGroupOrder.count,
              to >= 0, to <= pageGroupOrder.count else {
            return
        }

        let groupID = pageGroupOrder.remove(at: from)
        let adjustedTo = to > from ? to - 1 : to
        pageGroupOrder.insert(groupID, at: adjustedTo)
        touch()
    }

    /// Get all pages across all page groups (flattened)
    var allPages: [Page] {
        return orderedPageGroups.flatMap { $0.orderedPages }
    }

    /// Get total page count across all page groups
    var totalPageCount: Int {
        return pageGroups?.reduce(0) { $0 + ($1.pages?.count ?? 0) } ?? 0
    }

    /// Check if this document is empty (no page groups)
    var isEmpty: Bool {
        return pageGroups?.isEmpty ?? true
    }
}
