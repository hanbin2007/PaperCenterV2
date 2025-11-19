//
//  TagScope.swift
//  PaperCenterV2
//
//  Created by Claude on 2025-11-09.
//

import Foundation

/// Defines which entity types a Tag can be applied to
enum TagScope: String, Codable, CaseIterable {
    case pdfBundle = "pdfBundle"
    case doc = "doc"
    case pageGroup = "pageGroup"
    case page = "page"
    case noteBlock = "noteBlock"
    case docAndBelow = "docAndBelow"  // Doc, PageGroup, Page
    case all = "all"                   // All entities

    /// Check if this scope allows tagging the given entity type
    func canTag(_ entityType: TaggableEntityType) -> Bool {
        switch self {
        case .pdfBundle:
            return entityType == .pdfBundle
        case .doc:
            return entityType == .doc
        case .pageGroup:
            return entityType == .pageGroup
        case .page:
            return entityType == .page
        case .noteBlock:
            return entityType == .noteBlock
        case .docAndBelow:
            return entityType == .doc || entityType == .pageGroup || entityType == .page
        case .all:
            return true
        }
    }
}

/// Entity types that can be tagged
enum TaggableEntityType {
    case pdfBundle
    case doc
    case pageGroup
    case page
    case noteBlock
}
