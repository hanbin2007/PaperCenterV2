//
//  PageGroup.swift
//  PaperCenterV2
//
//  Created by Claude on 2025-11-09.
//

import Foundation
import SwiftData

/// An ordered collection of Pages within a Doc
///
/// PageGroups organize related pages into logical sections. Examples include:
/// grouping by section, question type, or topic within an exam.
@Model
final class PageGroup {
    // MARK: - Properties

    /// Unique identifier
    var id: UUID

    /// Group title (required, user-defined)
    var title: String

    /// System-managed creation timestamp
    var createdAt: Date

    /// System-managed update timestamp
    var updatedAt: Date

    /// Ordered array of Page IDs for preserving page order
    var pageOrder: [UUID]

    // MARK: - Relationships

    /// Pages in this group (exclusive ownership)
    @Relationship(deleteRule: .cascade, inverse: \Page.pageGroup)
    var pages: [Page]?

    /// Parent document (required)
    @Relationship(deleteRule: .nullify)
    var doc: Doc?

    /// Tags applied to this page group
    @Relationship(deleteRule: .nullify)
    var tags: [Tag]?

    /// Variable assignments for this page group
    @Relationship(deleteRule: .cascade, inverse: \PageGroupVariableAssignment.pageGroup)
    var variableAssignments: [PageGroupVariableAssignment]?

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        title: String,
        doc: Doc? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
        self.pageOrder = []
        self.doc = doc
    }

    // MARK: - Helper Methods

    /// Update the modification timestamp
    func touch() {
        self.updatedAt = Date()
    }

    /// Add a page to this group
    /// - Parameter page: Page to add
    /// - Parameter at: Optional index to insert at (appends if nil)
    func addPage(_ page: Page, at index: Int? = nil) {
        // Ensure pages array exists
        if pages == nil {
            pages = []
        }

        // Add the page
        page.pageGroup = self
        pages?.append(page)

        // Update order
        if let index = index, index < pageOrder.count {
            pageOrder.insert(page.id, at: index)
        } else {
            pageOrder.append(page.id)
        }

        touch()
    }

    /// Remove a page from this group
    /// - Parameter page: Page to remove
    func removePage(_ page: Page) {
        pages?.removeAll { $0.id == page.id }
        pageOrder.removeAll { $0 == page.id }
        touch()
    }

    /// Get pages in the specified order
    var orderedPages: [Page] {
        guard let pages = pages else { return [] }

        // Create a dictionary for quick lookup
        let pageDict = Dictionary(uniqueKeysWithValues: pages.map { ($0.id, $0) })

        // Return pages in the order specified by pageOrder
        return pageOrder.compactMap { pageDict[$0] }
    }

    /// Reorder pages
    /// - Parameter newOrder: New array of Page IDs in desired order
    func reorderPages(_ newOrder: [UUID]) {
        // Validate that all IDs in newOrder exist in current pages
        let currentPageIDs = Set(pages?.map { $0.id } ?? [])
        let newOrderSet = Set(newOrder)

        guard currentPageIDs == newOrderSet else {
            print("Warning: Page order mismatch. Some pages missing or extra in new order.")
            return
        }

        pageOrder = newOrder
        touch()
    }

    /// Move a page from one index to another
    /// - Parameters:
    ///   - from: Source index
    ///   - to: Destination index
    func movePage(from: Int, to: Int) {
        guard from >= 0, from < pageOrder.count,
              to >= 0, to <= pageOrder.count else {
            return
        }

        let pageID = pageOrder.remove(at: from)
        let adjustedTo = to > from ? to - 1 : to
        pageOrder.insert(pageID, at: adjustedTo)
        touch()
    }
}
