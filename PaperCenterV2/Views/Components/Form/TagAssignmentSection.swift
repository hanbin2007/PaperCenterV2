//
//  TagAssignmentSection.swift
//  PaperCenterV2
//
//  Form component for displaying and editing tag assignments
//

import SwiftUI
import SwiftData

/// Section view for displaying tag assignments within a Form
/// Shows assigned tags and navigates to selection screen
struct TagAssignmentSection: View {
    @Environment(\.modelContext) private var modelContext

    /// Current assigned tags (binding for updates)
    @Binding var assignedTags: [Tag]?

    /// Entity type for scope checking
    let entityType: TaggableEntityType

    /// Presentation control for selection sheet
    @State private var showSelection = false

    var body: some View {
        NavigationLink {
            TagSelectionView(
                entityType: entityType,
                assignedTags: $assignedTags
            )
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tags")
                        .font(.body)

                    if let tags = assignedTags, !tags.isEmpty {
                        HStack(spacing: 6) {
                            Text("\(tags.count) selected")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()

                            // Show preview of first 3 tags
                            ForEach(tags.prefix(3)) { tag in
                                TagPreviewCapsule(tag: tag)
                            }

                            if tags.count > 3 {
                                Text("+\(tags.count - 3)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("No tags assigned")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: "tag")
                    .foregroundStyle(.blue)
            }
        }
    }
}

/// Small capsule preview of a tag for use in lists
private struct TagPreviewCapsule: View {
    let tag: Tag

    var body: some View {
        Text(tag.name)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(hex: tag.color).opacity(0.12))
            .foregroundColor(Color(hex: tag.color))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color(hex: tag.color).opacity(0.2), lineWidth: 0.5)
            )
    }
}

// MARK: - Entity Type

/// Protocol for entities that can have tags
protocol TaggableEntity {
    var tags: [Tag]? { get set }
}

// MARK: - Previews

#Preview("TagAssignmentSection - With Tags") {
    let container = try! ModelContainer(for: Tag.self, TagGroup.self)
    let group = TagGroup(name: "Subject")
    let tag1 = Tag(name: "Mathematics", color: "#3B82F6", scope: .all, tagGroup: group)
    let tag2 = Tag(name: "Physics", color: "#10B981", scope: .all, tagGroup: group)
    let tag3 = Tag(name: "Chemistry", color: "#8B5CF6", scope: .all, tagGroup: group)
    container.mainContext.insert(group)
    container.mainContext.insert(tag1)
    container.mainContext.insert(tag2)
    container.mainContext.insert(tag3)

    return Form {
        TagAssignmentSection(
            assignedTags: .constant([tag1, tag2, tag3]),
            entityType: .doc
        )
    }
    .modelContainer(container)
}

#Preview("TagAssignmentSection - Empty") {
    let container = try! ModelContainer(for: Tag.self, TagGroup.self)

    return Form {
        TagAssignmentSection(
            assignedTags: .constant(nil),
            entityType: .doc
        )
    }
    .modelContainer(container)
}
