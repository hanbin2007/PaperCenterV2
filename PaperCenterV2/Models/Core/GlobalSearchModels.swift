//
//  GlobalSearchModels.swift
//  PaperCenterV2
//
//  Shared models for global search and structured filters.
//

import Foundation

enum GlobalSearchField: String, CaseIterable, Codable, Hashable, Identifiable {
    case docTitle
    case pageGroupTitle
    case ocrText
    case noteTitleBody
    case tagName
    case variableName
    case variableValue
    case versionSnapshotMetadata

    var id: String { rawValue }

    var title: String {
        switch self {
        case .docTitle:
            return "Document Title"
        case .pageGroupTitle:
            return "Page Group Title"
        case .ocrText:
            return "OCR Text"
        case .noteTitleBody:
            return "Notes"
        case .tagName:
            return "Tag Names"
        case .variableName:
            return "Variable Names"
        case .variableValue:
            return "Variable Values"
        case .versionSnapshotMetadata:
            return "Version Snapshot"
        }
    }
}

enum GlobalSearchResultKind: String, CaseIterable, Codable, Hashable, Identifiable {
    case doc
    case pageGroup
    case page
    case ocrHit
    case noteHit
    case versionMetadataHit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .doc:
            return "Document"
        case .pageGroup:
            return "Page Group"
        case .page:
            return "Page"
        case .ocrHit:
            return "OCR"
        case .noteHit:
            return "Note"
        case .versionMetadataHit:
            return "Version Metadata"
        }
    }

    var icon: String {
        switch self {
        case .doc:
            return "doc.text"
        case .pageGroup:
            return "folder"
        case .page:
            return "doc.plaintext"
        case .ocrHit:
            return "text.viewfinder"
        case .noteHit:
            return "text.bubble"
        case .versionMetadataHit:
            return "clock.arrow.trianglehead.counterclockwise.rotate.90"
        }
    }
}

enum TagFilterMode: String, CaseIterable, Codable, Hashable, Identifiable {
    case any
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any:
            return "Any"
        case .all:
            return "All"
        }
    }
}

enum FilterLogicalMode: String, CaseIterable, Codable, Hashable, Identifiable {
    case and
    case or

    var id: String { rawValue }

    var title: String {
        switch self {
        case .and:
            return "AND"
        case .or:
            return "OR"
        }
    }
}

enum RangeBoundInclusion: String, CaseIterable, Codable, Hashable, Identifiable {
    case open
    case closed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open:
            return "Open"
        case .closed:
            return "Closed"
        }
    }
}

struct TagFilter: Codable, Hashable {
    var nameKeyword: String
    var selectedTagIDs: Set<UUID>
    var mode: TagFilterMode

    init(
        nameKeyword: String = "",
        selectedTagIDs: Set<UUID> = [],
        mode: TagFilterMode = .any
    ) {
        self.nameKeyword = nameKeyword
        self.selectedTagIDs = selectedTagIDs
        self.mode = mode
    }

    var isActive: Bool {
        !nameKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !selectedTagIDs.isEmpty
    }
}

enum VariableFilterOperator: String, CaseIterable, Codable, Hashable, Identifiable {
    case eq
    case neq
    case gt
    case gte
    case lt
    case lte
    case between

    case contains
    case equals

    case `in`
    case notIn

    case isSet
    case isEmpty

    var id: String { rawValue }

    var title: String {
        switch self {
        case .eq:
            return "="
        case .neq:
            return "!="
        case .gt:
            return ">"
        case .gte:
            return ">="
        case .lt:
            return "<"
        case .lte:
            return "<="
        case .between:
            return "Between"
        case .contains:
            return "Contains"
        case .equals:
            return "Equals"
        case .in:
            return "In"
        case .notIn:
            return "Not In"
        case .isSet:
            return "Is Set"
        case .isEmpty:
            return "Is Empty"
        }
    }

    static func allowed(for type: VariableType) -> [VariableFilterOperator] {
        switch type {
        case .int, .date:
            return [.eq, .neq, .gt, .gte, .lt, .lte, .between, .isSet, .isEmpty]
        case .text:
            return [.contains, .equals, .isSet, .isEmpty]
        case .list:
            return [.in, .notIn, .isSet, .isEmpty]
        }
    }

    static func defaultOperator(for type: VariableType) -> VariableFilterOperator {
        switch type {
        case .int, .date:
            return .eq
        case .text:
            return .contains
        case .list:
            return .in
        }
    }

    var needsValue: Bool {
        self != .isSet && self != .isEmpty
    }
}

enum VariableFilterValue: Codable, Hashable {
    case int(Int)
    case intRange(
        min: Int,
        max: Int,
        lowerInclusion: RangeBoundInclusion,
        upperInclusion: RangeBoundInclusion
    )

    case text(String)

    case date(Date)
    case dateRange(
        min: Date,
        max: Date,
        lowerInclusion: RangeBoundInclusion,
        upperInclusion: RangeBoundInclusion
    )

    case list([String])
}

struct VariableFilterRule: Codable, Hashable, Identifiable {
    var id: UUID
    var variableID: UUID
    var `operator`: VariableFilterOperator
    var value: VariableFilterValue?

    init(
        id: UUID = UUID(),
        variableID: UUID,
        operator: VariableFilterOperator,
        value: VariableFilterValue?
    ) {
        self.id = id
        self.variableID = variableID
        self.operator = `operator`
        self.value = value
    }
}

struct GlobalSearchOptions: Codable, Hashable {
    var fieldScope: Set<GlobalSearchField>
    var resultTypes: Set<GlobalSearchResultKind>
    var includeHistoricalVersions: Bool
    var maxResults: Int

    var tagFilter: TagFilter
    var variableRules: [VariableFilterRule]
    var variableRulesMode: FilterLogicalMode

    static let `default` = GlobalSearchOptions(
        fieldScope: Set(GlobalSearchField.allCases),
        resultTypes: Set(GlobalSearchResultKind.allCases),
        includeHistoricalVersions: true,
        maxResults: 120,
        tagFilter: TagFilter(),
        variableRules: [],
        variableRulesMode: .and
    )

    var hasStructuredFilters: Bool {
        tagFilter.isActive || !variableRules.isEmpty
    }
}

struct DocViewerLaunchContext: Hashable, Codable {
    let logicalPageID: UUID?
    let preferredVersionID: UUID?
    let preferredSource: UniversalDocViewerSource?
    let preferredNoteID: UUID?

    init(
        logicalPageID: UUID? = nil,
        preferredVersionID: UUID? = nil,
        preferredSource: UniversalDocViewerSource? = nil,
        preferredNoteID: UUID? = nil
    ) {
        self.logicalPageID = logicalPageID
        self.preferredVersionID = preferredVersionID
        self.preferredSource = preferredSource
        self.preferredNoteID = preferredNoteID
    }
}

struct GlobalSearchResult: Identifiable, Hashable {
    let id: String
    let kind: GlobalSearchResultKind
    let matchedFields: Set<GlobalSearchField>
    let score: Int

    let docID: UUID
    let docTitle: String
    let pageGroupID: UUID?
    let pageGroupTitle: String?
    let logicalPageID: UUID?
    let pageVersionID: UUID?
    let noteID: UUID?

    let title: String
    let subtitle: String
    let snippet: String

    var launchContext: DocViewerLaunchContext {
        switch kind {
        case .ocrHit:
            return DocViewerLaunchContext(
                logicalPageID: logicalPageID,
                preferredVersionID: pageVersionID,
                preferredSource: .ocr,
                preferredNoteID: nil
            )
        case .noteHit:
            return DocViewerLaunchContext(
                logicalPageID: logicalPageID,
                preferredVersionID: pageVersionID,
                preferredSource: nil,
                preferredNoteID: noteID
            )
        case .versionMetadataHit:
            return DocViewerLaunchContext(
                logicalPageID: logicalPageID,
                preferredVersionID: pageVersionID,
                preferredSource: nil,
                preferredNoteID: nil
            )
        case .doc, .pageGroup, .page:
            return DocViewerLaunchContext(
                logicalPageID: logicalPageID,
                preferredVersionID: pageVersionID,
                preferredSource: nil,
                preferredNoteID: nil
            )
        }
    }
}
