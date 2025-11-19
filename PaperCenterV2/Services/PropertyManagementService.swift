//
//  PropertyManagementService.swift
//  PaperCenterV2
//
//  Service for managing Tags, TagGroups, and Variables
//

import Foundation
import SwiftData

/// Errors that can occur during property management operations
enum PropertyManagementError: LocalizedError {
    case duplicateName(String)
    case invalidColor(String)
    case invalidListOptions
    case tagGroupHasTags
    case variableHasAssignments
    case invalidScope
    case notFound

    var errorDescription: String? {
        switch self {
        case .duplicateName(let name):
            return "A property with the name '\(name)' already exists"
        case .invalidColor(let color):
            return "Invalid hex color code: \(color)"
        case .invalidListOptions:
            return "List-type variables must have at least 2 options"
        case .tagGroupHasTags:
            return "Cannot delete tag group that contains tags"
        case .variableHasAssignments:
            return "Cannot delete variable that has existing assignments"
        case .invalidScope:
            return "Invalid scope for this operation"
        case .notFound:
            return "Property not found"
        }
    }
}

/// Service for managing tags, tag groups, and variables
@MainActor
final class PropertyManagementService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - TagGroup Operations

    /// Fetch all tag groups
    func fetchAllTagGroups() throws -> [TagGroup] {
        let descriptor = FetchDescriptor<TagGroup>()
        let groups = try modelContext.fetch(descriptor)
        return groups.sortedByManualOrder()
    }

    /// Fetch a specific tag group by ID
    func fetchTagGroup(id: UUID) throws -> TagGroup? {
        let descriptor = FetchDescriptor<TagGroup>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    /// Create a new tag group
    func createTagGroup(name: String) throws -> TagGroup {
        // Validate name uniqueness
        try validateTagGroupNameUnique(name)

        let sortIndex = try nextTagGroupSortIndex()
        let tagGroup = TagGroup(name: name, sortIndex: sortIndex)
        modelContext.insert(tagGroup)
        try modelContext.save()
        return tagGroup
    }

    /// Update an existing tag group
    func updateTagGroup(_ tagGroup: TagGroup, name: String) throws {
        // Validate name uniqueness if changed
        if tagGroup.name != name {
            try validateTagGroupNameUnique(name)
        }

        tagGroup.name = name
        tagGroup.touch()
        try modelContext.save()
    }

    /// Delete a tag group (only if it has no tags)
    func deleteTagGroup(_ tagGroup: TagGroup) throws {
        // Check if tag group has any tags
        if let tags = tagGroup.tags, !tags.isEmpty {
            throw PropertyManagementError.tagGroupHasTags
        }

        modelContext.delete(tagGroup)
        try modelContext.save()
    }

    /// Batch delete tag groups (only those without tags)
    func batchDeleteTagGroups(_ tagGroups: [TagGroup]) throws {
        var deletedCount = 0
        var errors: [String] = []

        for tagGroup in tagGroups {
            do {
                try deleteTagGroup(tagGroup)
                deletedCount += 1
            } catch {
                errors.append("'\(tagGroup.name)': \(error.localizedDescription)")
            }
        }

        if !errors.isEmpty {
            print("Batch delete completed with errors: \(errors.joined(separator: ", "))")
        }
    }

    // MARK: - Tag Operations

    /// Fetch all tags
    func fetchAllTags() throws -> [Tag] {
        let descriptor = FetchDescriptor<Tag>()
        let tags = try modelContext.fetch(descriptor)
        return tags.sortedByManualOrder()
    }

    /// Fetch tags by scope
    func fetchTags(byScope scope: TagScope) throws -> [Tag] {
        let descriptor = FetchDescriptor<Tag>(
            predicate: #Predicate { $0.scope == scope }
        )
        let tags = try modelContext.fetch(descriptor)
        return tags.sortedByManualOrder()
    }

    /// Fetch tags by tag group
    func fetchTags(byGroup tagGroup: TagGroup) throws -> [Tag] {
        return (tagGroup.tags ?? []).sortedByManualOrder()
    }

    /// Fetch a specific tag by ID
    func fetchTag(id: UUID) throws -> Tag? {
        let descriptor = FetchDescriptor<Tag>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    /// Create a new tag
    func createTag(
        name: String,
        color: String = "#3B82F6",
        scope: TagScope = .all,
        tagGroup: TagGroup? = nil
    ) throws -> Tag {
        // Validate name uniqueness
        try validateTagNameUnique(name)

        // Validate color format
        try validateHexColor(color)

        let sortIndex = try nextTagSortIndex(in: tagGroup)
        let tag = Tag(
            name: name,
            color: color,
            scope: scope,
            tagGroup: tagGroup,
            sortIndex: sortIndex
        )

        modelContext.insert(tag)
        try modelContext.save()
        return tag
    }

    /// Update an existing tag
    func updateTag(
        _ tag: Tag,
        name: String? = nil,
        color: String? = nil,
        scope: TagScope? = nil,
        tagGroup: TagGroup? = nil
    ) throws {
        // Validate name uniqueness if changed
        if let name = name, tag.name != name {
            try validateTagNameUnique(name)
            tag.name = name
        }

        // Validate color format if changed
        if let color = color {
            try validateHexColor(color)
            tag.color = color
        }

        if let scope = scope {
            tag.scope = scope
        }

        if let tagGroup = tagGroup {
            let movedToDifferentGroup = tag.tagGroup?.id != tagGroup.id
            tag.tagGroup = tagGroup
            if movedToDifferentGroup {
                tag.sortIndex = try nextTagSortIndex(in: tagGroup)
            }
        } else if tag.tagGroup != nil {
            // Moving to ungrouped bucket, append to the end there
            tag.tagGroup = nil
            tag.sortIndex = try nextTagSortIndex(in: nil)
        }

        tag.touch()
        try modelContext.save()
    }

    /// Delete a tag
    func deleteTag(_ tag: Tag) throws {
        modelContext.delete(tag)
        try modelContext.save()
    }

    /// Batch delete tags
    func batchDeleteTags(_ tags: [Tag]) throws {
        for tag in tags {
            modelContext.delete(tag)
        }
        try modelContext.save()
    }

    /// Batch update tags (color or scope)
    func batchUpdateTags(_ tags: [Tag], color: String? = nil, scope: TagScope? = nil) throws {
        if let color = color {
            try validateHexColor(color)
        }

        for tag in tags {
            if let color = color {
                tag.color = color
            }
            if let scope = scope {
                tag.scope = scope
            }
            tag.touch()
        }

        try modelContext.save()
    }

    /// Bulk create tags in a group
    func bulkCreateTags(names: [String], tagGroup: TagGroup, color: String = "#3B82F6", scope: TagScope = .all) throws -> [Tag] {
        try validateHexColor(color)

        var createdTags: [Tag] = []

        var nextIndex = try nextTagSortIndex(in: tagGroup)
        for name in names {
            // Skip duplicates silently
            if (try? validateTagNameUnique(name)) != nil {
                let tag = Tag(
                    name: name,
                    color: color,
                    scope: scope,
                    tagGroup: tagGroup,
                    sortIndex: nextIndex
                )
                nextIndex += 1
                modelContext.insert(tag)
                createdTags.append(tag)
            }
        }

        try modelContext.save()
        return createdTags
    }

    // MARK: - Variable Operations

    /// Fetch all variables
    func fetchAllVariables() throws -> [Variable] {
        let descriptor = FetchDescriptor<Variable>()
        let variables = try modelContext.fetch(descriptor)
        return variables.sortedByManualOrder()
    }

    /// Fetch variables by scope
    func fetchVariables(byScope scope: VariableScope) throws -> [Variable] {
        let descriptor = FetchDescriptor<Variable>(
            predicate: #Predicate { $0.scope == scope }
        )
        let variables = try modelContext.fetch(descriptor)
        return variables.sortedByManualOrder()
    }

    /// Fetch variables by type
    func fetchVariables(byType type: VariableType) throws -> [Variable] {
        let descriptor = FetchDescriptor<Variable>(
            predicate: #Predicate { $0.type == type }
        )
        let variables = try modelContext.fetch(descriptor)
        return variables.sortedByManualOrder()
    }

    /// Fetch a specific variable by ID
    func fetchVariable(id: UUID) throws -> Variable? {
        let descriptor = FetchDescriptor<Variable>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    /// Create a new variable
    func createVariable(
        name: String,
        type: VariableType,
        scope: VariableScope = .all,
        color: String = "#8B5CF6",
        listOptions: [String]? = nil
    ) throws -> Variable {
        // Validate name uniqueness
        try validateVariableNameUnique(name)

        // Validate color format
        try validateHexColor(color)

        // Validate list options for list type
        if type == .list {
            try validateListOptions(listOptions)
        }

        let sortIndex = try nextVariableSortIndex()
        let variable = Variable(
            name: name,
            type: type,
            scope: scope,
            color: color,
            sortIndex: sortIndex,
            listOptions: listOptions
        )

        modelContext.insert(variable)
        try modelContext.save()
        return variable
    }

    /// Update an existing variable
    func updateVariable(
        _ variable: Variable,
        name: String? = nil,
        scope: VariableScope? = nil,
        color: String? = nil,
        listOptions: [String]? = nil
    ) throws {
        // Validate name uniqueness if changed
        if let name = name, variable.name != name {
            try validateVariableNameUnique(name)
            variable.name = name
        }

        if let scope = scope {
            variable.scope = scope
        }

        // Validate and update color if changed
        if let color = color {
            try validateHexColor(color)
            variable.color = color
        }

        // Update list options if provided (only for list type)
        if let listOptions = listOptions {
            guard variable.type == .list else {
                throw PropertyManagementError.invalidListOptions
            }
            try validateListOptions(listOptions)
            variable.listOptions = listOptions
        }

        variable.touch()
        try modelContext.save()
    }

    /// Delete a variable (only if it has no assignments)
    func deleteVariable(_ variable: Variable) throws {
        // Check if variable has any assignments
        if try hasAssignments(variable) {
            throw PropertyManagementError.variableHasAssignments
        }

        modelContext.delete(variable)
        try modelContext.save()
    }

    /// Batch delete variables (only those without assignments)
    func batchDeleteVariables(_ variables: [Variable]) throws {
        var deletedCount = 0
        var errors: [String] = []

        for variable in variables {
            do {
                try deleteVariable(variable)
                deletedCount += 1
            } catch {
                errors.append("'\(variable.name)': \(error.localizedDescription)")
            }
        }

        if !errors.isEmpty {
            print("Batch delete completed with errors: \(errors.joined(separator: ", "))")
        }
    }

    // MARK: - Ordering Helpers

    private func nextTagGroupSortIndex() throws -> Int {
        let groups = try modelContext.fetch(FetchDescriptor<TagGroup>())
        let maxIndex = groups.map(\.sortIndex).max() ?? -1
        return maxIndex + 1
    }

    private func nextTagSortIndex(in tagGroup: TagGroup?) throws -> Int {
        if let tagGroup {
            let tags = tagGroup.tags ?? []
            let maxIndex = tags.map(\.sortIndex).max() ?? -1
            return maxIndex + 1
        } else {
            let ungrouped = try modelContext.fetch(
                FetchDescriptor<Tag>(
                    predicate: #Predicate { $0.tagGroup == nil }
                )
            )
            let maxIndex = ungrouped.map(\.sortIndex).max() ?? -1
            return maxIndex + 1
        }
    }

    private func nextVariableSortIndex() throws -> Int {
        let variables = try modelContext.fetch(FetchDescriptor<Variable>())
        let maxIndex = variables.map(\.sortIndex).max() ?? -1
        return maxIndex + 1
    }

    // MARK: - Validation Helpers

    private func validateTagGroupNameUnique(_ name: String) throws {
        let descriptor = FetchDescriptor<TagGroup>(
            predicate: #Predicate { $0.name.localizedStandardContains(name) }
        )
        let existing = try modelContext.fetch(descriptor)
        if existing.contains(where: { $0.name.lowercased() == name.lowercased() }) {
            throw PropertyManagementError.duplicateName(name)
        }
    }

    private func validateTagNameUnique(_ name: String) throws {
        let descriptor = FetchDescriptor<Tag>(
            predicate: #Predicate { $0.name.localizedStandardContains(name) }
        )
        let existing = try modelContext.fetch(descriptor)
        if existing.contains(where: { $0.name.lowercased() == name.lowercased() }) {
            throw PropertyManagementError.duplicateName(name)
        }
    }

    private func validateVariableNameUnique(_ name: String) throws {
        let descriptor = FetchDescriptor<Variable>(
            predicate: #Predicate { $0.name.localizedStandardContains(name) }
        )
        let existing = try modelContext.fetch(descriptor)
        if existing.contains(where: { $0.name.lowercased() == name.lowercased() }) {
            throw PropertyManagementError.duplicateName(name)
        }
    }

    private func validateHexColor(_ color: String) throws {
        let hexPattern = "^#([A-Fa-f0-9]{6})$"
        let regex = try? NSRegularExpression(pattern: hexPattern)
        let range = NSRange(location: 0, length: color.utf16.count)

        if regex?.firstMatch(in: color, range: range) == nil {
            throw PropertyManagementError.invalidColor(color)
        }
    }

    private func validateListOptions(_ listOptions: [String]?) throws {
        guard let options = listOptions, options.count >= 2 else {
            throw PropertyManagementError.invalidListOptions
        }
    }

    private func hasAssignments(_ variable: Variable) throws -> Bool {
        let variableID = variable.id

        // Check all four assignment types
        // Note: We fetch all and filter because optional chaining in predicates is not fully supported
        let pdfBundleDescriptor = FetchDescriptor<PDFBundleVariableAssignment>()
        let pdfBundleAssignments = try modelContext.fetch(pdfBundleDescriptor)
        if pdfBundleAssignments.contains(where: { $0.variable?.id == variableID }) {
            return true
        }

        let docDescriptor = FetchDescriptor<DocVariableAssignment>()
        let docAssignments = try modelContext.fetch(docDescriptor)
        if docAssignments.contains(where: { $0.variable?.id == variableID }) {
            return true
        }

        let pageGroupDescriptor = FetchDescriptor<PageGroupVariableAssignment>()
        let pageGroupAssignments = try modelContext.fetch(pageGroupDescriptor)
        if pageGroupAssignments.contains(where: { $0.variable?.id == variableID }) {
            return true
        }

        let pageDescriptor = FetchDescriptor<PageVariableAssignment>()
        let pageAssignments = try modelContext.fetch(pageDescriptor)
        if pageAssignments.contains(where: { $0.variable?.id == variableID }) {
            return true
        }

        return false
    }
}
