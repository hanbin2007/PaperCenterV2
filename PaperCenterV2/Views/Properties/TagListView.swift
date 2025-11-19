//
//  TagListView.swift
//  PaperCenterV2
//
//  View for listing and managing tags
//

import SwiftUI
import SwiftData

struct TagListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Tag.sortIndex) private var allTags: [Tag]

    // Optional filter by tag group
    let filterTagGroup: TagGroup?

    @State private var showingCreateSheet = false
    @State private var selectedTags: Set<UUID> = []
    @State private var isEditMode = false
    @State private var showingDeleteConfirmation = false
    @State private var showingBatchUpdateSheet = false
    @State private var tagToEdit: Tag?
    @State private var filterScope: TagScope?
    @State private var searchText = ""

    private var viewModel: PropertyManagementViewModel {
        PropertyManagementViewModel(modelContext: modelContext)
    }

    private var filteredTags: [Tag] {
        var tags = allTags

        // Filter by tag group if specified
        if let filterTagGroup = filterTagGroup {
            tags = tags.filter { $0.tagGroup?.id == filterTagGroup.id }
        }

        // Filter by scope if selected
        if let scope = filterScope {
            tags = tags.filter { $0.scope == scope }
        }

        // Filter by search text
        if !searchText.isEmpty {
            tags = tags.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }

        return tags.sortedByManualOrder()
    }

    init(filterTagGroup: TagGroup? = nil) {
        self.filterTagGroup = filterTagGroup
    }

    var body: some View {
        List(selection: $selectedTags) {
            if filteredTags.isEmpty {
                ContentUnavailableView {
                    Label("No Tags", systemImage: "tag")
                } description: {
                    Text(filterTagGroup != nil ? "No tags in this group" : "Create a tag to get started")
                }
            } else {
                ForEach(filteredTags) { tag in
                    TagRow(tag: tag)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isEditMode {
                                toggleSelection(tag)
                            } else {
                                tagToEdit = tag
                            }
                        }
                }
            }
        }
        .environment(\.editMode, isEditMode ? .constant(.active) : .constant(.inactive))
        .navigationTitle(filterTagGroup?.name ?? "Tags")
        .searchable(text: $searchText, prompt: "Search tags")
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
                            selectedTags.removeAll()
                        }
                    }
                } label: {
                    Text(isEditMode ? "Done" : "Select")
                }
            }

            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button {
                        filterScope = nil
                    } label: {
                        Label("All Scopes", systemImage: filterScope == nil ? "checkmark" : "")
                    }

                    Divider()

                    ForEach(TagScope.allCases, id: \.self) { scope in
                        Button {
                            filterScope = scope
                        } label: {
                            Label(scope.displayName, systemImage: filterScope == scope ? "checkmark" : scope.icon)
                        }
                    }
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isEditMode && !selectedTags.isEmpty {
                TagBatchActionsToolbar(
                    selectedCount: selectedTags.count,
                    onUpdateColor: {
                        showingBatchUpdateSheet = true
                    },
                    onDelete: {
                        showingDeleteConfirmation = true
                    }
                )
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            TagEditView(viewModel: viewModel, tag: nil, defaultTagGroup: filterTagGroup)
        }
        .sheet(item: $tagToEdit) { tag in
            TagEditView(viewModel: viewModel, tag: tag, defaultTagGroup: nil)
        }
        .sheet(isPresented: $showingBatchUpdateSheet) {
            TagBatchUpdateView(
                viewModel: viewModel,
                selectedTags: filteredTags.filter { selectedTags.contains($0.id) }
            )
        }
        .alert("Delete Tags", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                batchDelete()
            }
        } message: {
            Text("Are you sure you want to delete \(selectedTags.count) tag(s)?")
        }
    }

    private func toggleSelection(_ tag: Tag) {
        if selectedTags.contains(tag.id) {
            selectedTags.remove(tag.id)
        } else {
            selectedTags.insert(tag.id)
        }
    }

    private func batchDelete() {
        let tagsToDelete = filteredTags.filter { selectedTags.contains($0.id) }
        viewModel.batchDeleteTags(tagsToDelete)
        selectedTags.removeAll()
    }
}

// MARK: - Supporting Views

private struct TagRow: View {
    let tag: Tag

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: tag.color) ?? .blue)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(tag.name)
                    .font(.headline)

                HStack(spacing: 8) {
                    Label(tag.scope.displayName, systemImage: tag.scope.icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let tagGroup = tag.tagGroup {
                        Text("•")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(tagGroup.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct TagBatchActionsToolbar: View {
    let selectedCount: Int
    let onUpdateColor: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Text("\(selectedCount) selected")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: onUpdateColor) {
                Label("Update", systemImage: "paintbrush")
            }
            .buttonStyle(.bordered)

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}

// MARK: - Batch Update View

private struct TagBatchUpdateView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: PropertyManagementViewModel
    let selectedTags: [Tag]

    @State private var newColor: String?
    @State private var newScope: TagScope?
    @State private var updateColor = false
    @State private var updateScope = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Update Options") {
                    Toggle("Update Color", isOn: $updateColor)
                    Toggle("Update Scope", isOn: $updateScope)
                }

                if updateColor {
                    Section("New Color") {
                        TagColorPicker(selectedColor: Binding(
                            get: { newColor ?? "#3B82F6" },
                            set: { newColor = $0 }
                        ))
                    }
                }

                if updateScope {
                    Section("New Scope") {
                        TagScopeSelector(selectedScope: Binding(
                            get: { newScope ?? .all },
                            set: { newScope = $0 }
                        ))
                    }
                }

                Section {
                    Text("This will update \(selectedTags.count) tag(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Batch Update Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Update") {
                        performUpdate()
                        dismiss()
                    }
                    .disabled(!updateColor && !updateScope)
                }
            }
        }
    }

    private func performUpdate() {
        viewModel.batchUpdateTags(
            selectedTags,
            color: updateColor ? newColor : nil,
            scope: updateScope ? newScope : nil
        )
    }
}

// MARK: - Preview

#Preview("Tag List") {
    NavigationStack {
        TagListView()
    }
    .modelContainer(for: [Tag.self, TagGroup.self])
}

#Preview("Tag List with Filter") {
    let container = try! ModelContainer(for: Tag.self, TagGroup.self)
    let tagGroup = TagGroup(name: "Subject")
    container.mainContext.insert(tagGroup)

    return NavigationStack {
        TagListView(filterTagGroup: tagGroup)
    }
    .modelContainer(container)
}
