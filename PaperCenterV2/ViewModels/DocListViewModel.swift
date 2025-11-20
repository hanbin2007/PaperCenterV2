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

    /// Duplicate a doc, including its page structure and metadata
    func duplicateDoc(_ doc: Doc) throws {
        let newTitle = "\(doc.title) Copy"
        let duplicate = Doc(title: newTitle)
        duplicate.tags = doc.tags

        if let assignments = doc.variableAssignments {
            duplicate.variableAssignments = assignments.compactMap { assignment in
                guard let variable = assignment.variable else { return nil }
                return DocVariableAssignment(
                    variable: variable,
                    doc: duplicate,
                    intValue: assignment.intValue,
                    listValue: assignment.listValue
                )
            }
        }

        modelContext.insert(duplicate)

        for group in doc.orderedPageGroups {
            let clonedGroup = PageGroup(title: group.title)
            clonedGroup.tags = group.tags
            duplicate.addPageGroup(clonedGroup)

            if let assignments = group.variableAssignments {
                clonedGroup.variableAssignments = assignments.compactMap { assignment in
                    guard let variable = assignment.variable else { return nil }
                    return PageGroupVariableAssignment(
                        variable: variable,
                        pageGroup: clonedGroup,
                        intValue: assignment.intValue,
                        listValue: assignment.listValue
                    )
                }
            }

            for page in group.orderedPages {
                guard let bundle = page.pdfBundle else { continue }
                let clonedPage = Page(pdfBundle: bundle, pageNumber: page.currentPageNumber)
                clonedPage.tags = page.tags
                if let assignments = page.variableAssignments {
                    clonedPage.variableAssignments = assignments.compactMap { assignment in
                        guard let variable = assignment.variable else { return nil }
                        return PageVariableAssignment(
                            variable: variable,
                            page: clonedPage,
                            intValue: assignment.intValue,
                            listValue: assignment.listValue
                        )
                    }
                }
                clonedGroup.addPage(clonedPage)
            }
        }

        try modelContext.save()
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
