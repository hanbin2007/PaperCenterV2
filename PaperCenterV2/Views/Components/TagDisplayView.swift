//
//  TagDisplayView.swift
//  PaperCenterV2
//
//  Created by Claude on 2025-11-09.
//

import SwiftUI

/// Displays tags grouped by TagGroup with capsule styling
/// Format: **TagGroupName**: Tag1 Tag2 Tag3
struct TagDisplayView: View {
    let tags: [Tag]

    /// Group tags by their TagGroup
    private var groupedTags: [(groupName: String, tags: [Tag])] {
        MetadataFormattingService.groupTags(tags)
    }

    var body: some View {
        if !tags.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(groupedTags, id: \.groupName) { group in
                    HStack(alignment: .top, spacing: 4) {
                        // Group name in bold
                        Text("\(group.groupName):")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)

                        // Tags as capsules
                        FlowLayout(spacing: 4) {
                            ForEach(group.tags) { tag in
                                TagCapsule(tag: tag)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Individual tag capsule
private struct TagCapsule: View {
    let tag: Tag

    var body: some View {
        Text(tag.name)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(hex: tag.color).opacity(0.15))
            .foregroundColor(Color(hex: tag.color))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color(hex: tag.color).opacity(0.3), lineWidth: 0.5)
            )
    }
}

/// Simple flow layout for tags (wraps to new line if needed)
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if currentX + size.width > maxWidth && currentX > 0 {
                    // Move to next line
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: currentX, y: currentY))
                currentX += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }

            self.size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}
