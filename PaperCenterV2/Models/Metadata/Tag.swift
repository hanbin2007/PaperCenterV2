//
//  Tag.swift
//  PaperCenterV2
//
//  Created by Claude on 2025-11-09.
//

import Foundation
import SwiftData

/// A tag that can be applied to entities for categorization and metadata
///
/// Tags provide flexible categorization with scope-based access control.
/// Example tags: "Mathematics", "Hard", "2023 Finals"
@Model
final class Tag {
    // MARK: - Properties

    /// Unique identifier
    var id: UUID

    /// Tag name (e.g., "Mathematics", "Hard")
    var name: String

    /// Hex color code for visual representation (e.g., "#FF5733")
    var color: String

    /// Scope defining which entity types can use this tag
    var scope: TagScope

    /// System-managed creation timestamp
    var createdAt: Date

    /// System-managed update timestamp
    var updatedAt: Date

    // MARK: - Relationships

    /// Parent tag group
    @Relationship(deleteRule: .nullify)
    var tagGroup: TagGroup?

    /// PDFBundles tagged with this tag
    @Relationship(inverse: \PDFBundle.tags)
    var pdfBundles: [PDFBundle]?

    /// Docs tagged with this tag
    @Relationship(inverse: \Doc.tags)
    var docs: [Doc]?

    /// PageGroups tagged with this tag
    @Relationship(inverse: \PageGroup.tags)
    var pageGroups: [PageGroup]?

    /// Pages tagged with this tag
    @Relationship(inverse: \Page.tags)
    var pages: [Page]?

    /// NoteBlocks tagged with this tag
    @Relationship(inverse: \NoteBlock.tags)
    var noteBlocks: [NoteBlock]?

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        name: String,
        color: String = "#3B82F6", // Default blue color
        scope: TagScope = .all,
        tagGroup: TagGroup? = nil
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.scope = scope
        self.createdAt = Date()
        self.updatedAt = Date()
        self.tagGroup = tagGroup
    }

    // MARK: - Helper Methods

    /// Update the modification timestamp
    func touch() {
        self.updatedAt = Date()
    }

    /// Check if this tag can be applied to a specific entity type
    func canApply(to entityType: TaggableEntityType) -> Bool {
        return scope.canTag(entityType)
    }
}
