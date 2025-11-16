//
//  VariableValueEditor.swift
//  PaperCenterV2
//
//  Form component for editing values of assigned variables
//  Supports int (TextField) and list (Picker) types
//

import SwiftUI
import SwiftData

/// View for editing values of assigned variables within a Form
/// Supports both int and list variable types with appropriate controls
struct VariableValueEditor: View {
    @Environment(\.modelContext) private var modelContext

    /// Variable assignments being edited
    var assignments: [DocVariableAssignment]

    /// Validation errors by variable ID
    @State private var validationErrors: [String: String] = [:]

    var body: some View {
        ForEach(assignments) { assignment in
            if let variable = assignment.variable {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        // Variable info header
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(hex: variable.color) ?? .purple)
                                .frame(width: 12, height: 12)

                            Text(variable.name)
                                .font(.headline)

                            Spacer()

                            // Type indicator
                            Label(
                                variable.type.displayName,
                                systemImage: variable.type.icon
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Divider()

                        // Value input based on type
                        VStack(alignment: .leading, spacing: 8) {
                            switch variable.type {
                            case .int:
                                IntValueEditor(
                                    assignment: assignment,
                                    validationError: $validationErrors[variable.id.uuidString]
                                )
                            case .list:
                                ListValueEditor(
                                    assignment: assignment,
                                    variable: variable
                                )
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

/// Editor for int type variables
private struct IntValueEditor: View {
    @Bindable var assignment: DocVariableAssignment
    @Binding var validationError: String?

    @State private var textValue: String = ""
    @State private var hasAppeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Enter value", text: $textValue)
                    .keyboardType(.numberPad)
                    .onChange(of: textValue) { oldValue, newValue in
                        validateAndSave(newValue: newValue)
                    }
                    .onAppear {
                        if !hasAppeared {
                            textValue = assignment.intValue.map { String($0) } ?? ""
                            hasAppeared = true
                        }
                    }

                if assignment.intValue != nil {
                    Button {
                        assignment.intValue = nil
                        textValue = ""
                        validationError = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let error = validationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func validateAndSave(newValue: String) {
        if newValue.isEmpty {
            assignment.intValue = nil
            validationError = nil
            return
        }

        if let intValue = Int(newValue) {
            assignment.intValue = intValue
            validationError = nil
        } else {
            validationError = "Please enter a valid number"
        }
    }
}

/// Editor for list type variables
private struct ListValueEditor: View {
    @Bindable var assignment: DocVariableAssignment
    let variable: Variable

    @State private var selectedOption: String?

    var body: some View {
        Menu {
            // Option to clear selection
            Button {
                assignment.listValue = nil
            } label: {
                Label("Clear Selection", systemImage: "xmark")
            }

            Divider()

            // Available options
            ForEach(variable.listOptions ?? [], id: \.self) { option in
                Button {
                    assignment.listValue = option
                } label: {
                    if assignment.listValue == option {
                        Label(option, systemImage: "checkmark")
                    } else {
                        Text(option)
                    }
                }
            }
        } label: {
            HStack {
                if let value = assignment.listValue {
                    Text(value)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background((Color(hex: variable.color) ?? .purple).opacity(0.1))
                        .foregroundColor(Color(hex: variable.color) ?? .purple)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke((Color(hex: variable.color) ?? .purple).opacity(0.2), lineWidth: 0.5)
                        )
                } else {
                    Text("Select value...")
                        .foregroundStyle(.secondary)
                        .italic()
                }

                Spacer()

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("VariableValueEditor - Mixed Types") {
    let container = try! ModelContainer(for: Variable.self, Doc.self)

    // Create sample variables
    let yearVar = Variable(name: "Year", type: .int, scope: .doc, color: "#3B82F6")
    let difficultyVar = Variable(
        name: "Difficulty",
        type: .list,
        scope: .doc,
        color: "#EF4444",
        listOptions: ["Easy", "Medium", "Hard"]
    )
    let scoreVar = Variable(name: "Score", type: .int, scope: .doc, color: "#10B981")

    container.mainContext.insert(yearVar)
    container.mainContext.insert(difficultyVar)
    container.mainContext.insert(scoreVar)

    // Create doc with assignments
    let doc = Doc(title: "Sample Document")

    let assignment1 = DocVariableAssignment(variable: yearVar, doc: doc, intValue: 2023)
    let assignment2 = DocVariableAssignment(variable: difficultyVar, doc: doc, listValue: "Medium")
    let assignment3 = DocVariableAssignment(variable: scoreVar, doc: doc, intValue: nil)

    container.mainContext.insert(doc)
    container.mainContext.insert(assignment1)
    container.mainContext.insert(assignment2)
    container.mainContext.insert(assignment3)

    return Form {
        VariableValueEditor(assignments: [assignment1, assignment2, assignment3])
    }
    .modelContainer(container)
}
