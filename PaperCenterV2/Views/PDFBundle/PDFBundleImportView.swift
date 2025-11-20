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
                        PageSelectionGrid(viewModel: viewModel)
                    } header: {
                        Text("Page Selection")
                    } footer: {
                        Text("Choose which Display PDF pages to import. Highlighted chips show available variants per page.")
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
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.plain)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Import") {
                        Task {
                            await viewModel.importBundle()
                            dismiss()
                        }
                    }
                    .buttonStyle(.plain)
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

// MARK: - Page Selection Grid

private struct PageSelectionGrid: View {
    @Bindable var viewModel: PDFImportViewModel

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 140, maximum: 220), spacing: 12)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Selected \(viewModel.selectedPageCount) of \(viewModel.totalPageCount)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Select All") {
                    viewModel.selectAllPages()
                }
                .disabled(viewModel.selectedPageCount == viewModel.totalPageCount)

                Button("Clear All") {
                    viewModel.clearSelection()
                }
                .disabled(viewModel.selectedPageCount == 0)
            }

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(viewModel.pagePreviews) { page in
                    PageSelectionCard(
                        page: page,
                        isSelected: viewModel.isSelected(page),
                        action: { viewModel.toggleSelection(for: page) }
                    )
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct PageSelectionCard: View {
    let page: PDFImportViewModel.ImportPage
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    pagePreview
                        .frame(maxWidth: .infinity)
                        .aspectRatio(3/4, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                        )

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .padding(8)
                }

                Text("Page \(page.pageNumber)")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 6) {
                    VariantChip(title: "Display", systemImage: "doc.viewfinder", isActive: true)
                    VariantChip(title: "Original", systemImage: "doc.richtext", isActive: page.hasOriginal)
                    VariantChip(title: "OCR", systemImage: "text.viewfinder", isActive: page.hasOCR)
                }
            }
            .padding(10)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var pagePreview: some View {
        if let thumbnail = page.thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.15))
                Text("\(page.pageNumber)")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct VariantChip: View {
    let title: String
    let systemImage: String
    let isActive: Bool

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isActive ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            .clipShape(Capsule())
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
            Tag.self,
            TagGroup.self,
            Variable.self,
            PDFBundleVariableAssignment.self,
            DocVariableAssignment.self,
            PageGroupVariableAssignment.self,
            PageVariableAssignment.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: configuration)
    }
}
