//
//  TagDisplayView.swift
//  PaperCenterV2
//
//  Displays tag groups and their tags in a single horizontal row.
//

import SwiftUI

struct TagDisplayView: View {
    let tags: [Tag]

    private var groupedTags: [(groupName: String, tags: [Tag])] {
        MetadataFormattingService.groupTags(tags)
    }

    var body: some View {
        if !tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(groupedTags, id: \.groupName) { group in
                        HStack(spacing: 6) {
                            Text(group.groupName)
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)

                            ForEach(group.tags) { tag in
                                TagCapsule(tag: tag)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

private struct TagCapsule: View {
    let tag: Tag

    var body: some View {
        Text(tag.name)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(hex: tag.color).opacity(0.15))
            .foregroundColor(Color(hex: tag.color))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color(hex: tag.color).opacity(0.3), lineWidth: 0.5)
            )
    }
}
