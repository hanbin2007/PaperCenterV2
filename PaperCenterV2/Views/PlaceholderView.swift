//
//  PlaceholderView.swift
//  PaperCenterV2
//
//  Created by Claude on 2025-11-09.
//

import SwiftUI
import SwiftData

/// Placeholder view for the app
///
/// This is a temporary view showing that the core data models are set up.
/// Future UI implementation will replace this with actual document management interface.
struct PlaceholderView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue)

                Text("PaperCenterV2")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Core Data Models Implemented")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Divider()
                    .padding(.vertical)

                VStack(alignment: .leading, spacing: 12) {
                    FeatureRow(icon: "checkmark.circle.fill", text: "PDFBundle model", color: .green)
                    FeatureRow(icon: "checkmark.circle.fill", text: "Page & PageVersion models", color: .green)
                    FeatureRow(icon: "checkmark.circle.fill", text: "PageGroup model", color: .green)
                    FeatureRow(icon: "checkmark.circle.fill", text: "Doc model", color: .green)
                    FeatureRow(icon: "checkmark.circle.fill", text: "Tag & Variable system", color: .green)
                    FeatureRow(icon: "checkmark.circle.fill", text: "PDF import service", color: .green)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)

                Spacer()

                Text("UI implementation coming in Phase 2")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .navigationTitle("Document Organizer")
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title3)

            Text(text)
                .font(.body)

            Spacer()
        }
    }
}

#Preview {
    PlaceholderView()
}
