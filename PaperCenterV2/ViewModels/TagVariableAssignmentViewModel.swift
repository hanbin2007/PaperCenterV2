//
//  TagVariableAssignmentViewModel.swift
//  PaperCenterV2
//
//  Coordinates tag and variable assignment for a given entity type.
//

import Foundation
import SwiftData
import SwiftUI

/// User-facing value for a variable
enum VariableValue: Equatable {
    case int(Int)
    case list(String)
    case text(String)
    case date(Date)

    var intValue: Int? {
        if case .int(let value) = self { return value }
        return nil
    }

    var listValue: String? {
        if case .list(let value) = self { return value }
        return nil
    }

    var textValue: String? {
        if case .text(let value) = self { return value }
        return nil
    }

    var dateValue: Date? {
        if case .date(let value) = self { return value }
        return nil
    }
}

/// MVVM ViewModel handling tag/variable selection and persistence.
@MainActor
@Observable
final class TagVariableAssignmentViewModel: NSObject {

    // MARK: - Types

    enum Target {
        case pdfBundle(PDFBundle)
        case doc(Doc)
        case pageGroup(PageGroup)
        case page(Page)
    }

    // MARK: - Public State

    let entityType: TaggableEntityType

    var availableTags: [Tag] = []
    var availableVariables: [Variable] = []
    var availableTagGroups: [TagGroup] = []

    var selectedTagIDs: Set<UUID> = []
    var selectedVariableIDs: Set<UUID> = []
    var variableValues: [UUID: VariableValue] = [:]

    var statusMessage: String?
    var errorMessage: String?
    var isSaving: Bool = false
    var searchText: String = ""

    // MARK: - Private

    private let modelContext: ModelContext
    private let propertyService: PropertyManagementService
    private(set) var target: Target?

    // MARK: - Initialization

    init(modelContext: ModelContext, entityType: TaggableEntityType, target: Target? = nil) {
        self.modelContext = modelContext
        self.entityType = entityType
        self.propertyService = PropertyManagementService(modelContext: modelContext)
        self.target = target
        super.init()
        loadAvailable()
        syncFromTarget()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(metadataCatalogDidChange),
            name: .metadataCatalogDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: .metadataCatalogDidChange, object: nil)
    }

    // MARK: - Loading

    func refresh() {
        loadAvailable()
        syncFromTarget()
    }

    @objc private func metadataCatalogDidChange() {
        refresh()
    }

    private func loadAvailable() {
        do {
            let tagDescriptor = FetchDescriptor<Tag>()
            let variableDescriptor = FetchDescriptor<Variable>()

            let tags = try modelContext.fetch(tagDescriptor)
            let variables = try modelContext.fetch(variableDescriptor)
            availableTagGroups = (try propertyService.fetchAllTagGroups()).sortedByManualOrder()

            // Enforce scope visibility
            availableTags = tags
                .filter { $0.scope.canTag(entityType) }
                .sortedByManualOrder()
            availableVariables = variables
                .filter { $0.scope.canApplyTo(entityType.toVariableEntityType) }
                .sortedByManualOrder()
        } catch {
            errorMessage = "Failed to load tags/variables: \(error.localizedDescription)"
        }
    }

    private func syncFromTarget() {
        guard let target = target else { return }

        switch target {
        case .doc(let doc):
            selectedTagIDs = Set(doc.tags?.map { $0.id } ?? [])
            if let assignments = doc.variableAssignments {
                variableValues = assignments.reduce(into: [:]) { dict, assignment in
                    guard let variable = assignment.variable else { return }
                    switch variable.type {
                    case .int:
                        if let value = assignment.intValue {
                            dict[variable.id] = .int(value)
                        }
                    case .list:
                        if let value = assignment.listValue {
                            dict[variable.id] = .list(value)
                        }
                    case .text:
                        if let value = assignment.textValue, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            dict[variable.id] = .text(value)
                        }
                    case .date:
                        if let value = assignment.dateValue {
                            dict[variable.id] = .date(value)
                        }
                    }
                }
                selectedVariableIDs = Set(variableValues.keys)
            }
        case .pdfBundle(let bundle):
            selectedTagIDs = Set(bundle.tags?.map { $0.id } ?? [])
            if let assignments = bundle.variableAssignments {
                variableValues = assignments.reduce(into: [:]) { dict, assignment in
                    guard let variable = assignment.variable else { return }
                    switch variable.type {
                    case .int:
                        if let value = assignment.intValue {
                            dict[variable.id] = .int(value)
                        }
                    case .list:
                        if let value = assignment.listValue {
                            dict[variable.id] = .list(value)
                        }
                    case .text:
                        if let value = assignment.textValue, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            dict[variable.id] = .text(value)
                        }
                    case .date:
                        if let value = assignment.dateValue {
                            dict[variable.id] = .date(value)
                        }
                    }
                }
                selectedVariableIDs = Set(variableValues.keys)
            }
        case .pageGroup(let group):
            selectedTagIDs = Set(group.tags?.map { $0.id } ?? [])
            if let assignments = group.variableAssignments {
                variableValues = assignments.reduce(into: [:]) { dict, assignment in
                    guard let variable = assignment.variable else { return }
                    switch variable.type {
                    case .int:
                        if let value = assignment.intValue {
                            dict[variable.id] = .int(value)
                        }
                    case .list:
                        if let value = assignment.listValue {
                            dict[variable.id] = .list(value)
                        }
                    case .text:
                        if let value = assignment.textValue, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            dict[variable.id] = .text(value)
                        }
                    case .date:
                        if let value = assignment.dateValue {
                            dict[variable.id] = .date(value)
                        }
                    }
                }
                selectedVariableIDs = Set(variableValues.keys)
            }
        case .page(let page):
            selectedTagIDs = Set(page.tags?.map { $0.id } ?? [])
            if let assignments = page.variableAssignments {
                variableValues = assignments.reduce(into: [:]) { dict, assignment in
                    guard let variable = assignment.variable else { return }
                    switch variable.type {
                    case .int:
                        if let value = assignment.intValue {
                            dict[variable.id] = .int(value)
                        }
                    case .list:
                        if let value = assignment.listValue {
                            dict[variable.id] = .list(value)
                        }
                    case .text:
                        if let value = assignment.textValue, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            dict[variable.id] = .text(value)
                        }
                    case .date:
                        if let value = assignment.dateValue {
                            dict[variable.id] = .date(value)
                        }
                    }
                }
                selectedVariableIDs = Set(variableValues.keys)
            }
        }
    }

    // MARK: - Public Mutations

    /// Replace the target (useful after creating a Doc) and apply current selections.
    func bind(to target: Target) {
        self.target = target
        applyPending(to: target)
        syncFromTarget()
    }

    func toggleTag(_ tag: Tag) {
        let selecting = !selectedTagIDs.contains(tag.id)
        selectedTagIDs.formSymmetricDifference([tag.id])

        guard let target = target else { return }
        do {
            isSaving = true
            switch target {
            case .doc(let doc):
                if selecting {
                    add(tag: tag, to: &doc.tags)
                } else {
                    remove(tag: tag, from: &doc.tags)
                }
                doc.touch()
            case .pdfBundle(let bundle):
                if selecting {
                    add(tag: tag, to: &bundle.tags)
                } else {
                    remove(tag: tag, from: &bundle.tags)
                }
            case .pageGroup(let group):
                if selecting {
                    add(tag: tag, to: &group.tags)
                } else {
                    remove(tag: tag, from: &group.tags)
                }
            case .page(let page):
                if selecting {
                    add(tag: tag, to: &page.tags)
                } else {
                    remove(tag: tag, from: &page.tags)
                }
            }
            try modelContext.save()
            statusMessage = "Saved"
        } catch {
            // Roll back selection on failure
            selectedTagIDs.formSymmetricDifference([tag.id])
            errorMessage = "Failed to save tag: \(error.localizedDescription)"
        }
        isSaving = false
    }

    @discardableResult
    func quickCreateTagGroup(name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Tag group name cannot be empty"
            return false
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let created = try propertyService.createTagGroup(name: trimmed)
            availableTagGroups.append(created)
            availableTagGroups = availableTagGroups.sortedByManualOrder()
            statusMessage = "Tag group '\(trimmed)' added"
            return true
        } catch {
            errorMessage = "Failed to create tag group: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func quickCreateTag(name: String, in group: TagGroup?) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Tag name cannot be empty"
            return false
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let scope = tagScope(for: entityType)
            let color = Self.randomTagColor()
            let created = try propertyService.createTag(
                name: trimmed,
                color: color,
                scope: scope,
                tagGroup: group
            )
            availableTags.append(created)
            availableTags = availableTags.sortedByManualOrder()
            selectedTagIDs.insert(created.id)
            if let target {
                switch target {
                case .doc(let doc):
                    add(tag: created, to: &doc.tags)
                    doc.touch()
                case .pdfBundle(let bundle):
                    add(tag: created, to: &bundle.tags)
                case .pageGroup(let group):
                    add(tag: created, to: &group.tags)
                case .page(let page):
                    add(tag: created, to: &page.tags)
                }
                try modelContext.save()
            }
            statusMessage = "Tag '\(trimmed)' added"
            return true
        } catch {
            errorMessage = "Failed to create tag: \(error.localizedDescription)"
            return false
        }
    }

    func toggleVariableSelection(_ variable: Variable) {
        let selecting = !selectedVariableIDs.contains(variable.id)
        if selecting {
            selectedVariableIDs.insert(variable.id)
        } else {
            selectedVariableIDs.remove(variable.id)
            variableValues.removeValue(forKey: variable.id)
            removeAssignment(of: variable)
            do {
                try modelContext.save()
                statusMessage = "Saved"
            } catch {
                errorMessage = "Failed to save variable removal: \(error.localizedDescription)"
            }
        }
    }

    func updateVariable(_ variable: Variable, intValue: Int?) {
        selectedVariableIDs.insert(variable.id)
        if let value = intValue {
            variableValues[variable.id] = .int(value)
        } else {
            variableValues.removeValue(forKey: variable.id)
        }

        guard let target = target else { return }

        do {
            isSaving = true
            try persistVariable(variable, value: variableValues[variable.id], target: target)
            try modelContext.save()
            statusMessage = "Saved"
        } catch {
            errorMessage = "Failed to save variable: \(error.localizedDescription)"
        }
        isSaving = false
    }

    func updateVariable(_ variable: Variable, listValue: String?) {
        selectedVariableIDs.insert(variable.id)
        if let value = listValue {
            variableValues[variable.id] = .list(value)
        } else {
            variableValues.removeValue(forKey: variable.id)
        }

        guard let target = target else { return }

        do {
            isSaving = true
            try persistVariable(variable, value: variableValues[variable.id], target: target)
            try modelContext.save()
            statusMessage = "Saved"
        } catch {
            errorMessage = "Failed to save variable: \(error.localizedDescription)"
        }
        isSaving = false
    }

    func updateVariable(_ variable: Variable, textValue: String?) {
        selectedVariableIDs.insert(variable.id)
        let trimmed = textValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            variableValues[variable.id] = .text(trimmed)
        } else {
            variableValues.removeValue(forKey: variable.id)
        }

        guard let target = target else { return }

        do {
            isSaving = true
            try persistVariable(variable, value: variableValues[variable.id], target: target)
            try modelContext.save()
            statusMessage = "Saved"
        } catch {
            errorMessage = "Failed to save variable: \(error.localizedDescription)"
        }
        isSaving = false
    }

    func updateVariable(_ variable: Variable, dateValue: Date?) {
        selectedVariableIDs.insert(variable.id)
        if let dateValue {
            variableValues[variable.id] = .date(dateValue)
        } else {
            variableValues.removeValue(forKey: variable.id)
        }

        guard let target = target else { return }

        do {
            isSaving = true
            try persistVariable(variable, value: variableValues[variable.id], target: target)
            try modelContext.save()
            statusMessage = "Saved"
        } catch {
            errorMessage = "Failed to save variable: \(error.localizedDescription)"
        }
        isSaving = false
    }

    // MARK: - Applying Pending State

    /// Apply in-memory selections to a concrete target (used when the entity is created in the same flow).
    func applyPending(to target: Target) {
        switch target {
        case .doc(let doc):
            let tags = availableTags.filter { selectedTagIDs.contains($0.id) }
            doc.tags = tags
            let selectedVars = availableVariables.filter { selectedVariableIDs.contains($0.id) }
            for variable in selectedVars {
                let value = variableValues[variable.id]
                try? persistVariable(variable, value: value, target: target)
            }
        case .pdfBundle(let bundle):
            let tags = availableTags.filter { selectedTagIDs.contains($0.id) }
            bundle.tags = tags
            let selectedVars = availableVariables.filter { selectedVariableIDs.contains($0.id) }
            for variable in selectedVars {
                let value = variableValues[variable.id]
                try? persistVariable(variable, value: value, target: target)
            }
        case .pageGroup(let group):
            let tags = availableTags.filter { selectedTagIDs.contains($0.id) }
            group.tags = tags
            let selectedVars = availableVariables.filter { selectedVariableIDs.contains($0.id) }
            for variable in selectedVars {
                let value = variableValues[variable.id]
                try? persistVariable(variable, value: value, target: target)
            }
        case .page(let page):
            let tags = availableTags.filter { selectedTagIDs.contains($0.id) }
            page.tags = tags
            let selectedVars = availableVariables.filter { selectedVariableIDs.contains($0.id) }
            for variable in selectedVars {
                let value = variableValues[variable.id]
                try? persistVariable(variable, value: value, target: target)
            }
        }
    }

    // MARK: - Helpers

    private func add(tag: Tag, to collection: inout [Tag]?) {
        if collection == nil { collection = [] }
        if !(collection?.contains(where: { $0.id == tag.id }) ?? false) {
            collection?.append(tag)
        }
    }

    private func remove(tag: Tag, from collection: inout [Tag]?) {
        collection?.removeAll { $0.id == tag.id }
    }

    private func persistVariable(
        _ variable: Variable,
        value: VariableValue?,
        target: Target
    ) throws {
        switch target {
        case .doc(let doc):
            var assignment = doc.variableAssignments?.first(where: { $0.variable?.id == variable.id })
            if assignment == nil {
                assignment = DocVariableAssignment(variable: variable, doc: doc)
                if doc.variableAssignments == nil { doc.variableAssignments = [] }
                doc.variableAssignments?.append(assignment!)
            }
            assignment?.intValue = value?.intValue
            assignment?.listValue = value?.listValue
            assignment?.textValue = value?.textValue
            assignment?.dateValue = value?.dateValue
            doc.touch()
        case .pdfBundle(let bundle):
            var assignment = bundle.variableAssignments?.first(where: { $0.variable?.id == variable.id })
            if assignment == nil {
                assignment = PDFBundleVariableAssignment(variable: variable, pdfBundle: bundle)
                if bundle.variableAssignments == nil { bundle.variableAssignments = [] }
                bundle.variableAssignments?.append(assignment!)
            }
            assignment?.intValue = value?.intValue
            assignment?.listValue = value?.listValue
            assignment?.textValue = value?.textValue
            assignment?.dateValue = value?.dateValue
        case .pageGroup(let group):
            var assignment = group.variableAssignments?.first(where: { $0.variable?.id == variable.id })
            if assignment == nil {
                assignment = PageGroupVariableAssignment(variable: variable, pageGroup: group)
                if group.variableAssignments == nil { group.variableAssignments = [] }
                group.variableAssignments?.append(assignment!)
            }
            assignment?.intValue = value?.intValue
            assignment?.listValue = value?.listValue
            assignment?.textValue = value?.textValue
            assignment?.dateValue = value?.dateValue
        case .page(let page):
            var assignment = page.variableAssignments?.first(where: { $0.variable?.id == variable.id })
            if assignment == nil {
                assignment = PageVariableAssignment(variable: variable, page: page)
                if page.variableAssignments == nil { page.variableAssignments = [] }
                page.variableAssignments?.append(assignment!)
            }
            assignment?.intValue = value?.intValue
            assignment?.listValue = value?.listValue
            assignment?.textValue = value?.textValue
            assignment?.dateValue = value?.dateValue
        }
    }

    private func removeAssignment(of variable: Variable) {
        guard let target = target else { return }

        switch target {
        case .doc(let doc):
            doc.variableAssignments?.removeAll { $0.variable?.id == variable.id }
        case .pdfBundle(let bundle):
            bundle.variableAssignments?.removeAll { $0.variable?.id == variable.id }
        case .pageGroup(let group):
            group.variableAssignments?.removeAll { $0.variable?.id == variable.id }
        case .page(let page):
            page.variableAssignments?.removeAll { $0.variable?.id == variable.id }
        }
    }

    private func tagScope(for entity: TaggableEntityType) -> TagScope {
        switch entity {
        case .pdfBundle:
            return .pdfBundle
        case .doc:
            return .doc
        case .pageGroup:
            return .pageGroup
        case .page:
            return .page
        case .noteBlock:
            return .noteBlock
        }
    }

    private static func randomTagColor() -> String {
        let palette = [
            "#3B82F6", "#6366F1", "#A855F7", "#EC4899",
            "#F97316", "#10B981", "#14B8A6", "#F43F5E"
        ]
        return palette.randomElement() ?? "#3B82F6"
    }
}

private extension TaggableEntityType {
    var toVariableEntityType: VariableEntityType {
        switch self {
        case .pdfBundle:
            return .pdfBundle
        case .doc:
            return .doc
        case .pageGroup:
            return .pageGroup
        case .page:
            return .page
        case .noteBlock:
            return .noteBlock
        }
    }
}
