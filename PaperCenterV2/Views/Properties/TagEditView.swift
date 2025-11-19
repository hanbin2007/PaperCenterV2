//
//  TagEditView.swift
//  PaperCenterV2
//
//  View for creating and editing tags
//

import SwiftUI
import SwiftData

struct TagEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: PropertyManagementViewModel

    let tag: Tag? // nil for create, non-nil for edit
    let defaultTagGroup: TagGroup?

    @Query(sort: \TagGroup.sortIndex) private var tagGroups: [TagGroup]

    @State private var name: String = ""
    @State private var color: String = "#3B82F6"
    @State private var scope: TagScope = .all
    @State private var selectedTagGroup: TagGroup?

    private var isEditing: Bool {
        tag != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tag Details") {
                    TextField("Name", text: $name, prompt: Text("e.g., Mathematics, Hard"))
                        .autocorrectionDisabled()

                    TagScopeSelector(selectedScope: $scope)
                }

                Section {
                    TagColorPicker(selectedColor: $color)
                }

                Section("Tag Group") {
                    if tagGroups.isEmpty {
                        Text("No tag groups available")
                            .foregroundStyle(.secondary)
                            .italic()
                    } else {
                        Picker("Group", selection: $selectedTagGroup) {
                            Text("None")
                                .tag(nil as TagGroup?)

                            ForEach(tagGroups.sortedByManualOrder()) { group in
                                Text(group.name)
                                    .tag(group as TagGroup?)
                            }
                        }
                    }
                }

                Section("Preview") {
                    HStack {
                        Circle()
                            .fill(Color(hex: color) ?? .blue)
                            .frame(width: 20, height: 20)

                        Text(name.isEmpty ? "Tag Name" : name)
                            .font(.headline)

                        Spacer()

                        Label(scope.displayName, systemImage: scope.icon)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(isEditing ? "Edit Tag" : "New Tag")
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
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let tag = tag {
                    // Editing existing tag
                    name = tag.name
                    color = tag.color
                    scope = tag.scope
                    selectedTagGroup = tag.tagGroup
                } else {
                    // Creating new tag
                    selectedTagGroup = defaultTagGroup
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        if let tag = tag {
            // Update existing
            viewModel.updateTag(
                tag,
                name: trimmedName,
                color: color,
                scope: scope,
                tagGroup: selectedTagGroup
            )
        } else {
            // Create new
            viewModel.createTag(
                name: trimmedName,
                color: color,
                scope: scope,
                tagGroup: selectedTagGroup
            )
        }

        dismiss()
    }
}

// MARK: - Preview

#Preview("Create Tag") {
    let container = try! ModelContainer(for: Tag.self, TagGroup.self)
    let viewModel = PropertyManagementViewModel(modelContext: container.mainContext)

    // Create some tag groups for the preview
    let group1 = TagGroup(name: "Subject")
    let group2 = TagGroup(name: "Difficulty")
    container.mainContext.insert(group1)
    container.mainContext.insert(group2)

    return TagEditView(viewModel: viewModel, tag: nil, defaultTagGroup: nil)
        .modelContainer(container)
}

#Preview("Edit Tag") {
    let container = try! ModelContainer(for: Tag.self, TagGroup.self)
    let viewModel = PropertyManagementViewModel(modelContext: container.mainContext)

    let tagGroup = TagGroup(name: "Subject")
    container.mainContext.insert(tagGroup)

    let tag = Tag(name: "Mathematics", color: "#3B82F6", scope: .all, tagGroup: tagGroup)
    container.mainContext.insert(tag)

    return TagEditView(viewModel: viewModel, tag: tag, defaultTagGroup: nil)
        .modelContainer(container)
}
