//
//  TagSelectionView.swift
//  PaperCenterV2
//
//  View for selecting tags from a searchable, grouped list
//

import SwiftUI
import SwiftData

/// View for selecting tags from a searchable, grouped list
struct TagSelectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Entity type for scope filtering
    let entityType: TaggableEntityType

    /// Currently assigned tags (binding for updates)
    @Binding var assignedTags: [Tag]?

    /// Search query
    @State private var searchQuery = ""

    /// All available tags from database
    @Query(sort: \Tag.name) private var allTags: [Tag]

    /// Computed: Only show tags applicable to this entity type
    private var applicableTags: [Tag] {
        allTags.filter { $0.canApply(to: entityType) }
    }

    /// Computed: Tags grouped by TagGroup with filtering
    private var groupedTags: [(groupName: String, tags: [Tag])] {
        let filtered = searchQuery.isEmpty
            ? applicableTags
            : applicableTags.filter { tag in
                tag.name.localizedCaseInsensitiveContains(searchQuery) ||
                (tag.tagGroup?.name.localizedCaseInsensitiveContains(searchQuery) ?? false)
            }

        let grouped = Dictionary(grouping: filtered) { tag in
            tag.tagGroup?.name ?? "Other"
        }

        return grouped.map { (groupName: $0.key, tags: $0.value) }
            .sorted { $0.groupName < $1.groupName }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Search bar
                SearchBar(text: $searchQuery, placeholder: "Search tags...")
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                // Tags grouped by TagGroup
                ForEach(groupedTags, id: \.groupName) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        // Group header
                        Text(group.groupName)
                            .font(.headline)
                            .padding(.horizontal)

                        // Tags grid
                        TagGrid(
                            tags: group.tags,
                            assignedTags: $assignedTags
                        )
                    }
                }

                // Empty state
                if groupedTags.isEmpty {
                    EmptyStateView(
                        title: "No Tags Found",
                        subtitle: searchQuery.isEmpty
                            ? "No tags available for this entity type"
                            : "No tags match your search",
                        icon: "tag"
                    )
                    .padding(.top, 40)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Select Tags")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }

    /// Check if a tag is currently selected
    private func isTagSelected(_ tag: Tag) -> Bool {
        assignedTags?.contains(where: { $0.id == tag.id }) ?? false
    }

    /// Toggle tag selection
    private func toggleTag(_ tag: Tag) {
        if assignedTags == nil {
            assignedTags = []
        }

        if isTagSelected(tag) {
            assignedTags?.removeAll(where: { $0.id == tag.id })
        } else {
            assignedTags?.append(tag)
        }
    }
}

/// Grid view displaying tags as selectable capsules
private struct TagGrid: View {
    let tags: [Tag]
    @Binding var assignedTags: [Tag]?

    /// Grid layout with adaptive columns
    private let columns = [GridItem(.adaptive(minimum: 110))]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(tags) { tag in
                TagCapsuleButton(
                    tag: tag,
                    isSelected: isTagSelected(tag)
                ) {
                    toggleTag(tag)
                }
            }
        }
        .padding(.horizontal)
    }

    private func isTagSelected(_ tag: Tag) -> Bool {
        assignedTags?.contains(where: { $0.id == tag.id }) ?? false
    }

    private func toggleTag(_ tag: Tag) {
        if assignedTags == nil {
            assignedTags = []
        }

        if isTagSelected(tag) {
            assignedTags?.removeAll(where: { $0.id == tag.id })
        } else {
            assignedTags?.append(tag)
        }
    }
}

/// Selectable tag capsule with visual feedback
private struct TagCapsuleButton: View {
    let tag: Tag
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(tag.name)
                    .font(.subheadline)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                Capsule()
                    .fill(Color(hex: tag.color).opacity(isSelected ? 0.25 : 0.12))
            )
            .foregroundColor(Color(hex: tag.color))
            .overlay(
                Capsule()
                    .stroke(
                        Color(hex: tag.color).opacity(isSelected ? 0.6 : 0.3),
                        lineWidth: isSelected ? 2 : 0.5
                    )
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color(hex: tag.color))
                        .background(
                            Circle()
                                .fill(.background)
                                .scaleEffect(0.8)
                        )
                        .offset(x: 4, y: -4)
                }
            }
            .scaleEffect(isSelected ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

/// Search bar component
struct SearchBar: View {
    @Binding var text: String
    let placeholder: String

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .focused($isFocused)
                .submitLabel(.search)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color(.systemFill))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.vertical, 8)
        .onAppear {
            // Auto focus search bar
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isFocused = true
            }
        }
    }
}

/// Empty state view for when no items are available
struct EmptyStateView: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}

// MARK: - Preview

#Preview("TagSelectionView") {
    let container = try! ModelContainer(for: Tag.self, TagGroup.self)
    let subjectGroup = TagGroup(name: "Subject")
    let difficultyGroup = TagGroup(name: "Difficulty")
    let mathTag = Tag(name: "Mathematics", color: "#3B82F6", scope: .all, tagGroup: subjectGroup)
    let physicsTag = Tag(name: "Physics", color: "#10B981", scope: .all, tagGroup: subjectGroup)
    let hardTag = Tag(name: "Hard", color: "#EF4444", scope: .doc, tagGroup: difficultyGroup)
    container.mainContext.insert(subjectGroup)
    container.mainContext.insert(difficultyGroup)
    container.mainContext.insert(mathTag)
    container.mainContext.insert(physicsTag)
    container.mainContext.insert(hardTag)

    return NavigationStack {
        TagSelectionView(
            entityType: .doc,
            assignedTags: .constant([mathTag])
        )
    }
    .modelContainer(container)
}

#Preview("TagSelectionView - Empty") {
    let container = try! ModelContainer(for: Tag.self, TagGroup.self)

    return NavigationStack {
        TagSelectionView(
            entityType: .doc,
            assignedTags: .constant(nil)
        )
    }
    .modelContainer(container)
}
