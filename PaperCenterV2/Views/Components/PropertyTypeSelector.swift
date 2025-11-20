//
//  PropertyTypeSelector.swift
//  PaperCenterV2
//
//  Component for selecting variable types
//

import SwiftUI

/// Picker for selecting VariableType
struct VariableTypeSelector: View {
    @Binding var selectedType: VariableType

    var body: some View {
        Picker("Type", selection: $selectedType) {
            ForEach(VariableType.allCases, id: \.self) { type in
                Label(type.displayName, systemImage: type.icon)
                    .tag(type)
            }
        }
    }
}

// MARK: - Display Extensions

extension VariableType {
    var displayName: String {
        switch self {
        case .int:
            return "Integer"
        case .list:
            return "List"
        case .text:
            return "Text"
        case .date:
            return "Date"
        }
    }

    var icon: String {
        switch self {
        case .int:
            return "number"
        case .list:
            return "list.bullet"
        case .text:
            return "character.cursor.ibeam"
        case .date:
            return "calendar"
        }
    }

    var description: String {
        switch self {
        case .int:
            return "A whole number value"
        case .list:
            return "A single selection from predefined options"
        case .text:
            return "Free-form text entry"
        case .date:
            return "A calendar date without time"
        }
    }
}

// MARK: - Preview

#Preview("VariableType Selector") {
    @Previewable @State var type: VariableType = .int

    Form {
        VariableTypeSelector(selectedType: $type)

        Text("Description: \(type.description)")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
