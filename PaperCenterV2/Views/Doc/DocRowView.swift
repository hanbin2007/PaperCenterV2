//
//  DocRowView.swift
//  PaperCenterV2
//
//  Created by Claude on 2025-11-09.
//

import SwiftUI

/// Row view for displaying a Doc in a list
struct DocRowView: View {
    let doc: Doc
    let formattedTags: [(groupName: String, tags: [Tag])]
    let formattedVariables: [FormattedVariable]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title
            Text(doc.title)
                .font(.headline)

            // Tags
            if !formattedTags.isEmpty {
                TagDisplayView(tags: doc.tags ?? [])
            }

            // Variables
            if !formattedVariables.isEmpty {
                VariableDisplayView(variables: formattedVariables)
            }

            // Dates and page count
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Created: \(doc.createdAt, format: .dateTime.month().day().year())")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Modified: \(doc.updatedAt, format: .dateTime.month().day().year())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(doc.totalPageCount) pages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}
