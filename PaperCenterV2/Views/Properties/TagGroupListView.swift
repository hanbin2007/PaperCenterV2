//
//  TagGroupListView.swift
//  PaperCenterV2
//
//  View for listing and managing tag groups
//

import SwiftUI
import SwiftData

struct TagGroupListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \TagGroup.sortIndex) private var tagGroups: [TagGroup]

    @State private var showingCreateSheet = false
    @State private var selectedTagGroups: Set<UUID> = []
    @State private var isEditMode = false
    @State private var showingDeleteConfirmation = false
    @State private var tagGroupToEdit: TagGroup?
    @State private var searchText = ""

    private var viewModel: PropertyManagementViewModel {
        PropertyManagementViewModel(modelContext: modelContext)
    }

    private var filteredTagGroups: [TagGroup] {
        let base = searchText.isEmpty
            ? tagGroups
            : tagGroups.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        return base.sortedByManualOrder()
    }

    var body: some View {
        List(selection: $selectedTagGroups) {
            if filteredTagGroups.isEmpty {
                ContentUnavailableView {
                    Label("No Tag Groups", systemImage: "folder.badge.questionmark")
                } description: {
                    if searchText.isEmpty {
                        Text("Create a tag group to organize your tags")
                    } else {
                        Text("No tag groups match '\(searchText)'")
                    }
                }
            } else {
                ForEach(filteredTagGroups) { tagGroup in
                    if isEditMode {
                        TagGroupRow(
                            tagGroup: tagGroup,
                            onEdit: { tagGroupToEdit = tagGroup }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggleSelection(tagGroup)
                        }
                    } else {
                        NavigationLink(value: tagGroup) {
                            TagGroupRow(
                                tagGroup: tagGroup,
                                onEdit: { tagGroupToEdit = tagGroup }
                            )
                        }
                    }
                }
            }
        }
        .environment(\.editMode, isEditMode ? .constant(.active) : .constant(.inactive))
        .navigationTitle("Tag Groups")
        .searchable(text: $searchText, prompt: "Search tag groups")
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
                            selectedTagGroups.removeAll()
                        }
                    }
                } label: {
                    Text(isEditMode ? "Done" : "Select")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isEditMode && !selectedTagGroups.isEmpty {
                BatchActionsToolbar(
                    selectedCount: selectedTagGroups.count,
                    onDelete: {
                        showingDeleteConfirmation = true
                    }
                )
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            TagGroupEditView(viewModel: viewModel, tagGroup: nil)
        }
        .sheet(item: $tagGroupToEdit) { tagGroup in
            TagGroupEditView(viewModel: viewModel, tagGroup: tagGroup)
        }
        .alert("Delete Tag Groups", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                batchDelete()
            }
        } message: {
            Text("Are you sure you want to delete \(selectedTagGroups.count) tag group(s)? Tag groups with tags cannot be deleted.")
        }
    }

    private func toggleSelection(_ tagGroup: TagGroup) {
        if selectedTagGroups.contains(tagGroup.id) {
            selectedTagGroups.remove(tagGroup.id)
        } else {
            selectedTagGroups.insert(tagGroup.id)
        }
    }

    private func batchDelete() {
        let groupsToDelete = filteredTagGroups.filter { selectedTagGroups.contains($0.id) }
        viewModel.batchDeleteTagGroups(groupsToDelete)
        selectedTagGroups.removeAll()
    }
}

// MARK: - Supporting Views

private struct TagGroupRow: View {
    let tagGroup: TagGroup
    let onEdit: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(tagGroup.name)
                    .font(.headline)

                if let tags = tagGroup.tags, !tags.isEmpty {
                    Text("\(tags.count) tag\(tags.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No tags")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                onEdit()
            } label: {
                Image(systemName: "pencil.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

private struct BatchActionsToolbar: View {
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

// MARK: - Toast Views

private struct ErrorToast: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        VStack {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.subheadline)
                Spacer()
                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.bordered)
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .padding()

            Spacer()
        }
    }
}

private struct SuccessToast: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        VStack {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(message)
                    .font(.subheadline)
                Spacer()
                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.bordered)
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .padding()

            Spacer()
        }
    }
}

// MARK: - Preview

#Preview("Tag Group List") {
    NavigationStack {
        TagGroupListView()
    }
    .modelContainer(for: [TagGroup.self, Tag.self])
}
