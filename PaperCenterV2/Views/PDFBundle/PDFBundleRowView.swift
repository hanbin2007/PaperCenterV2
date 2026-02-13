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
                    PDFIndicator(variant: info.displayVariant)
                    PDFIndicator(variant: info.ocrVariant)
                    PDFIndicator(variant: info.originalVariant)
                }

                if !info.isComplete {
                    Label(missingSummary, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
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

    private var missingSummary: String {
        let fileMissingCount = info.missingVariants.filter { $0.status == .fileMissing }.count
        if fileMissingCount > 0 {
            if info.missingCount == 1 {
                return "1 variant file is missing"
            }
            return "\(info.missingCount) variants missing (\(fileMissingCount) file issues)"
        }

        if info.missingCount == 1 {
            return "1 variant not added yet"
        }
        return "\(info.missingCount) variants not added yet"
    }
}

/// Indicator showing if a PDF type is available
private struct PDFIndicator: View {
    let variant: BundleVariantInfo

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: iconName)
                .font(.caption2)
                .foregroundStyle(iconColor)

            Text(variant.type.shortTitle)
                .font(.caption2)
                .foregroundStyle(textColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(backgroundColor)
        .clipShape(Capsule())
    }

    private var iconName: String {
        switch variant.status {
        case .available:
            return "checkmark.circle.fill"
        case .missing:
            return "circle"
        case .fileMissing:
            return "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch variant.status {
        case .available:
            return .green
        case .missing:
            return .secondary
        case .fileMissing:
            return .orange
        }
    }

    private var textColor: Color {
        switch variant.status {
        case .available:
            return .primary
        case .missing, .fileMissing:
            return .secondary
        }
    }

    private var backgroundColor: Color {
        switch variant.status {
        case .available:
            return Color.green.opacity(0.1)
        case .missing:
            return Color.secondary.opacity(0.05)
        case .fileMissing:
            return Color.orange.opacity(0.12)
        }
    }
}

private let bundleThumbnailSize = CGSize(width: 84, height: 112)
