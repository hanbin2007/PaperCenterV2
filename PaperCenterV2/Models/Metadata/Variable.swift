//
//  Variable.swift
//  PaperCenterV2
//
//  Created by Claude on 2025-11-09.
//

import Foundation
import SwiftData

/// A typed, scoped field that can be attached to entities
///
/// Variables provide structured metadata fields with specific data types.
/// Examples: "Year" (int), "Difficulty" (list), "Score" (int)
@Model
final class Variable {
    // MARK: - Properties

    /// Unique identifier
    var id: UUID

    /// Variable name (e.g., "Year", "Score", "Difficulty")
    var name: String

    /// Data type of this variable
    var type: VariableType

    /// Scope defining which entity types can use this variable
    var scope: VariableScope

    /// Hex color code for visual representation (e.g., "#3B82F6")
    var color: String

    /// Predefined options for list type (nil for int type)
    /// Example: ["Easy", "Medium", "Hard"]
    var listOptions: [String]?

    /// System-managed creation timestamp
    var createdAt: Date

    /// System-managed update timestamp
    var updatedAt: Date

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        name: String,
        type: VariableType,
        scope: VariableScope = .all,
        color: String = "#8B5CF6", // Default purple color
        listOptions: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.scope = scope
        self.color = color
        self.listOptions = listOptions
        self.createdAt = Date()
        self.updatedAt = Date()

        // Validate that list type has options
        assert(type != .list || listOptions != nil, "List type variable must have listOptions")
    }

    // MARK: - Helper Methods

    /// Update the modification timestamp
    func touch() {
        self.updatedAt = Date()
    }

    /// Check if this variable can be applied to a specific entity type
    func canApply(to entityType: VariableEntityType) -> Bool {
        return scope.canApplyTo(entityType)
    }

    /// Validate a value for this variable
    func isValid(intValue: Int?) -> Bool {
        guard type == .int else { return false }
        return intValue != nil
    }

    /// Validate a list selection for this variable
    func isValid(listValue: String?) -> Bool {
        guard type == .list, let listValue = listValue else { return false }
        return listOptions?.contains(listValue) ?? false
    }
}
