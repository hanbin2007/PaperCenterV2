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
    @State private var thumbnailImage: Image?
    @State private var isLoadingThumbnail = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnailView
            VStack(alignment: .leading, spacing: 4) {
                Text(doc.title)
                    .font(.headline)
                    .lineLimit(1)

                tagSection
                variableSection

                Spacer(minLength: 0)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Created: \(doc.createdAt, format: .dateTime.month().day().year())")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text("Modified: \(doc.updatedAt, format: .dateTime.month().day().year())")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("\(doc.totalPageCount) pages")
                        .font(.caption2)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(Capsule())
                }
                .frame(height: 30)
            }
            .frame(height: thumbnailSize.height, alignment: .top)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .task(id: doc.id) {
            await loadThumbnailIfNeeded()
        }
    }

    private var thumbnailView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.systemGray6))
                .frame(width: thumbnailSize.width, height: thumbnailSize.height)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                )

            if let thumbnailImage {
                thumbnailImage
                    .resizable()
                    .scaledToFill()
                    .frame(width: thumbnailSize.width, height: thumbnailSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Image(systemName: isLoadingThumbnail ? "hourglass" : "doc.richtext")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func loadThumbnailIfNeeded() async {
        guard !isLoadingThumbnail, thumbnailImage == nil else { return }
        guard let firstPage = doc.allPages.first else { return }
        isLoadingThumbnail = true
        defer { isLoadingThumbnail = false }

        do {
            let descriptor = try await UniversalThumbnailService.shared.thumbnail(
                for: firstPage,
                size: thumbnailSize
            )
            await MainActor.run {
                thumbnailImage = Image(uiImage: descriptor.image)
            }
        } catch {
            print("Thumbnail error for doc \(doc.id): \(error)")
        }
    }

    @ViewBuilder
    private var tagSection: some View {
        if !formattedTags.isEmpty {
            TagDisplayView(tags: doc.tags ?? [])
                .frame(height: 25, alignment: .leading)
        } else {
            Color.clear.frame(height: 0)
        }
    }

    @ViewBuilder
    private var variableSection: some View {
        if !formattedVariables.isEmpty {
            VariableDisplayView(variables: formattedVariables)
                .frame(height: 25, alignment: .leading)
        } else {
            Color.clear.frame(height: 0)
        }
    }
}

private let thumbnailSize = CGSize(width: 84, height: 112)
