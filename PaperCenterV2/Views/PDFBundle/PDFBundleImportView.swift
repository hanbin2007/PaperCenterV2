//
//  PDFBundleImportView.swift
//  PaperCenterV2
//
//  Created by Claude on 2025-11-09.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// View for importing PDF bundles
struct PDFBundleImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel: PDFImportViewModel

    @State private var activePickerType: PDFType?
    @State private var isFileImporterPresented = false

    @Bindable var ocrSettings = OCRSettings.shared

    init() {
        // Will be properly initialized in onAppear with modelContext
        _viewModel = State(initialValue: PDFImportViewModel(modelContext: ModelContext(ModelContainer.preview)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Bundle Name", text: $viewModel.bundleName)
                } header: {
                    Text("Bundle Information")
                } footer: {
                    Text("Enter a descriptive name for this PDF bundle")
                }

                Section {
                    // Display PDF (required)
                    PDFPickerRow(
                        title: "Display PDF",
                        subtitle: "Required",
                        url: $viewModel.displayPDFURL
                    ) {
                        presentPicker(.display)
                    }

                    // OCR PDF (optional)
                    PDFPickerRow(
                        title: "OCR PDF",
                        subtitle: "Optional - for text extraction",
                        url: $viewModel.ocrPDFURL
                    ) {
                        presentPicker(.ocr)
                    }

                    // Original PDF (optional)
                    PDFPickerRow(
                        title: "Original PDF",
                        subtitle: "Optional - original without annotations",
                        url: $viewModel.originalPDFURL
                    ) {
                        presentPicker(.original)
                    }
                } header: {
                    Text("Select PDF Files")
                } footer: {
                    Text("Display PDF is required. OCR and Original PDFs are optional.")
                }

                if !viewModel.pagePreviews.isEmpty {
                    Section {
                        NavigationLink {
                            PageSelectionView(viewModel: viewModel)
                        } label: {
                            PageSelectionSummary(viewModel: viewModel)
                        }
                    } header: {
                        Text("Page Selection")
                    } footer: {
                        Text("Tap to review thumbnails and choose which pages to import.")
                            .font(.caption)
                    }
                }

                // OCR Settings Section (only show if OCR PDF is selected)
                if viewModel.ocrPDFURL != nil {
                    Section {
                        Toggle(isOn: $ocrSettings.isVisionOCREnabled) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Vision Framework OCR")
                                    .font(.body)
                                Text("Extract text from scanned images")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Picker("Language", selection: $ocrSettings.ocrLanguage) {
                            ForEach(OCRLanguage.allCases) { language in
                                Text(language.displayName).tag(language)
                            }
                        }
                        .disabled(!ocrSettings.isVisionOCREnabled)
                    } header: {
                        Text("OCR Settings")
                    } footer: {
                        VStack(alignment: .leading, spacing: 8) {
                            if ocrSettings.isVisionOCREnabled {
                                Text("Vision OCR will extract text from image-based PDFs in the selected language.")
                            } else {
                                Text("Only embedded text will be extracted (faster, but won't work for scanned documents).")
                            }
                        }
                        .font(.caption)
                    }
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Import PDF Bundle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        Task {
                            await viewModel.importBundle()
                            dismiss()
                        }
                    }
                    .disabled(!viewModel.canImport)
                }
            }
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                guard let pickerType = activePickerType else { return }
                defer { activePickerType = nil }
                handleFileSelection(result, for: pickerType)
            }
            .onAppear {
                // Initialize viewModel with actual modelContext
                viewModel = PDFImportViewModel(modelContext: modelContext)
            }
        }
    }

    private func presentPicker(_ type: PDFType) {
        activePickerType = type
        isFileImporterPresented = true
    }

    private func handleFileSelection(_ result: Result<[URL], Error>, for type: PDFType) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            switch type {
            case .display:
                viewModel.displayPDFURL = url
            case .ocr:
                viewModel.ocrPDFURL = url
            case .original:
                viewModel.originalPDFURL = url
            }
        case .failure(let error):
            viewModel.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Page Selection Views

private struct PageSelectionView: View {
    @Bindable var viewModel: PDFImportViewModel

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 140, maximum: 220), spacing: 12)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                selectionToolbar

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(viewModel.pagePreviews) { page in
                        PageSelectionCard(
                            page: page,
                            isSelected: viewModel.isSelected(page),
                            onToggleSelection: { viewModel.toggleSelection(for: page) }
                        )
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Select Pages")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var selectionToolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Selected \(viewModel.selectedPageCount) of \(viewModel.totalPageCount)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Select All") {
                    viewModel.selectAllPages()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.selectedPageCount == viewModel.totalPageCount)

                Button("Clear All") {
                    viewModel.clearSelection()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.selectedPageCount == 0)
            }
        }
    }
}

private struct PageSelectionSummary: View {
    @Bindable var viewModel: PDFImportViewModel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Selected Pages")
                    .font(.headline)
                Text("\(viewModel.selectedPageCount) of \(viewModel.totalPageCount)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }
}

private struct PageSelectionCard: View {
    let page: PDFImportViewModel.ImportPage
    let isSelected: Bool
    let onToggleSelection: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Page \(page.pageNumber)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: onToggleSelection) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
            }

            NavigationLink {
                PagePreviewDetailView(page: page)
            } label: {
                pagePreview
                    .frame(height: 110)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            HStack(spacing: 6) {
                VariantChip(title: "Display", systemImage: "doc.viewfinder", isActive: true)
                VariantChip(title: "Original", systemImage: "doc.richtext", isActive: page.hasOriginal)
                VariantChip(title: "OCR", systemImage: "text.viewfinder", isActive: page.hasOCR)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { onToggleSelection() }
    }

    @ViewBuilder
    private var pagePreview: some View {
        if let thumbnail = page.thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.15))
                .overlay(
                    Text("\(page.pageNumber)")
                        .font(.title)
                        .foregroundStyle(.secondary)
                )
        }
    }
}

private struct VariantChip: View {
    let title: String
    let systemImage: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption2)
            Text(title)
                .font(.caption2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(isActive ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
        .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
        .clipShape(Capsule())
    }
}

private struct PagePreviewDetailView: View {
    let page: PDFImportViewModel.ImportPage

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                pagePreview
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 12) {
                    Text("Variants")
                        .font(.headline)
                    HStack(spacing: 8) {
                        VariantChip(title: "Display", systemImage: "doc.viewfinder", isActive: true)
                        VariantChip(title: "Original", systemImage: "doc.richtext", isActive: page.hasOriginal)
                        VariantChip(title: "OCR", systemImage: "text.viewfinder", isActive: page.hasOCR)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .navigationTitle("Page \(page.pageNumber)")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var pagePreview: some View {
        if let thumbnail = page.thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 360)
        } else {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.2))
                .frame(height: 320)
                .overlay(
                    Text("No Preview")
                        .foregroundStyle(.secondary)
                )
        }
    }
}

/// Row for picking a PDF file
private struct PDFPickerRow: View {
    let title: String
    let subtitle: String
    @Binding var url: URL?
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    action()
                } label: {
                    Text(url == nil ? "Select" : "Change")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }

            if let url = url {
                Text(url.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

// MARK: - Preview Helper

extension ModelContainer {
    static var preview: ModelContainer {
        let schema = Schema([
            PDFBundle.self,
            Doc.self,
            PageGroup.self,
            Page.self,
            PageVersion.self,
            NoteBlock.self,
            Tag.self,
            TagGroup.self,
            Variable.self,
            PDFBundleVariableAssignment.self,
            DocVariableAssignment.self,
            PageGroupVariableAssignment.self,
            PageVariableAssignment.self,
            NoteBlockVariableAssignment.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: configuration)
    }
}
