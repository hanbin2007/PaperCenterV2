//
//  Page.swift
//  PaperCenterV2
//
//  Created by Claude on 2025-11-09.
//

import Foundation
import SwiftData

/// A logical unit referring to exactly one page within one PDFBundle
///
/// Pages maintain version history, tracking changes to their PDFBundle reference
/// and page number. Each Page belongs exclusively to one PageGroup.
@Model
final class Page {
    // MARK: - Properties

    /// Unique identifier
    var id: UUID

    /// System-managed creation timestamp
    var createdAt: Date

    /// System-managed update timestamp
    var updatedAt: Date

    /// Current PDFBundle ID reference (for versioning comparison)
    var currentPDFBundleID: UUID

    /// Current page number within the bundle (1-based)
    var currentPageNumber: Int

    // MARK: - Relationships

    /// Current PDFBundle reference
    @Relationship(deleteRule: .nullify)
    var pdfBundle: PDFBundle?

    /// Parent PageGroup (required, exclusive ownership)
    @Relationship(deleteRule: .nullify)
    var pageGroup: PageGroup?

    /// Version history
    @Relationship(deleteRule: .cascade, inverse: \PageVersion.page)
    var versions: [PageVersion]?

    /// Tags applied to this page
    @Relationship(deleteRule: .nullify)
    var tags: [Tag]?

    /// Variable assignments for this page
    @Relationship(deleteRule: .cascade, inverse: \PageVariableAssignment.page)
    var variableAssignments: [PageVariableAssignment]?

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        pdfBundle: PDFBundle,
        pageNumber: Int,
        pageGroup: PageGroup? = nil
    ) {
        self.id = id
        self.createdAt = Date()
        self.updatedAt = Date()
        self.currentPDFBundleID = pdfBundle.id
        self.currentPageNumber = pageNumber
        self.pdfBundle = pdfBundle
        self.pageGroup = pageGroup

        // Create initial version
        let initialVersion = PageVersion(
            pdfBundleID: pdfBundle.id,
            pageNumber: pageNumber,
            metadataSnapshot: nil
        )
        initialVersion.page = self
        self.versions = [initialVersion]
    }

    // MARK: - Helper Methods

    /// Update the modification timestamp
    func touch() {
        self.updatedAt = Date()
    }

    /// Update the page reference, creating a new version if needed
    /// - Parameters:
    ///   - newBundle: New PDFBundle to reference
    ///   - newPageNumber: New page number within the bundle
    /// - Returns: True if a new version was created
    @discardableResult
    @MainActor
    func updateReference(to newBundle: PDFBundle, pageNumber newPageNumber: Int) -> Bool {
        // Check if this is actually a change
        let bundleChanged = newBundle.id != currentPDFBundleID
        let pageNumberChanged = newPageNumber != currentPageNumber

        guard bundleChanged || pageNumberChanged else {
            return false // No change, no new version needed
        }

        // Create metadata snapshot
        let snapshot = try? PageVersion.createMetadataSnapshot(
            tags: tags,
            variableAssignments: variableAssignments
        )

        // Create new version
        let newVersion = PageVersion(
            pdfBundleID: newBundle.id,
            pageNumber: newPageNumber,
            metadataSnapshot: snapshot
        )
        newVersion.page = self

        // Update current state
        self.pdfBundle = newBundle
        self.currentPDFBundleID = newBundle.id
        self.currentPageNumber = newPageNumber

        // Add to version history
        if versions == nil {
            versions = []
        }
        versions?.append(newVersion)

        touch()
        return true
    }

    /// Get the version history sorted by creation date (newest first)
    var sortedVersions: [PageVersion] {
        return versions?.sorted { $0.createdAt > $1.createdAt } ?? []
    }

    /// Get the most recent version (should match current state)
    var latestVersion: PageVersion? {
        return sortedVersions.first
    }

    /// Get OCR text for the current page (if available)
    var ocrText: String? {
        return pdfBundle?.ocrTextByPage[currentPageNumber]
    }
}
