//
//  PDFBundleRowView.swift
//  PaperCenterV2
//
//  Created by Claude on 2025-11-09.
//

import SwiftUI

/// Row view for displaying a PDFBundle in a list
struct PDFBundleRowView: View {
    let bundle: PDFBundle
    let info: BundleDisplayInfo
    @State private var thumbnailImage: Image?
    @State private var isLoadingThumbnail = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnailView
            VStack(alignment: .leading, spacing: 8) {
                Text(bundle.displayName)
                    .font(.headline)

                HStack(spacing: 8) {
                    PDFIndicator(type: "Display", available: info.hasDisplay)
                    PDFIndicator(type: "OCR", available: info.hasOCR)
                    PDFIndicator(type: "Original", available: info.hasOriginal)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(info.pageCount) pages")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("Created: \(info.createdAt, format: .dateTime.month().day().year())")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    if info.referenceCount > 0 {
                        Text("\(info.referenceCount) refs")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .task(id: bundle.id) {
            await loadThumbnailIfNeeded()
        }
    }

    private var thumbnailView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.systemGray6))
                .frame(width: bundleThumbnailSize.width, height: bundleThumbnailSize.height)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                )

            if let thumbnailImage {
                thumbnailImage
                    .resizable()
                    .scaledToFill()
                    .frame(width: bundleThumbnailSize.width, height: bundleThumbnailSize.height)
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
        guard info.pageCount > 0 else { return }
        isLoadingThumbnail = true
        defer { isLoadingThumbnail = false }

        do {
            let descriptor = try await UniversalThumbnailService.shared.thumbnail(
                for: bundle,
                page: 1,
                size: bundleThumbnailSize
            )
            await MainActor.run {
                thumbnailImage = Image(uiImage: descriptor.image)
            }
        } catch {
            print("Thumbnail error for bundle \(bundle.id): \(error)")
        }
    }
}

/// Indicator showing if a PDF type is available
private struct PDFIndicator: View {
    let type: String
    let available: Bool

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: available ? "checkmark.circle.fill" : "circle")
                .font(.caption2)
                .foregroundColor(available ? .green : .secondary)

            Text(type)
                .font(.caption2)
                .foregroundStyle(available ? .primary : .secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(available ? Color.green.opacity(0.1) : Color.secondary.opacity(0.05))
        .clipShape(Capsule())
    }
}

private let bundleThumbnailSize = CGSize(width: 84, height: 112)
