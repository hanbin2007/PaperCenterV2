//
//  UniversalThumbnailView.swift
//  PaperCenterV2
//
//  Created by zhb on 2025-11-09.
//

import SwiftUI

/// Modern thumbnail card that can optionally show selection controls, titles, and tags
struct UniversalThumbnailView: View {
    struct Configuration {
        var showsSelectionControl: Bool = true
        var showsTitle: Bool = true
        var showsSubtitle: Bool = true
        var showsTags: Bool = true
        var cornerRadius: CGFloat = 12
    }

    @Binding var isSelected: Bool

    let image: Image?
    let title: String?
    let subtitle: String?
    let tags: [Tag]
    let isLoading: Bool
    var configuration: Configuration = .init()
    var onSelectionToggle: (() -> Void)?

    init(
        isSelected: Binding<Bool>,
        image: Image?,
        title: String? = nil,
        subtitle: String? = nil,
        tags: [Tag] = [],
        isLoading: Bool = false,
        configuration: Configuration = .init(),
        onSelectionToggle: (() -> Void)? = nil
    ) {
        self._isSelected = isSelected
        self.image = image
        self.title = title
        self.subtitle = subtitle
        self.tags = tags
        self.isLoading = isLoading
        self.configuration = configuration
        self.onSelectionToggle = onSelectionToggle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                thumbnailContent

                if configuration.showsSelectionControl {
                    selectionControl
                }
            }

            if configuration.showsTitle, let title {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }

            if configuration.showsSubtitle, let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if configuration.showsTags, !tags.isEmpty {
                tagRow
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: configuration.cornerRadius, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: configuration.cornerRadius, style: .continuous)
                        .stroke(isSelected ? Color.accentColor.opacity(0.7) : Color.clear, lineWidth: 1)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: configuration.cornerRadius, style: .continuous)
                .stroke(Color.black.opacity(0.03), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.systemBackground))
                .aspectRatio(3 / 4, contentMode: .fit)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
                )

            if let image {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                placeholder
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(.systemGray6),
                            Color(.systemGray5)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if isLoading {
                ProgressView()
            } else {
                Image(systemName: "doc.richtext")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var selectionControl: some View {
        Button {
            isSelected.toggle()
            onSelectionToggle?()
        } label: {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .padding(6)
                .background(
                    Circle()
                        .fill(Color(.systemBackground).opacity(0.85))
                )
        }
        .buttonStyle(.plain)
        .padding(6)
    }

    private var tagRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags) { tag in
                    Text(tag.name)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(hex: tag.color).opacity(0.12))
                        .foregroundColor(Color(hex: tag.color))
                        .clipShape(Capsule())
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Universal Thumbnail - Detailed") {
    let sampleTag = Tag(name: "Math", color: "#2563EB")
    return UniversalThumbnailView(
        isSelected: .constant(true),
        image: Image(systemName: "doc.text.image"),
        title: "Page 1",
        subtitle: "Bundle A",
        tags: [sampleTag],
        isLoading: false
    )
    .padding()
    .previewLayout(.sizeThatFits)
}

#Preview("Universal Thumbnail - Minimal") {
    let config = UniversalThumbnailView.Configuration(
        showsSelectionControl: false,
        showsTitle: false,
        showsSubtitle: false,
        showsTags: false
    )

    return UniversalThumbnailView(
        isSelected: .constant(false),
        image: nil,
        title: nil,
        subtitle: nil,
        tags: [],
        isLoading: true,
        configuration: config
    )
    .padding()
    .previewLayout(.sizeThatFits)
}
