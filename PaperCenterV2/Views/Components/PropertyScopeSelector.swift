//
//  PropertyScopeSelector.swift
//  PaperCenterV2
//
//  Component for selecting property scopes (Tags and Variables)
//

import SwiftUI

/// Picker for selecting TagScope
struct TagScopeSelector: View {
    @Binding var selectedScope: TagScope

    var body: some View {
        Picker("Scope", selection: $selectedScope) {
            ForEach(TagScope.allCases, id: \.self) { scope in
                Text(scope.displayName).tag(scope)
            }
        }
    }
}

/// Picker for selecting VariableScope
struct VariableScopeSelector: View {
    @Binding var selectedScope: VariableScope

    var body: some View {
        Picker("Scope", selection: $selectedScope) {
            ForEach(VariableScope.allCases, id: \.self) { scope in
                Text(scope.displayName).tag(scope)
            }
        }
    }
}

// MARK: - Display Name Extensions

extension TagScope {
    var displayName: String {
        switch self {
        case .pdfBundle:
            return "PDF Bundle"
        case .doc:
            return "Document"
        case .pageGroup:
            return "Page Group"
        case .page:
            return "Page"
        case .noteBlock:
            return "Note Block"
        case .docAndBelow:
            return "Doc & Below"
        case .all:
            return "All Entities"
        }
    }

    var icon: String {
        switch self {
        case .pdfBundle:
            return "folder"
        case .doc:
            return "doc.text"
        case .pageGroup:
            return "rectangle.stack"
        case .page:
            return "doc.plaintext"
        case .noteBlock:
            return "text.badge.plus"
        case .docAndBelow:
            return "chart.bar.yaxis"
        case .all:
            return "square.stack.3d.up"
        }
    }
}

extension VariableScope {
    var displayName: String {
        switch self {
        case .pdfBundle:
            return "PDF Bundle"
        case .doc:
            return "Document"
        case .pageGroup:
            return "Page Group"
        case .page:
            return "Page"
        case .noteBlock:
            return "Note Block"
        case .all:
            return "All Entities"
        }
    }

    var icon: String {
        switch self {
        case .pdfBundle:
            return "folder"
        case .doc:
            return "doc.text"
        case .pageGroup:
            return "rectangle.stack"
        case .page:
            return "doc.plaintext"
        case .noteBlock:
            return "text.badge.plus"
        case .all:
            return "square.stack.3d.up"
        }
    }
}

// MARK: - Preview

#Preview("TagScope Selector") {
    @Previewable @State var scope: TagScope = .all

    Form {
        TagScopeSelector(selectedScope: $scope)
    }
}

#Preview("VariableScope Selector") {
    @Previewable @State var scope: VariableScope = .all

    Form {
        VariableScopeSelector(selectedScope: $scope)
    }
}
