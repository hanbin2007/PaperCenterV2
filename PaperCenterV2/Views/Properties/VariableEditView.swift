//
//  VariableEditView.swift
//  PaperCenterV2
//
//  View for creating and editing variables
//

import SwiftUI
import SwiftData

struct VariableEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: PropertyManagementViewModel

    let variable: Variable? // nil for create, non-nil for edit

    @State private var name: String = ""
    @State private var type: VariableType = .int
    @State private var scope: VariableScope = .all
    @State private var color: String = "#8B5CF6"
    @State private var listOptions: [String] = ["Option 1", "Option 2"]

    private var isEditing: Bool {
        variable != nil
    }

    private var canChangeType: Bool {
        // Can only change type when creating, not editing
        variable == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Variable Details") {
                    TextField("Name", text: $name, prompt: Text("e.g., Year, Score, Difficulty"))
                        .autocorrectionDisabled()

                    VariableScopeSelector(selectedScope: $scope)
                }

                Section {
                    TagColorPicker(selectedColor: $color)
                }

                Section("Type") {
                    VariableTypeSelector(selectedType: $type)
                        .disabled(!canChangeType)

                    Text(type.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !canChangeType {
                        Text("Type cannot be changed after creation")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                if type == .list {
                    Section {
                        ListOptionsEditor(options: $listOptions)
                    }
                }

                Section("Preview") {
                    HStack {
                        Circle()
                            .fill(Color(hex: color) ?? .purple)
                            .frame(width: 20, height: 20)

                        Text(name.isEmpty ? "Variable Name" : name)
                            .font(.headline)

                        Spacer()

                        Label(scope.displayName, systemImage: scope.icon)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if type == .list && !listOptions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Options:")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ForEach(listOptions, id: \.self) { option in
                                Text("• \(option)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Variable" : "New Variable")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Create") {
                        save()
                    }
                    .disabled(!isValidForm)
                }
            }
            .onAppear {
                if let variable = variable {
                    // Editing existing variable
                    name = variable.name
                    type = variable.type
                    scope = variable.scope
                    color = variable.color
                    if let options = variable.listOptions {
                        listOptions = options
                    }
                }
            }
        }
    }

    private var isValidForm: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return false }

        if type == .list {
            return listOptions.count >= 2 && listOptions.allSatisfy { !$0.isEmpty }
        }

        return true
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        if let variable = variable {
            // Update existing
            viewModel.updateVariable(
                variable,
                name: trimmedName,
                scope: scope,
                color: color,
                listOptions: type == .list ? listOptions : nil
            )
        } else {
            // Create new
            viewModel.createVariable(
                name: trimmedName,
                type: type,
                scope: scope,
                color: color,
                listOptions: type == .list ? listOptions : nil
            )
        }

        dismiss()
    }
}

// MARK: - Preview

#Preview("Create Variable - Int") {
    let container = try! ModelContainer(for: Variable.self)
    let viewModel = PropertyManagementViewModel(modelContext: container.mainContext)

    return VariableEditView(viewModel: viewModel, variable: nil)
        .modelContainer(container)
}

#Preview("Create Variable - List") {
    let container = try! ModelContainer(for: Variable.self)
    let viewModel = PropertyManagementViewModel(modelContext: container.mainContext)

    return VariableEditView(viewModel: viewModel, variable: nil)
        .modelContainer(container)
        .onAppear {
            // Simulate selecting list type
        }
}

#Preview("Edit Variable") {
    let container = try! ModelContainer(for: Variable.self)
    let viewModel = PropertyManagementViewModel(modelContext: container.mainContext)

    let variable = Variable(
        name: "Difficulty",
        type: .list,
        scope: .doc,
        listOptions: ["Easy", "Medium", "Hard"]
    )
    container.mainContext.insert(variable)

    return VariableEditView(viewModel: viewModel, variable: variable)
        .modelContainer(container)
}
