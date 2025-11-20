//
//  PropertyManagementViewModel.swift
//  PaperCenterV2
//
//  ViewModel for managing tags, tag groups, and variables
//

import Foundation
import SwiftData
import SwiftUI

/// ViewModel for coordinating all property management operations
@MainActor
@Observable
final class PropertyManagementViewModel {

    // MARK: - Properties

    private let modelContext: ModelContext
    private let service: PropertyManagementService
    private weak var assignmentViewModel: TagVariableAssignmentViewModel?

    /// Current error message to display
    var errorMessage: String?

    /// Success message to display
    var successMessage: String?

    /// Loading state
    var isLoading: Bool = false

    /// Search query for filtering
    var searchQuery: String = ""

    /// Current filter scope for tags
    var tagFilterScope: TagScope?

    /// Current filter scope for variables
    var variableFilterScope: VariableScope?

    /// Current filter type for variables
    var variableFilterType: VariableType?

    // MARK: - Initialization

    init(modelContext: ModelContext, assignmentViewModel: TagVariableAssignmentViewModel? = nil) {
        self.modelContext = modelContext
        self.service = PropertyManagementService(modelContext: modelContext)
        self.assignmentViewModel = assignmentViewModel
    }

    // MARK: - TagGroup Operations

    func fetchAllTagGroups() -> [TagGroup] {
        do {
            let tagGroups = try service.fetchAllTagGroups()
            return filterTagGroups(tagGroups)
        } catch {
            handleError(error)
            return []
        }
    }

    func createTagGroup(name: String) {
        guard !name.isEmpty else {
            errorMessage = "Tag group name cannot be empty"
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            _ = try service.createTagGroup(name: name)
            successMessage = "Tag group '\(name)' created successfully"
        } catch {
            handleError(error)
        }
    }

    func updateTagGroup(_ tagGroup: TagGroup, name: String) {
        guard !name.isEmpty else {
            errorMessage = "Tag group name cannot be empty"
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            try service.updateTagGroup(tagGroup, name: name)
            successMessage = "Tag group updated successfully"
        } catch {
            handleError(error)
        }
    }

    func deleteTagGroup(_ tagGroup: TagGroup) {
        isLoading = true
        defer { isLoading = false }

        do {
            try service.deleteTagGroup(tagGroup)
            successMessage = "Tag group deleted successfully"
        } catch {
            handleError(error)
        }
    }

    func batchDeleteTagGroups(_ tagGroups: [TagGroup]) {
        guard !tagGroups.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            try service.batchDeleteTagGroups(tagGroups)
            successMessage = "Deleted \(tagGroups.count) tag group(s)"
        } catch {
            handleError(error)
        }
    }

    func refreshAssignmentState() {
        assignmentViewModel?.refresh()
    }

    func reorderTagGroups(_ orderedGroups: [TagGroup]) {
        guard !orderedGroups.isEmpty else { return }
        do {
            try service.reorderTagGroups(orderedGroups)
        } catch {
            handleError(error)
        }
    }

    func duplicateTagGroup(_ tagGroup: TagGroup) {
        do {
            _ = try service.duplicateTagGroup(tagGroup)
            successMessage = "Duplicated '\(tagGroup.name)'"
        } catch {
            handleError(error)
        }
    }

    // MARK: - Tag Operations

    func fetchAllTags() -> [Tag] {
        do {
            let tags: [Tag]
            if let scope = tagFilterScope {
                tags = try service.fetchTags(byScope: scope)
            } else {
                tags = try service.fetchAllTags()
            }
            return filterTags(tags)
        } catch {
            handleError(error)
            return []
        }
    }

    func fetchTags(byGroup tagGroup: TagGroup) -> [Tag] {
        do {
            let tags = try service.fetchTags(byGroup: tagGroup)
            return filterTags(tags)
        } catch {
            handleError(error)
            return []
        }
    }

    func createTag(name: String, color: String, scope: TagScope, tagGroup: TagGroup?) {
        guard !name.isEmpty else {
            errorMessage = "Tag name cannot be empty"
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            _ = try service.createTag(name: name, color: color, scope: scope, tagGroup: tagGroup)
            successMessage = "Tag '\(name)' created successfully"
        } catch {
            handleError(error)
        }
    }

    func updateTag(
        _ tag: Tag,
        name: String? = nil,
        color: String? = nil,
        scope: TagScope? = nil,
        tagGroup: TagGroup? = nil
    ) {
        isLoading = true
        defer { isLoading = false }

        do {
            try service.updateTag(tag, name: name, color: color, scope: scope, tagGroup: tagGroup)
            successMessage = "Tag updated successfully"
        } catch {
            handleError(error)
        }
    }

    func deleteTag(_ tag: Tag) {
        isLoading = true
        defer { isLoading = false }

        do {
            try service.deleteTag(tag)
            successMessage = "Tag deleted successfully"
        } catch {
            handleError(error)
        }
    }

    func batchDeleteTags(_ tags: [Tag]) {
        guard !tags.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            try service.batchDeleteTags(tags)
            successMessage = "Deleted \(tags.count) tag(s)"
        } catch {
            handleError(error)
        }
    }

    func reorderTags(in tagGroup: TagGroup?, orderedTags: [Tag]) {
        guard !orderedTags.isEmpty else { return }
        do {
            try service.reorderTags(orderedTags, tagGroup: tagGroup)
        } catch {
            handleError(error)
        }
    }

    func batchUpdateTags(_ tags: [Tag], color: String? = nil, scope: TagScope? = nil) {
        guard !tags.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            try service.batchUpdateTags(tags, color: color, scope: scope)
            successMessage = "Updated \(tags.count) tag(s)"
        } catch {
            handleError(error)
        }
    }

    func bulkCreateTags(names: [String], tagGroup: TagGroup, color: String, scope: TagScope) {
        guard !names.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let created = try service.bulkCreateTags(names: names, tagGroup: tagGroup, color: color, scope: scope)
            successMessage = "Created \(created.count) tag(s)"
        } catch {
            handleError(error)
        }
    }

    // MARK: - Variable Operations

    func fetchAllVariables() -> [Variable] {
        do {
            var variables: [Variable]

            // Apply scope filter
            if let scope = variableFilterScope {
                variables = try service.fetchVariables(byScope: scope)
            } else if let type = variableFilterType {
                variables = try service.fetchVariables(byType: type)
            } else {
                variables = try service.fetchAllVariables()
            }

            return filterVariables(variables)
        } catch {
            handleError(error)
            return []
        }
    }

    func createVariable(name: String, type: VariableType, scope: VariableScope, color: String, listOptions: [String]?) {
        guard !name.isEmpty else {
            errorMessage = "Variable name cannot be empty"
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            _ = try service.createVariable(name: name, type: type, scope: scope, color: color, listOptions: listOptions)
            successMessage = "Variable '\(name)' created successfully"
        } catch {
            handleError(error)
        }
    }

    func updateVariable(
        _ variable: Variable,
        name: String? = nil,
        scope: VariableScope? = nil,
        color: String? = nil,
        listOptions: [String]? = nil
    ) {
        isLoading = true
        defer { isLoading = false }

        do {
            try service.updateVariable(variable, name: name, scope: scope, color: color, listOptions: listOptions)
            successMessage = "Variable updated successfully"
        } catch {
            handleError(error)
        }
    }

    func deleteVariable(_ variable: Variable) {
        isLoading = true
        defer { isLoading = false }

        do {
            try service.deleteVariable(variable)
            successMessage = "Variable deleted successfully"
        } catch {
            handleError(error)
        }
    }

    func batchDeleteVariables(_ variables: [Variable]) {
        guard !variables.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            try service.batchDeleteVariables(variables)
            successMessage = "Deleted \(variables.count) variable(s)"
        } catch {
            handleError(error)
        }
    }

    func reorderVariables(_ orderedVariables: [Variable]) {
        guard !orderedVariables.isEmpty else { return }
        do {
            try service.reorderVariables(orderedVariables)
        } catch {
            handleError(error)
        }
    }

    // MARK: - Filtering

    private func filterTagGroups(_ tagGroups: [TagGroup]) -> [TagGroup] {
        let filtered = searchQuery.isEmpty
            ? tagGroups
            : tagGroups.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
        return filtered.sortedByManualOrder()
    }

    private func filterTags(_ tags: [Tag]) -> [Tag] {
        let filtered = searchQuery.isEmpty
            ? tags
            : tags.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
        return filtered.sortedByManualOrder()
    }

    private func filterVariables(_ variables: [Variable]) -> [Variable] {
        let filtered = searchQuery.isEmpty
            ? variables
            : variables.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
        return filtered.sortedByManualOrder()
    }

    // MARK: - Helper Methods

    func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }

    private func handleError(_ error: Error) {
        if let propertyError = error as? PropertyManagementError {
            errorMessage = propertyError.localizedDescription
        } else {
            errorMessage = "An error occurred: \(error.localizedDescription)"
        }
        print("Property management error: \(error)")
    }
}
