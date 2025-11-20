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

    /// Manual sort index to control order in pickers and lists
    var sortIndex: Int

    /// Predefined options for list type (nil for other types)
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
        sortIndex: Int = 0,
        listOptions: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.scope = scope
        self.color = color
        self.sortIndex = sortIndex
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

    /// Validate free-form text input
    func isValid(textValue: String?) -> Bool {
        guard type == .text else { return false }
        let trimmed = textValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !trimmed.isEmpty
    }

    /// Validate a date input
    func isValid(dateValue: Date?) -> Bool {
        guard type == .date else { return false }
        return dateValue != nil
    }
}
