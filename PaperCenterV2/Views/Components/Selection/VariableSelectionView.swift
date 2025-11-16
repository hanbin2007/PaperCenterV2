//
//  VariableSelectionView.swift
//  PaperCenterV2
//
//  View for selecting variables to assign to an entity
//

import SwiftUI
import SwiftData

/// View for selecting variables to assign to an entity
struct VariableSelectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Entity type for scope filtering
    let entityType: VariableEntityType

    /// The entity being assigned variables
    let entity: any VariableHolder

    /// Search query
    @State private var searchQuery = ""

    /// Currently assigned variable IDs
    @State private var assignedVariableIDs: Set<UUID> = []

    /// All available variables from database
    @Query(sort: \Variable.name) private var allVariables: [Variable]

    /// Entity type (Doc, Page, etc.) for fetching assignments
    @State private var entityDoc: Doc?

    /// Computed: Only show variables applicable to this entity type
    private var applicableVariables: [Variable] {
        allVariables.filter { $0.canApply(to: entityType) }
    }

    /// Computed: Filtered by search
    private var filteredVariables: [Variable] {
        if searchQuery.isEmpty {
            return applicableVariables
        }
        return applicableVariables.filter { variable in
            variable.name.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Search bar
                SearchBar(text: $searchQuery, placeholder: "Search variables...")
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                // Variables grid
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Available Variables")
                            .font(.headline)
                        Spacer()
                        Text("\(filteredVariables.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)

                    VariableGrid(
                        variables: filteredVariables,
                        assignedVariableIDs: $assignedVariableIDs,
                        toggleVariable: toggleVariable
                    )
                }

                // Empty state
                if filteredVariables.isEmpty {
                    EmptyStateView(
                        title: "No Variables Found",
                        subtitle: searchQuery.isEmpty
                            ? "No variables available for this entity type"
                            : "No variables match your search",
                        icon: "square.grid.3x1.folder.badge.plus"
                    )
                    .padding(.top, 40)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Select Variables")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .onAppear {
            loadAssignedVariables()
        }
    }

    /// Load currently assigned variable IDs
    private func loadAssignedVariables() {
        if let doc = entity as? Doc {
            assignedVariableIDs = Set(
                (doc.variableAssignments ?? []).compactMap { $0.variable?.id }
            )
            entityDoc = doc
        }
    }

    /// Toggle variable assignment
    private func toggleVariable(_ variable: Variable) {
        guard let doc = entityDoc else { return }

        if assignedVariableIDs.contains(variable.id) {
            // Remove assignment
            if let assignment = doc.variableAssignments?.first(where: { $0.variable?.id == variable.id }) {
                modelContext.delete(assignment)
                assignedVariableIDs.remove(variable.id)
            }
        } else {
            // Add assignment
            let assignment = DocVariableAssignment(
                variable: variable,
                doc: doc,
                intValue: nil,
                listValue: nil
            )
            modelContext.insert(assignment)

            if doc.variableAssignments == nil {
                doc.variableAssignments = []
            }
            doc.variableAssignments?.append(assignment)
            assignedVariableIDs.insert(variable.id)
        }

        // Save changes
        try? modelContext.save()
    }
}

/// Grid view displaying variables as selectable capsules
private struct VariableGrid: View {
    let variables: [Variable]
    @Binding var assignedVariableIDs: Set<UUID>
    let toggleVariable: (Variable) -> Void

    /// Grid layout with adaptive columns
    private let columns = [GridItem(.adaptive(minimum: 110))]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(variables) { variable in
                VariableCapsuleButton(
                    variable: variable,
                    isAssigned: assignedVariableIDs.contains(variable.id)
                ) {
                    toggleVariable(variable)
                }
            }
        }
        .padding(.horizontal)
    }
}

/// Selectable variable capsule with visual feedback
private struct VariableCapsuleButton: View {
    let variable: Variable
    let isAssigned: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                // Variable name
                Text(variable.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                // Type icon
                Image(systemName: variable.type.icon)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                Capsule()
                    .fill(Color(hex: variable.color).opacity(isAssigned ? 0.25 : 0.12))
            )
            .foregroundColor(Color(hex: variable.color))
            .overlay(
                Capsule()
                    .stroke(
                        Color(hex: variable.color).opacity(isAssigned ? 0.6 : 0.3),
                        lineWidth: isAssigned ? 2 : 0.5
                    )
            )
            .overlay(alignment: .topTrailing) {
                if isAssigned {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color(hex: variable.color))
                        .background(
                            Circle()
                                .fill(.background)
                                .scaleEffect(0.8)
                        )
                        .offset(x: 4, y: -4)
                }
            }
            .scaleEffect(isAssigned ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isAssigned)
    }
}

// MARK: - Display Extensions

extension VariableEntityType {
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
        }
    }
}

// MARK: - Preview

#Preview("VariableSelectionView") {
    let container = try! ModelContainer(for: Variable.self, Doc.self)

    // Create sample variables
    let yearVar = Variable(name: "Year", type: .int, scope: .all, color: "#3B82F6")
    let difficultyVar = Variable(
        name: "Difficulty Level",
        type: .list,
        scope: .doc,
        color: "#EF4444",
        listOptions: ["Easy", "Medium", "Hard"]
    )
    let scoreVar = Variable(name: "Score", type: .int, scope: .page, color: "#10B981")

    container.mainContext.insert(yearVar)
    container.mainContext.insert(difficultyVar)
    container.mainContext.insert(scoreVar)

    return NavigationStack {
        VariableSelectionView(
            entityType: .doc,
            entity: Doc(title: "Sample")
        )
    }
    .modelContainer(container)
}

#Preview("VariableSelectionView - With Assignments") {
    let container = try! ModelContainer(for: Variable.self, Doc.self)

    // Create sample variables
    let yearVar = Variable(name: "Year", type: .int, scope: .all, color: "#3B82F6")
    let difficultyVar = Variable(
        name: "Difficulty Level",
        type: .list,
        scope: .doc,
        color: "#EF4444",
        listOptions: ["Easy", "Medium", "Hard"]
    )

    container.mainContext.insert(yearVar)
    container.mainContext.insert(difficultyVar)

    // Create doc with one variable assigned
    let doc = Doc(title: "Sample Document")
    let assignment = DocVariableAssignment(variable: yearVar, doc: doc)
    container.mainContext.insert(doc)
    container.mainContext.insert(assignment)
    doc.variableAssignments = [assignment]

    return NavigationStack {
        VariableSelectionView(
            entityType: .doc,
            entity: doc
        )
    }
    .modelContainer(container)
}
