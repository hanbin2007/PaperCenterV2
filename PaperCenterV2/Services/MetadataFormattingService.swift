//
//  MetadataFormattingService.swift
//  PaperCenterV2
//
//  Created by Claude on 2025-11-09.
//

import Foundation

/// Service for formatting metadata (tags and variables) for display
@MainActor
final class MetadataFormattingService {

    // MARK: - Tag Formatting

    /// Group tags by their TagGroup for display
    /// - Parameter tags: Tags to group
    /// - Returns: Array of tuples with group name and tags
    static func groupTags(_ tags: [Tag]) -> [(groupName: String, tags: [Tag])] {
        let orderedTags = tags.sortedByManualOrder()
        var grouped: [(id: UUID?, name: String, tags: [Tag])] = []
        var indexMap: [UUID?: Int] = [:]

        for tag in orderedTags {
            let key = tag.tagGroup?.id
            if let index = indexMap[key] {
                grouped[index].tags.append(tag)
            } else {
                indexMap[key] = grouped.count
                grouped.append((
                    id: key,
                    name: tag.tagGroup?.name ?? "Other",
                    tags: [tag]
                ))
            }
        }

        return grouped.map { (groupName: $0.name, tags: $0.tags) }
    }

    // MARK: - Variable Formatting

    /// Format variable assignments for display
    /// - Parameter assignments: Variable assignments to format
    /// - Returns: Array of formatted variable data
    static func formatDocVariables(_ assignments: [DocVariableAssignment]) -> [FormattedVariable] {
        return assignments.compactMap { assignment in
            guard let variable = assignment.variable else { return nil }

            let value: String
            switch variable.type {
            case .int:
                value = assignment.intValue.map { String($0) } ?? "—"
            case .list:
                value = assignment.listValue ?? "—"
            case .text:
                let trimmed = assignment.textValue?.trimmingCharacters(in: .whitespacesAndNewlines)
                value = trimmed?.isEmpty == false ? trimmed! : "—"
            case .date:
                if let date = assignment.dateValue {
                    value = Self.dateFormatter.string(from: date)
                } else {
                    value = "—"
                }
            }

            return FormattedVariable(
                name: variable.name,
                value: value,
                type: variable.type,
                color: variable.color
            )
        }.sorted { $0.name < $1.name }
    }

    /// Format PDFBundle variable assignments for display
    /// - Parameter assignments: Variable assignments to format
    /// - Returns: Array of formatted variable data
    static func formatPDFBundleVariables(_ assignments: [PDFBundleVariableAssignment]) -> [FormattedVariable] {
        return assignments.compactMap { assignment in
            guard let variable = assignment.variable else { return nil }

            let value: String
            switch variable.type {
            case .int:
                value = assignment.intValue.map { String($0) } ?? "—"
            case .list:
                value = assignment.listValue ?? "—"
            case .text:
                let trimmed = assignment.textValue?.trimmingCharacters(in: .whitespacesAndNewlines)
                value = trimmed?.isEmpty == false ? trimmed! : "—"
            case .date:
                if let date = assignment.dateValue {
                    value = Self.dateFormatter.string(from: date)
                } else {
                    value = "—"
                }
            }

            return FormattedVariable(
                name: variable.name,
                value: value,
                type: variable.type,
                color: variable.color
            )
        }.sorted { $0.name < $1.name }
    }

    /// Format PageGroup variable assignments for display
    /// - Parameter assignments: Variable assignments to format
    /// - Returns: Array of formatted variable data
    static func formatPageGroupVariables(_ assignments: [PageGroupVariableAssignment]) -> [FormattedVariable] {
        return assignments.compactMap { assignment in
            guard let variable = assignment.variable else { return nil }

            let value: String
            switch variable.type {
            case .int:
                value = assignment.intValue.map { String($0) } ?? "—"
            case .list:
                value = assignment.listValue ?? "—"
            case .text:
                let trimmed = assignment.textValue?.trimmingCharacters(in: .whitespacesAndNewlines)
                value = trimmed?.isEmpty == false ? trimmed! : "—"
            case .date:
                if let date = assignment.dateValue {
                    value = Self.dateFormatter.string(from: date)
                } else {
                    value = "—"
                }
            }

            return FormattedVariable(
                name: variable.name,
                value: value,
                type: variable.type,
                color: variable.color
            )
        }.sorted { $0.name < $1.name }
    }

    /// Format Page variable assignments for display
    /// - Parameter assignments: Variable assignments to format
    /// - Returns: Array of formatted variable data
    static func formatPageVariables(_ assignments: [PageVariableAssignment]) -> [FormattedVariable] {
        return assignments.compactMap { assignment in
            guard let variable = assignment.variable else { return nil }

            let value: String
            switch variable.type {
            case .int:
                value = assignment.intValue.map { String($0) } ?? "—"
            case .list:
                value = assignment.listValue ?? "—"
            case .text:
                let trimmed = assignment.textValue?.trimmingCharacters(in: .whitespacesAndNewlines)
                value = trimmed?.isEmpty == false ? trimmed! : "—"
            case .date:
                if let date = assignment.dateValue {
                    value = Self.dateFormatter.string(from: date)
                } else {
                    value = "—"
                }
            }

            return FormattedVariable(
                name: variable.name,
                value: value,
                type: variable.type,
                color: variable.color
            )
        }.sorted { $0.name < $1.name }
    }
}

// MARK: - Supporting Types

/// Formatted variable data for display
struct FormattedVariable: Identifiable {
    let id = UUID()
    let name: String
    let value: String
    let type: VariableType
    let color: String
}

private extension MetadataFormattingService {
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
