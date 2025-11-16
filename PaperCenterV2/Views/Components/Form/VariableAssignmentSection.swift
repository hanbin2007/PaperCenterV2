//
//  VariableAssignmentSection.swift
//  PaperCenterV2
//
//  Form component for displaying and editing variable assignments
//

import SwiftUI
import SwiftData

/// Section view for displaying variable assignments within a Form
/// Shows assigned variables with values and navigates to selection screen
struct VariableAssignmentSection: View {
    @Environment(\.modelContext) private var modelContext

    /// The document to which variables are assigned
    @Bindable var doc: Doc

    /// Entity type for scope checking
    let entityType: VariableEntityType

    /// State for showing selection sheet
    @State private var showSelection = false

    /// Formatted variables for display
    private var formattedVariables: [FormattedVariable] {
        guard let assignments = doc.variableAssignments else { return [] }
        return MetadataFormattingService.formatDocVariables(assignments)
    }

    /// Variables with values set
    private var variablesWithValues: [FormattedVariable] {
        formattedVariables.filter { $0.value != "—" }
    }

    /// Variables without values
    private var variablesWithoutValues: Int {
        formattedVariables.count - variablesWithValues.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main navigation to variable selection
            NavigationLink {
                VariableSelectionView(
                    entityType: entityType,
                    entity: doc
                )
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Variables")
                            .font(.body)

                        if !formattedVariables.isEmpty {
                            Text("\(variablesWithValues.count) set, \(variablesWithoutValues) unset")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("No variables assigned")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(.purple)
                }
            }

            Divider()
                .padding(.vertical, 8)

            // List of assigned variables with values (if any)
            if !variablesWithValues.isEmpty {
                ForEach(variablesWithValues) { variable in
                    VariableValueRow(variable: variable)
                }
            }

            // Prompt to assign variables if none
            if formattedVariables.isEmpty {
                Button {
                    showSelection = true
                } label: {
                    Label("Assign Variables", systemImage: "plus")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                .padding(.top, 4)
                .sheet(isPresented: $showSelection) {
                    NavigationStack {
                        VariableSelectionView(
                            entityType: entityType,
                            entity: doc
                        )
                    }
                }
            }
        }
    }
}

/// Row showing a variable with its current value
private struct VariableValueRow: View {
    let variable: FormattedVariable

    var body: some View {
        HStack(spacing: 8) {
            // Color indicator
            Circle()
                .fill(Color(hex: variable.color))
                .frame(width: 8, height: 8)

            // Variable name
            Text(variable.name)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            // Value (in capsule if set)
            if variable.value != "—" {
                Text(variable.value)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(hex: variable.color).opacity(0.1))
                    .foregroundColor(Color(hex: variable.color))
                    .clipShape(Capsule())
            } else {
                Text("Not set")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .italic()
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Entity Type

/// Protocol for entities that can have variables
protocol VariableHolder {
    var variableAssignments: [DocVariableAssignment]? { get set }
}

// MARK: - Preview

#Preview("VariableAssignmentSection - With Values") {
    let container = try! ModelContainer(for: Variable.self, Doc.self)
    let yearVar = Variable(name: "Year", type: .int, scope: .doc, color: "#3B82F6")
    let difficultyVar = Variable(
        name: "Difficulty",
        type: .list,
        scope: .doc,
        color: "#EF4444",
        listOptions: ["Easy", "Medium", "Hard"]
    )
    container.mainContext.insert(yearVar)
    container.mainContext.insert(difficultyVar)

    let doc = Doc(title: "Sample Document")
    let assignment1 = DocVariableAssignment(variable: yearVar, doc: doc, intValue: 2023)
    let assignment2 = DocVariableAssignment(variable: difficultyVar, doc: doc, listValue: "Medium")
    container.mainContext.insert(doc)
    container.mainContext.insert(assignment1)
    container.mainContext.insert(assignment2)
    doc.variableAssignments = [assignment1, assignment2]

    return Form {
        VariableAssignmentSection(
            doc: doc,
            entityType: .doc
        )
    }
    .modelContainer(container)
}

#Preview("VariableAssignmentSection - Empty") {
    let container = try! ModelContainer(for: Variable.self, Doc.self)

    let doc = Doc(title: "Sample Document")
    container.mainContext.insert(doc)

    return Form {
        VariableAssignmentSection(
            doc: doc,
            entityType: .doc
        )
    }
    .modelContainer(container)
}
