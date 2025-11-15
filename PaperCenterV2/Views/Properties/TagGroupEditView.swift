//
//  TagGroupEditView.swift
//  PaperCenterV2
//
//  View for creating and editing tag groups
//

import SwiftUI
import SwiftData

struct TagGroupEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: PropertyManagementViewModel

    let tagGroup: TagGroup? // nil for create, non-nil for edit

    @State private var name: String = ""

    private var isEditing: Bool {
        tagGroup != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tag Group Details") {
                    TextField("Name", text: $name, prompt: Text("e.g., Subject, Difficulty"))
                        .autocorrectionDisabled()
                }

                if isEditing, let tagGroup = tagGroup {
                    Section {
                        HStack {
                            Text("Tags in this group")
                                .foregroundStyle(.secondary)

                            Spacer()

                            if let tags = tagGroup.tags, !tags.isEmpty {
                                Text("\(tags.count)")
                                    .foregroundStyle(.blue)
                                    .fontWeight(.semibold)
                            } else {
                                Text("0")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } footer: {
                        Text("Tap on the tag group in the list to manage its tags")
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Tag Group" : "New Tag Group")
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
                if let tagGroup = tagGroup {
                    name = tagGroup.name
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        if let tagGroup = tagGroup {
            // Update existing
            viewModel.updateTagGroup(tagGroup, name: trimmedName)
        } else {
            // Create new
            viewModel.createTagGroup(name: trimmedName)
        }

        dismiss()
    }
}

// MARK: - Preview

#Preview("Create Tag Group") {
    @Previewable @State var viewModel = PropertyManagementViewModel(
        modelContext: ModelContext(
            try! ModelContainer(for: TagGroup.self, Tag.self)
        )
    )

    TagGroupEditView(viewModel: viewModel, tagGroup: nil)
}

#Preview("Edit Tag Group") {
    @Previewable @State var viewModel: PropertyManagementViewModel = {
        let container = try! ModelContainer(for: TagGroup.self, Tag.self)
        let context = ModelContext(container)

        let tagGroup = TagGroup(name: "Subject")
        context.insert(tagGroup)

        let tag1 = Tag(name: "Mathematics", color: "#3B82F6", scope: .all, tagGroup: tagGroup)
        let tag2 = Tag(name: "Physics", color: "#10B981", scope: .all, tagGroup: tagGroup)
        context.insert(tag1)
        context.insert(tag2)

        return PropertyManagementViewModel(modelContext: context)
    }()

    let container = try! ModelContainer(for: TagGroup.self, Tag.self)
    let tagGroup = TagGroup(name: "Subject")
    container.mainContext.insert(tagGroup)

    return TagGroupEditView(viewModel: viewModel, tagGroup: tagGroup)
}
