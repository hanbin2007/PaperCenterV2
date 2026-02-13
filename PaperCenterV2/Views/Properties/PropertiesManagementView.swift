import SwiftUI
import SwiftData

struct PropertiesManagementView: View {
    enum PropertySection: String, CaseIterable {
        case tags = "Tags"
        case variables = "Variables"

        var icon: String { self == .tags ? "tag" : "slider.horizontal.3" }
    }

    @State private var selectedSection: PropertySection = .tags
    @State private var showTagGroups = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $selectedSection) {
                    ForEach(PropertySection.allCases, id: \.self) { section in
                        Label(section.rawValue, systemImage: section.icon).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                if selectedSection == .tags {
                    VStack(spacing: 0) {
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
                } else {
                    VariableListView()
                }
            }
            .navigationTitle(selectedSection.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: TagGroup.self) { tagGroup in
                TagListView(filterTagGroup: tagGroup)
                    .navigationTitle(tagGroup.name)
            }
        }
    }
}
