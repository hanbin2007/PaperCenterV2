//
//  PageVersion.swift
//  PaperCenterV2
//
//  Created by Claude on 2025-11-09.
//

import Foundation
import SwiftData

/// Immutable snapshot of a Page at a point in time
///
/// PageVersions maintain a complete history of changes to which PDFBundle/page
/// a Page references. Metadata snapshots are independent of current Page metadata.
@Model
final class PageVersion {
    // MARK: - Properties

    /// Unique identifier
    var id: UUID

    /// Version creation timestamp
    var createdAt: Date

    /// PDFBundle ID at this version
    var pdfBundleID: UUID

    /// Page number within the bundle at this version (1-based)
    var pageNumber: Int

    /// Encoded snapshot of tags and variables at version creation
    /// This is a JSON-encoded representation of the metadata state
    var metadataSnapshot: Data?

    // MARK: - Relationships

    /// Parent page that owns this version
    @Relationship(deleteRule: .nullify)
    var page: Page?

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        pdfBundleID: UUID,
        pageNumber: Int,
        metadataSnapshot: Data? = nil
    ) {
        self.id = id
        self.createdAt = Date()
        self.pdfBundleID = pdfBundleID
        self.pageNumber = pageNumber
        self.metadataSnapshot = metadataSnapshot
    }

    // MARK: - Helper Methods

    /// Create metadata snapshot from current Page state
    static func createMetadataSnapshot(
        tags: [Tag]?,
        variableAssignments: [PageVariableAssignment]?
    ) throws -> Data {
        let snapshot = MetadataSnapshot(
            tagIDs: tags?.map { $0.id } ?? [],
            variableAssignments: variableAssignments?.map { assignment in
                VariableAssignmentSnapshot(
                    variableID: assignment.variable?.id ?? UUID(),
                    intValue: assignment.intValue,
                    listValue: assignment.listValue,
                    textValue: assignment.textValue,
                    dateValue: assignment.dateValue
                )
            } ?? []
        )
        return try JSONEncoder().encode(snapshot)
    }

    /// Decode metadata snapshot
    func decodeMetadataSnapshot() throws -> MetadataSnapshot? {
        guard let data = metadataSnapshot else { return nil }
        return try JSONDecoder().decode(MetadataSnapshot.self, from: data)
    }
}

// MARK: - Supporting Types

/// Codable representation of metadata at a point in time
struct MetadataSnapshot: Codable {
    /// IDs of tags that were applied
    let tagIDs: [UUID]

    /// Variable assignments that existed
    let variableAssignments: [VariableAssignmentSnapshot]
}

/// Codable representation of a variable assignment
struct VariableAssignmentSnapshot: Codable {
    /// Variable ID
    let variableID: UUID

    /// Integer value (for int type)
    let intValue: Int?

    /// List selection (for list type)
    let listValue: String?

    /// Text value (for text type)
    let textValue: String?

    /// Date value (for date type)
    let dateValue: Date?
}
