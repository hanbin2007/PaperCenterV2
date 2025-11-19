//
//  PropertyOrdering.swift
//  PaperCenterV2
//
//  Shared ordering helpers for Tag/TagGroup/Variable collections.
//

import Foundation

extension Sequence where Element == TagGroup {
    /// Sorts tag groups by their manual sort index, falling back to name.
    func sortedByManualOrder() -> [TagGroup] {
        sorted { lhs, rhs in
            if lhs.sortIndex == rhs.sortIndex {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.sortIndex < rhs.sortIndex
        }
    }
}

extension Sequence where Element == Tag {
    /// Sorts tags by their parent group's order, then the tag's order, then name.
    func sortedByManualOrder() -> [Tag] {
        sorted { lhs, rhs in
            let lhsGroupIndex = lhs.tagGroup?.sortIndex ?? Int.max
            let rhsGroupIndex = rhs.tagGroup?.sortIndex ?? Int.max
            if lhsGroupIndex != rhsGroupIndex {
                return lhsGroupIndex < rhsGroupIndex
            }

            let lhsGroupName = lhs.tagGroup?.name ?? ""
            let rhsGroupName = rhs.tagGroup?.name ?? ""
            if lhsGroupName.caseInsensitiveCompare(rhsGroupName) != .orderedSame {
                return lhsGroupName.localizedCaseInsensitiveCompare(rhsGroupName) == .orderedAscending
            }

            if lhs.sortIndex == rhs.sortIndex {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.sortIndex < rhs.sortIndex
        }
    }
}

extension Sequence where Element == Variable {
    /// Sorts variables by their manual sort index, falling back to name.
    func sortedByManualOrder() -> [Variable] {
        sorted { lhs, rhs in
            if lhs.sortIndex == rhs.sortIndex {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.sortIndex < rhs.sortIndex
        }
    }
}
