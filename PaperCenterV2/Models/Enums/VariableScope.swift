//
//  VariableScope.swift
//  PaperCenterV2
//
//  Created by Claude on 2025-11-09.
//

import Foundation

/// Defines which entity types a Variable can be applied to
enum VariableScope: String, Codable, CaseIterable {
    case pdfBundle = "pdfBundle"
    case doc = "doc"
    case pageGroup = "pageGroup"
    case page = "page"
    case noteBlock = "noteBlock"
    case all = "all"

    /// Check if this scope allows this variable on the given entity type
    func canApplyTo(_ entityType: VariableEntityType) -> Bool {
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
        case .all:
            return true
        }
    }
}

/// Entity types that can have variables
enum VariableEntityType {
    case pdfBundle
    case doc
    case pageGroup
    case page
    case noteBlock
}
