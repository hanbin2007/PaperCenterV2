import SwiftUI
import UniformTypeIdentifiers

struct BundlePDFCompletionView: View {
    @Environment(\.dismiss) private var dismiss

    let bundle: PDFBundle
    let viewModel: PDFBundleListViewModel

    @State private var activeImportType: PDFType?
    @State private var isFileImporterPresented = false
    @State private var importingType: PDFType?
    @State private var successMessage: String?
    @State private var errorMessage: String?

    private var info: BundleDisplayInfo {
        viewModel.formatBundleInfo(bundle)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    overviewCard
                    variantsCard

                    if let successMessage {
                        FeedbackBanner(
                            title: "Updated",
                            message: successMessage,
                            tint: .green,
                            icon: "checkmark.circle.fill"
                        )
                    }

                    if let errorMessage {
                        FeedbackBanner(
                            title: "Import Failed",
                            message: errorMessage,
                            tint: .red,
                            icon: "xmark.circle.fill"
                        )
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Complete Bundle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .disabled(importingType != nil)
                }
            }
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: [UTType.pdf],
                allowsMultipleSelection: false
            ) { result in
                guard let type = activeImportType else { return }
                activeImportType = nil

                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task {
                        await importVariant(type: type, from: url)
                    }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(bundle.displayName)
                        .font(.headline)

                    Text(completionSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(info.availableCount)/\(info.variants.count)")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(info.isComplete ? .green : .primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background((info.isComplete ? Color.green : Color.secondary).opacity(0.12))
                    .clipShape(Capsule())
            }

            ProgressView(value: info.completionRatio)
                .tint(info.isComplete ? .green : .accentColor)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var variantsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PDF Variants")
                .font(.headline)

            ForEach(info.variants) { variant in
                BundleVariantCompletionRow(
                    variant: variant,
                    isImporting: importingType == variant.type,
                    isBusy: importingType != nil
                ) { type in
                    errorMessage = nil
                    successMessage = nil
                    activeImportType = type
                    isFileImporterPresented = true
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var completionSummary: String {
        if info.isComplete {
            return "All PDF variants are available."
        }

        let fileMissingCount = info.missingVariants.filter { $0.status == .fileMissing }.count
        if fileMissingCount > 0 {
            return "\(info.missingCount) variants need attention (\(fileMissingCount) files missing on disk)."
        }
        return "\(info.missingCount) variants still need files."
    }

    @MainActor
    private func importVariant(type: PDFType, from url: URL) async {
        guard importingType == nil else { return }

        importingType = type
        errorMessage = nil
        successMessage = nil
        defer { importingType = nil }

        do {
            try await viewModel.addPDF(from: url, type: type, to: bundle)
            successMessage = "\(type.title) imported successfully."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct BundleVariantCompletionRow: View {
    let variant: BundleVariantInfo
    let isImporting: Bool
    let isBusy: Bool
    let onSelectFile: (PDFType) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: variant.status.statusIcon)
                .font(.system(size: 18))
                .foregroundStyle(variant.status.statusTint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(variant.type.title)
                        .font(.subheadline.weight(.semibold))
                    Text(variant.type.requirementText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }

                Text(variant.type.summaryDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(variant.status.statusText)
                    .font(.caption)
                    .foregroundStyle(variant.status.statusTint)
            }

            Spacer()

            actionView
        }
        .padding(10)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var actionView: some View {
        if isImporting {
            ProgressView()
                .controlSize(.small)
        } else if variant.status.requiresSupplement {
            Button(variant.status.actionTitle) {
                onSelectFile(variant.type)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isBusy)
        } else {
            Label("Ready", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.green)
        }
    }
}

private struct FeedbackBanner: View {
    let title: String
    let message: String
    let tint: Color
    let icon: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(tint.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private extension BundleVariantStatus {
    var statusText: String {
        switch self {
        case .available:
            return "Available"
        case .missing:
            return "Not added yet"
        case .fileMissing:
            return "Path exists, but file is missing"
        }
    }

    var actionTitle: String {
        switch self {
        case .available:
            return "View"
        case .missing:
            return "Add PDF"
        case .fileMissing:
            return "Restore File"
        }
    }

    var statusIcon: String {
        switch self {
        case .available:
            return "checkmark.circle.fill"
        case .missing:
            return "plus.circle"
        case .fileMissing:
            return "exclamationmark.triangle.fill"
        }
    }

    var statusTint: Color {
        switch self {
        case .available:
            return .green
        case .missing:
            return .secondary
        case .fileMissing:
            return .orange
        }
    }
}
