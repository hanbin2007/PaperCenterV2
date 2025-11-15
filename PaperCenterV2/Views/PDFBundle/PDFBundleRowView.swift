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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Bundle name
            Text(bundle.displayName)
                .font(.headline)

            // PDF availability indicators
            HStack(spacing: 8) {
                PDFIndicator(type: "Display", available: info.hasDisplay)
                PDFIndicator(type: "OCR", available: info.hasOCR)
                PDFIndicator(type: "Original", available: info.hasOriginal)
            }

            // Bundle info
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
        .padding(.vertical, 4)
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
