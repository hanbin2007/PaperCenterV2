//
//  DocListViewModel.swift
//  PaperCenterV2
//
//  Created by Claude on 2025-11-09.
//

import Foundation
import SwiftData

/// ViewModel for managing the Doc list
@MainActor
@Observable
final class DocListViewModel {

    // MARK: - Properties

    private let modelContext: ModelContext

    // MARK: - Initialization

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Doc Management

    /// Delete a Doc
    /// - Parameter doc: Doc to delete
    func deleteDoc(_ doc: Doc) {
        modelContext.delete(doc)
    }

    /// Format tags for display
    /// - Parameter tags: Tags to format
    /// - Returns: Grouped tags
    func formatTags(_ tags: [Tag]?) -> [(groupName: String, tags: [Tag])] {
        guard let tags = tags, !tags.isEmpty else { return [] }
        return MetadataFormattingService.groupTags(tags)
    }

    /// Format variables for display
    /// - Parameter assignments: Variable assignments to format
    /// - Returns: Formatted variables
    func formatVariables(_ assignments: [DocVariableAssignment]?) -> [FormattedVariable] {
        guard let assignments = assignments, !assignments.isEmpty else { return [] }
        return MetadataFormattingService.formatDocVariables(assignments)
    }
}
