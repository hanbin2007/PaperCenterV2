//
//  TagGroup.swift
//  PaperCenterV2
//
//  Created by Claude on 2025-11-09.
//

import Foundation
import SwiftData

/// A named group of tags for organizing metadata
///
/// TagGroups provide a way to categorize tags into logical groups.
/// Examples: "Subject", "Difficulty", "Source", "Year"
@Model
final class TagGroup {
    // MARK: - Properties

    /// Unique identifier
    var id: UUID

    /// Group name (e.g., "Subject", "Difficulty")
    var name: String

    /// Manual sort index for user-defined ordering (lower values appear first)
    var sortIndex: Int

    /// System-managed creation timestamp
    var createdAt: Date

    /// System-managed update timestamp
    var updatedAt: Date

    // MARK: - Relationships

    /// Tags belonging to this group
    @Relationship(deleteRule: .cascade, inverse: \Tag.tagGroup)
    var tags: [Tag]?

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        name: String,
        sortIndex: Int = 0
    ) {
        self.id = id
        self.name = name
        self.sortIndex = sortIndex
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // MARK: - Helper Methods

    /// Update the modification timestamp
    func touch() {
        self.updatedAt = Date()
    }
}
