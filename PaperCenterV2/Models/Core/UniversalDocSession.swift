//
//  UniversalDocSession.swift
//  PaperCenterV2
//
//  Session-layer types for UniversalDoc Viewer.
//

import Foundation

enum UniversalDocViewerSource: String, CaseIterable, Codable, Identifiable {
    case display
    case original
    case ocr

    var id: String { rawValue }

    var title: String {
        switch self {
        case .display:
            return "Display"
        case .original:
            return "Original"
        case .ocr:
            return "OCR"
        }
    }
}

struct VersionInheritanceOptions: Codable, Equatable {
    var inheritTags: Bool
    var inheritVariables: Bool
    var inheritNoteBlocks: Bool

    static let none = VersionInheritanceOptions(
        inheritTags: false,
        inheritVariables: false,
        inheritNoteBlocks: false
    )

    static let metadataOnly = VersionInheritanceOptions(
        inheritTags: true,
        inheritVariables: true,
        inheritNoteBlocks: false
    )

    static let all = VersionInheritanceOptions(
        inheritTags: true,
        inheritVariables: true,
        inheritNoteBlocks: true
    )
}

struct UniversalDocVersionOption: Identifiable, Hashable {
    let id: UUID
    let pdfBundleID: UUID
    let pageNumber: Int
    let createdAt: Date
    let ordinal: Int
    let isCurrentDefault: Bool
}

struct UniversalDocLogicalPageSlot: Identifiable, Hashable {
    let id: UUID
    let pageID: UUID
    let versionOptions: [UniversalDocVersionOption]
    let defaultVersionID: UUID
    let defaultSource: UniversalDocViewerSource
    let canPreviewOtherVersions: Bool
    let canSwitchSource: Bool
    let canAnnotate: Bool
}

enum UniversalDocSessionViewMode: String, Codable {
    case paged
}

struct UniversalDocSession {
    let docID: UUID
    let slots: [UniversalDocLogicalPageSlot]
    let viewMode: UniversalDocSessionViewMode
}
