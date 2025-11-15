//
//  PropertiesManagementView.swift
//  PaperCenterV2
//
//  Main view for managing properties (tags and variables)
//

import SwiftUI
import SwiftData

/// Main properties management view with segmented control
struct PropertiesManagementView: View {
    @Environment(\.modelContext) private var modelContext

    enum PropertySection: String, CaseIterable {
        case tags = "Tags"
        case variables = "Variables"

        var icon: String {
            switch self {
            case .tags:
                return "tag"
            case .variables:
                return "slider.horizontal.3"
            }
        }
    }

    @State private var selectedSection: PropertySection = .tags

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented control
                Picker("Section", selection: $selectedSection) {
                    ForEach(PropertySection.allCases, id: \.self) { section in
                        Label(section.rawValue, systemImage: section.icon)
                            .tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                // Content based on selection
                switch selectedSection {
                case .tags:
                    TagManagementView()
                case .variables:
                    VariableManagementView()
                }
            }
            .navigationTitle("Properties")
        }
    }
}

// MARK: - Tag Management Section

private struct TagManagementView: View {
    @State private var showTagGroups = true

    var body: some View {
        VStack(spacing: 0) {
            // Toggle between tag groups and all tags
            Picker("View", selection: $showTagGroups) {
                Label("Groups", systemImage: "folder").tag(true)
                Label("All Tags", systemImage: "tag").tag(false)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            if showTagGroups {
                TagGroupListView()
            } else {
                TagListView()
            }
        }
    }
}

// MARK: - Variable Management Section

private struct VariableManagementView: View {
    var body: some View {
        VariableListView()
    }
}

// MARK: - Preview

#Preview("Properties Management") {
    PropertiesManagementView()
        .modelContainer(for: [Tag.self, TagGroup.self, Variable.self])
}

#Preview("Properties with Sample Data") {
    let container = try! ModelContainer(
        for: Tag.self, TagGroup.self, Variable.self
    )

    // Create sample tag groups
    let subjectGroup = TagGroup(name: "Subject")
    let difficultyGroup = TagGroup(name: "Difficulty")
    container.mainContext.insert(subjectGroup)
    container.mainContext.insert(difficultyGroup)

    // Create sample tags
    let mathTag = Tag(name: "Mathematics", color: "#3B82F6", scope: .all, tagGroup: subjectGroup)
    let physicsTag = Tag(name: "Physics", color: "#10B981", scope: .all, tagGroup: subjectGroup)
    let hardTag = Tag(name: "Hard", color: "#EF4444", scope: .doc, tagGroup: difficultyGroup)
    container.mainContext.insert(mathTag)
    container.mainContext.insert(physicsTag)
    container.mainContext.insert(hardTag)

    // Create sample variables
    let yearVar = Variable(name: "Year", type: .int, scope: .all)
    let difficultyVar = Variable(
        name: "Difficulty Level",
        type: .list,
        scope: .doc,
        listOptions: ["Easy", "Medium", "Hard"]
    )
    let scoreVar = Variable(name: "Score", type: .int, scope: .page)
    container.mainContext.insert(yearVar)
    container.mainContext.insert(difficultyVar)
    container.mainContext.insert(scoreVar)

    return PropertiesManagementView()
        .modelContainer(container)
}
