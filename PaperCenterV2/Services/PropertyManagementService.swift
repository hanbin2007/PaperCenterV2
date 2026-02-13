import Foundation
import SwiftData

enum PropertyManagementError: LocalizedError {
    case duplicateName(String), invalidColor(String), invalidListOptions
    case tagGroupHasTags, variableHasAssignments, invalidScope, notFound

    var errorDescription: String? {
        switch self {
        case .duplicateName(let name): return "A property with the name '\(name)' already exists"
        case .invalidColor(let color): return "Invalid hex color code: \(color)"
        case .invalidListOptions: return "List-type variables must have at least 2 options"
        case .tagGroupHasTags: return "Cannot delete tag group that contains tags"
        case .variableHasAssignments: return "Cannot delete variable that has existing assignments"
        case .invalidScope: return "Invalid scope for this operation"
        case .notFound: return "Property not found"
        }
    }
}

@MainActor
final class PropertyManagementService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    private func notifyMetadataChanged() {
        NotificationCenter.default.post(name: .metadataCatalogDidChange, object: nil)
    }

    // MARK: - TagGroup Operations

    func fetchAllTagGroups() throws -> [TagGroup] {
        try modelContext.fetch(FetchDescriptor<TagGroup>()).sortedByManualOrder()
    }

    func fetchTagGroup(id: UUID) throws -> TagGroup? {
        var desc = FetchDescriptor<TagGroup>(predicate: #Predicate { $0.id == id })
        desc.fetchLimit = 1
        return try modelContext.fetch(desc).first
    }

    func createTagGroup(name: String) throws -> TagGroup {
        try validateTagGroupNameUnique(name)
        let group = TagGroup(name: name, sortIndex: try nextTagGroupSortIndex())
        modelContext.insert(group)
        try modelContext.save()
        return group
    }

    func updateTagGroup(_ tagGroup: TagGroup, name: String) throws {
        if tagGroup.name != name {
            try validateTagGroupNameUnique(name)
        }
        tagGroup.name = name
        tagGroup.touch()
        try modelContext.save()
    }

    func deleteTagGroup(_ tagGroup: TagGroup) throws {
        if let tags = tagGroup.tags, !tags.isEmpty {
            throw PropertyManagementError.tagGroupHasTags
        }
        modelContext.delete(tagGroup)
        try modelContext.save()
    }

    func batchDeleteTagGroups(_ tagGroups: [TagGroup]) throws {
        for tagGroup in tagGroups {
            try? deleteTagGroup(tagGroup)
        }
    }

    func duplicateTagGroup(_ tagGroup: TagGroup) throws -> TagGroup {
        var candidateName = "\(tagGroup.name) Copy"
        var suffix = 2
        while (try? validateTagGroupNameUnique(candidateName)) == nil {
            candidateName = "\(tagGroup.name) Copy \(suffix)"
            suffix += 1
        }

        let newGroup = TagGroup(name: candidateName, sortIndex: try nextTagGroupSortIndex())
        modelContext.insert(newGroup)
        if let tags = tagGroup.tags?.sortedByManualOrder() {
            for (idx, original) in tags.enumerated() {
                modelContext.insert(
                    Tag(
                        name: original.name,
                        color: original.color,
                        scope: original.scope,
                        tagGroup: newGroup,
                        sortIndex: idx
                    )
                )
            }
        }

        try modelContext.save()
        notifyMetadataChanged()
        return newGroup
    }

    func reorderTagGroups(_ orderedGroups: [TagGroup]) throws {
        for (index, group) in orderedGroups.enumerated() {
            group.sortIndex = index
            group.touch()
        }
        try modelContext.save()
        notifyMetadataChanged()
    }

    // MARK: - Tag Operations

    func fetchAllTags() throws -> [Tag] {
        try modelContext.fetch(FetchDescriptor<Tag>()).sortedByManualOrder()
    }

    func fetchTags(byScope scope: TagScope) throws -> [Tag] {
        try modelContext.fetch(
            FetchDescriptor<Tag>(predicate: #Predicate { $0.scope == scope })
        ).sortedByManualOrder()
    }

    func fetchTags(byGroup tagGroup: TagGroup) throws -> [Tag] {
        (tagGroup.tags ?? []).sortedByManualOrder()
    }

    func fetchTag(id: UUID) throws -> Tag? {
        var desc = FetchDescriptor<Tag>(predicate: #Predicate { $0.id == id })
        desc.fetchLimit = 1
        return try modelContext.fetch(desc).first
    }

    func createTag(
        name: String,
        color: String = "#3B82F6",
        scope: TagScope = .all,
        tagGroup: TagGroup? = nil
    ) throws -> Tag {
        try validateTagNameUnique(name)
        try validateHexColor(color)
        let tag = Tag(name: name, color: color, scope: scope, tagGroup: tagGroup, sortIndex: try nextTagSortIndex(in: tagGroup))
        modelContext.insert(tag)
        try modelContext.save()
        return tag
    }

    func updateTag(
        _ tag: Tag,
        name: String? = nil,
        color: String? = nil,
        scope: TagScope? = nil,
        tagGroup: TagGroup? = nil
    ) throws {
        if let name = name, tag.name != name {
            try validateTagNameUnique(name)
            tag.name = name
        }
        if let color = color {
            try validateHexColor(color)
            tag.color = color
        }
        if let scope = scope {
            tag.scope = scope
        }

        if let tagGroup = tagGroup {
            let moved = tag.tagGroup?.id != tagGroup.id
            tag.tagGroup = tagGroup
            if moved {
                tag.sortIndex = try nextTagSortIndex(in: tagGroup)
            }
        } else if tag.tagGroup != nil {
            tag.tagGroup = nil
            tag.sortIndex = try nextTagSortIndex(in: nil)
        }

        tag.touch()
        try modelContext.save()
    }

    func deleteTag(_ tag: Tag) throws {
        modelContext.delete(tag)
        try modelContext.save()
    }

    func batchDeleteTags(_ tags: [Tag]) throws {
        for tag in tags {
            modelContext.delete(tag)
        }
        try modelContext.save()
    }

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

    func reorderTags(_ orderedTags: [Tag], tagGroup: TagGroup?) throws {
        for (index, tag) in orderedTags.enumerated() {
            tag.sortIndex = index
            if let tagGroup {
                tag.tagGroup = tagGroup
            } else if tag.tagGroup != nil {
                tag.tagGroup = nil
            }
            tag.touch()
        }
        try modelContext.save()
        notifyMetadataChanged()
    }

    func bulkCreateTags(names: [String], tagGroup: TagGroup, color: String = "#3B82F6", scope: TagScope = .all) throws -> [Tag] {
        try validateHexColor(color)
        var createdTags: [Tag] = []
        var nextIndex = try nextTagSortIndex(in: tagGroup)

        for name in names where (try? validateTagNameUnique(name)) != nil {
            let tag = Tag(name: name, color: color, scope: scope, tagGroup: tagGroup, sortIndex: nextIndex)
            nextIndex += 1
            modelContext.insert(tag)
            createdTags.append(tag)
        }

        try modelContext.save()
        return createdTags
    }

    // MARK: - Variable Operations

    func fetchAllVariables() throws -> [Variable] {
        try modelContext.fetch(FetchDescriptor<Variable>()).sortedByManualOrder()
    }

    func fetchVariables(byScope scope: VariableScope) throws -> [Variable] {
        try modelContext.fetch(
            FetchDescriptor<Variable>(predicate: #Predicate { $0.scope == scope })
        ).sortedByManualOrder()
    }

    func fetchVariables(byType type: VariableType) throws -> [Variable] {
        try modelContext.fetch(
            FetchDescriptor<Variable>(predicate: #Predicate { $0.type == type })
        ).sortedByManualOrder()
    }

    func fetchVariable(id: UUID) throws -> Variable? {
        var desc = FetchDescriptor<Variable>(predicate: #Predicate { $0.id == id })
        desc.fetchLimit = 1
        return try modelContext.fetch(desc).first
    }

    func createVariable(
        name: String,
        type: VariableType,
        scope: VariableScope = .all,
        color: String = "#8B5CF6",
        listOptions: [String]? = nil
    ) throws -> Variable {
        try validateVariableNameUnique(name)
        try validateHexColor(color)
        if type == .list {
            try validateListOptions(listOptions)
        }
        let variable = Variable(
            name: name,
            type: type,
            scope: scope,
            color: color,
            sortIndex: try nextVariableSortIndex(),
            listOptions: listOptions
        )
        modelContext.insert(variable)
        try modelContext.save()
        return variable
    }

    func updateVariable(
        _ variable: Variable,
        name: String? = nil,
        scope: VariableScope? = nil,
        color: String? = nil,
        listOptions: [String]? = nil
    ) throws {
        if let name = name, variable.name != name {
            try validateVariableNameUnique(name)
            variable.name = name
        }
        if let scope = scope {
            variable.scope = scope
        }
        if let color = color {
            try validateHexColor(color)
            variable.color = color
        }
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

    func deleteVariable(_ variable: Variable) throws {
        if try hasAssignments(variable) {
            throw PropertyManagementError.variableHasAssignments
        }
        modelContext.delete(variable)
        try modelContext.save()
    }

    func batchDeleteVariables(_ variables: [Variable]) throws {
        for variable in variables {
            try? deleteVariable(variable)
        }
    }

    func reorderVariables(_ orderedVariables: [Variable]) throws {
        for (index, variable) in orderedVariables.enumerated() {
            variable.sortIndex = index
            variable.touch()
        }
        try modelContext.save()
        notifyMetadataChanged()
    }

    // MARK: - Safe Ordering & Checking (Optimized with fetchLimit)

    private func nextTagGroupSortIndex() throws -> Int {
        var desc = FetchDescriptor<TagGroup>(
            sortBy: [SortDescriptor(\.sortIndex, order: .reverse)]
        )
        desc.fetchLimit = 1
        return (try modelContext.fetch(desc).first?.sortIndex ?? -1) + 1
    }

    private func nextTagSortIndex(in tagGroup: TagGroup?) throws -> Int {
        var desc: FetchDescriptor<Tag>
        if let groupID = tagGroup?.id {
            desc = FetchDescriptor<Tag>(
                predicate: #Predicate { $0.tagGroup?.id == groupID },
                sortBy: [SortDescriptor(\.sortIndex, order: .reverse)]
            )
        } else {
            desc = FetchDescriptor<Tag>(
                predicate: #Predicate { $0.tagGroup == nil },
                sortBy: [SortDescriptor(\.sortIndex, order: .reverse)]
            )
        }
        desc.fetchLimit = 1
        return (try modelContext.fetch(desc).first?.sortIndex ?? -1) + 1
    }

    private func nextVariableSortIndex() throws -> Int {
        var desc = FetchDescriptor<Variable>(
            sortBy: [SortDescriptor(\.sortIndex, order: .reverse)]
        )
        desc.fetchLimit = 1
        return (try modelContext.fetch(desc).first?.sortIndex ?? -1) + 1
    }

    // MARK: - Validation Helpers

    private func validateTagGroupNameUnique(_ name: String) throws {
        let existing = try modelContext.fetch(
            FetchDescriptor<TagGroup>(
                predicate: #Predicate { $0.name.localizedStandardContains(name) }
            )
        )
        if existing.contains(where: { $0.name.lowercased() == name.lowercased() }) {
            throw PropertyManagementError.duplicateName(name)
        }
    }

    private func validateTagNameUnique(_ name: String) throws {
        let existing = try modelContext.fetch(
            FetchDescriptor<Tag>(
                predicate: #Predicate { $0.name.localizedStandardContains(name) }
            )
        )
        if existing.contains(where: { $0.name.lowercased() == name.lowercased() }) {
            throw PropertyManagementError.duplicateName(name)
        }
    }

    private func validateVariableNameUnique(_ name: String) throws {
        let existing = try modelContext.fetch(
            FetchDescriptor<Variable>(
                predicate: #Predicate { $0.name.localizedStandardContains(name) }
            )
        )
        if existing.contains(where: { $0.name.lowercased() == name.lowercased() }) {
            throw PropertyManagementError.duplicateName(name)
        }
    }

    private func validateHexColor(_ color: String) throws {
        let regex = try? NSRegularExpression(pattern: "^#([A-Fa-f0-9]{6})$")
        if regex?.firstMatch(in: color, range: NSRange(location: 0, length: color.utf16.count)) == nil {
            throw PropertyManagementError.invalidColor(color)
        }
    }

    private func validateListOptions(_ listOptions: [String]?) throws {
        guard let options = listOptions, options.count >= 2 else {
            throw PropertyManagementError.invalidListOptions
        }
    }

    private func hasAssignments(_ variable: Variable) throws -> Bool {
        let vID = variable.id

        var d1 = FetchDescriptor<PDFBundleVariableAssignment>(predicate: #Predicate { $0.variable?.id == vID })
        d1.fetchLimit = 1
        if try modelContext.fetchCount(d1) > 0 { return true }

        var d2 = FetchDescriptor<DocVariableAssignment>(predicate: #Predicate { $0.variable?.id == vID })
        d2.fetchLimit = 1
        if try modelContext.fetchCount(d2) > 0 { return true }

        var d3 = FetchDescriptor<PageGroupVariableAssignment>(predicate: #Predicate { $0.variable?.id == vID })
        d3.fetchLimit = 1
        if try modelContext.fetchCount(d3) > 0 { return true }

        var d4 = FetchDescriptor<PageVariableAssignment>(predicate: #Predicate { $0.variable?.id == vID })
        d4.fetchLimit = 1
        if try modelContext.fetchCount(d4) > 0 { return true }

        var d5 = FetchDescriptor<NoteBlockVariableAssignment>(predicate: #Predicate { $0.variable?.id == vID })
        d5.fetchLimit = 1
        if try modelContext.fetchCount(d5) > 0 { return true }

        return false
    }
}
