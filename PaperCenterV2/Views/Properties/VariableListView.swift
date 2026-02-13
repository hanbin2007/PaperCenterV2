//
//  VariableListView.swift
//  PaperCenterV2
//
//  View for listing and managing variables
//

import SwiftUI
import SwiftData

struct VariableListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Variable.sortIndex) private var allVariables: [Variable]

    @State private var showingCreateSheet = false
    @State private var selectedVariables: Set<UUID> = []
    @State private var isEditMode = false
    @State private var showingDeleteConfirmation = false
    @State private var variableToEdit: Variable?
    @State private var filterScope: VariableScope?
    @State private var filterType: VariableType?
    @State private var searchText = ""

    private var viewModel: PropertyManagementViewModel {
        PropertyManagementViewModel(modelContext: modelContext)
    }

    private var filteredVariables: [Variable] {
        var variables = allVariables

        // Filter by scope if selected
        if let scope = filterScope {
            variables = variables.filter { $0.scope == scope }
        }

        // Filter by type if selected
        if let type = filterType {
            variables = variables.filter { $0.type == type }
        }

        // Filter by search text
        if !searchText.isEmpty {
            variables = variables.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }

        return variables.sortedByManualOrder()
    }

    var body: some View {
        List(selection: $selectedVariables) {
            if filteredVariables.isEmpty {
                ContentUnavailableView {
                    Label("No Variables", systemImage: "slider.horizontal.3")
                } description: {
                    Text("Create a variable to add structured metadata")
                }
            } else {
                ForEach(filteredVariables) { variable in
                    VariableRow(variable: variable)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isEditMode {
                                toggleSelection(variable)
                            } else {
                                variableToEdit = variable
                            }
                        }
                }
                .onMove(perform: moveVariables)
                .moveDisabled(!canReorderVariables)
            }
        }
        .environment(\.editMode, isEditMode ? .constant(.active) : .constant(.inactive))
        .navigationTitle("Variables")
        .searchable(text: $searchText, prompt: "Search variables")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation {
                        isEditMode.toggle()
                        if !isEditMode {
                            selectedVariables.removeAll()
                        }
                    }
                } label: {
                    Text(isEditMode ? "Done" : "Select")
                }
            }

            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    // Filter by scope
                    Menu("Filter by Scope") {
                        Button {
                            filterScope = nil
                        } label: {
                            Label("All Scopes", systemImage: filterScope == nil ? "checkmark" : "")
                        }

                        Divider()

                        ForEach(VariableScope.allCases, id: \.self) { scope in
                            Button {
                                filterScope = scope
                            } label: {
                                Label(scope.displayName, systemImage: filterScope == scope ? "checkmark" : scope.icon)
                            }
                        }
                    }

                    // Filter by type
                    Menu("Filter by Type") {
                        Button {
                            filterType = nil
                        } label: {
                            Label("All Types", systemImage: filterType == nil ? "checkmark" : "")
                        }

                        Divider()

                        ForEach(VariableType.allCases, id: \.self) { type in
                            Button {
                                filterType = type
                            } label: {
                                Label(type.displayName, systemImage: filterType == type ? "checkmark" : type.icon)
                            }
                        }
                    }
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isEditMode && !selectedVariables.isEmpty {
                VariableBatchActionsToolbar(
                    selectedCount: selectedVariables.count,
                    onDelete: {
                        showingDeleteConfirmation = true
                    }
                )
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            VariableEditView(viewModel: viewModel, variable: nil)
        }
        .sheet(item: $variableToEdit) { variable in
            VariableEditView(viewModel: viewModel, variable: variable)
        }
        .alert("Delete Variables", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                batchDelete()
            }
        } message: {
            Text("Are you sure you want to delete \(selectedVariables.count) variable(s)? Variables with assignments cannot be deleted.")
        }
    }

    private func toggleSelection(_ variable: Variable) {
        if selectedVariables.contains(variable.id) {
            selectedVariables.remove(variable.id)
        } else {
            selectedVariables.insert(variable.id)
        }
    }

    private func batchDelete() {
        let variablesToDelete = filteredVariables.filter { selectedVariables.contains($0.id) }
        viewModel.batchDeleteVariables(variablesToDelete)
        selectedVariables.removeAll()
    }

    private var canReorderVariables: Bool {
        filterScope == nil && filterType == nil && searchText.isEmpty
    }

    private func moveVariables(from source: IndexSet, to destination: Int) {
        guard canReorderVariables else { return }
        var ordered = filteredVariables
        ordered.move(fromOffsets: source, toOffset: destination)
        viewModel.reorderVariables(ordered)
    }
}

// MARK: - Supporting Views

private struct VariableRow: View {
    let variable: Variable

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: variable.color))
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(variable.name)
                    .font(.headline)

                HStack(spacing: 8) {
                    Label(variable.type.displayName, systemImage: variable.type.icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("•")
                        .foregroundStyle(.secondary)
                        .font(.caption)

                    Label(variable.scope.displayName, systemImage: variable.scope.icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if variable.type == .list, let options = variable.listOptions {
                    Text(options.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct VariableBatchActionsToolbar: View {
    let selectedCount: Int
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Text("\(selectedCount) selected")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}

// MARK: - Preview

#Preview("Variable List") {
    NavigationStack {
        VariableListView()
    }
    .modelContainer(for: [Variable.self])
}

#Preview("Variable List with Data") {
    let container = try! ModelContainer(for: Variable.self)

    let var1 = Variable(name: "Year", type: .int, scope: .all)
    let var2 = Variable(name: "Difficulty", type: .list, scope: .doc, listOptions: ["Easy", "Medium", "Hard"])
    let var3 = Variable(name: "Score", type: .int, scope: .page)

    container.mainContext.insert(var1)
    container.mainContext.insert(var2)
    container.mainContext.insert(var3)

    return NavigationStack {
        VariableListView()
    }
    .modelContainer(container)
}
