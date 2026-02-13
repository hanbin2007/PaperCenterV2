//
//  OCRDebugView.swift
//  PaperCenterV2
//
//  Created by Claude on 2025-11-09.
//

import SwiftUI
import SwiftData

/// Debug view for inspecting OCR text extraction results
struct OCRDebugView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PDFBundle.createdAt, order: .reverse) private var bundles: [PDFBundle]

    @State private var selectedBundle: PDFBundle?
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            List {
                if bundles.isEmpty {
                    ContentUnavailableView(
                        "No PDF Bundles",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Import a PDF bundle with OCR text to see extraction results")
                    )
                } else {
                    ForEach(bundles) { bundle in
                        Button {
                            selectedBundle = bundle
                        } label: {
                            BundleRowView(bundle: bundle)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("OCR Debug")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gear")
                    }
                }
            }
            .sheet(item: $selectedBundle) { bundle in
                OCRTextDetailView(bundle: bundle)
            }
            .sheet(isPresented: $showingSettings) {
                OCRSettingsView()
            }
        }
    }
}

/// Row view for bundle list
private struct BundleRowView: View {
    let bundle: PDFBundle

    private var statusColor: Color {
        switch bundle.ocrExtractionStatus {
        case "completed":
            return .green
        case "inProgress":
            return .blue
        case "failed":
            return .red
        default:
            return .gray
        }
    }

    private var statusIcon: String {
        switch bundle.ocrExtractionStatus {
        case "completed":
            return "checkmark.circle.fill"
        case "inProgress":
            return "arrow.circlepath"
        case "failed":
            return "exclamationmark.triangle.fill"
        default:
            return "circle"
        }
    }

    private var statusText: String {
        switch bundle.ocrExtractionStatus {
        case "completed":
            return "Completed"
        case "inProgress":
            return "Extracting..."
        case "failed":
            return "Failed"
        default:
            return "Not Started"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(bundle.displayName)
                .font(.headline)

            HStack(spacing: 12) {
                // OCR status indicator
                HStack(spacing: 4) {
                    Image(systemName: bundle.ocrPDFPath != nil ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundColor(bundle.ocrPDFPath != nil ? .green : .gray)
                        .font(.caption)
                    Text(bundle.ocrPDFPath != nil ? "Has OCR PDF" : "No OCR PDF")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()
                    .frame(height: 12)

                // Text extraction status
                HStack(spacing: 4) {
                    Image(systemName: "text.alignleft")
                        .font(.caption)
                    Text("\(bundle.ocrTextByPage.count) pages")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // OCR Extraction Status
            if bundle.ocrPDFPath != nil {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: statusIcon)
                            .foregroundColor(statusColor)
                            .font(.caption)
                            .symbolEffect(.pulse, isActive: bundle.ocrExtractionStatus == "inProgress")

                        Text(statusText)
                            .font(.caption)
                            .foregroundColor(statusColor)

                        Spacer()

                        if bundle.ocrExtractionStatus == "inProgress" || bundle.ocrExtractionStatus == "completed" {
                            Text("\(Int(bundle.ocrExtractionProgress * 100))%")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Progress bar
                    if bundle.ocrExtractionStatus == "inProgress" {
                        ProgressView(value: bundle.ocrExtractionProgress)
                            .progressViewStyle(.linear)
                    } else if bundle.ocrExtractionStatus == "completed" {
                        ProgressView(value: 1.0)
                            .progressViewStyle(.linear)
                            .tint(.green)
                    }
                }
                .padding(.top, 4)
            }

            Text("Created: \(bundle.createdAt, format: .dateTime.month().day().hour().minute())")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Detail view showing extracted text for each page
struct OCRTextDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let bundle: PDFBundle

    @State private var selectedPage: Int?

    private var sortedPages: [(Int, String)] {
        bundle.ocrTextByPage.sorted { $0.key < $1.key }
    }

    private var statusColor: Color {
        switch bundle.ocrExtractionStatus {
        case "completed":
            return .green
        case "inProgress":
            return .blue
        case "failed":
            return .red
        default:
            return .gray
        }
    }

    private var statusIcon: String {
        switch bundle.ocrExtractionStatus {
        case "completed":
            return "checkmark.circle.fill"
        case "inProgress":
            return "arrow.circlepath"
        case "failed":
            return "exclamationmark.triangle.fill"
        default:
            return "circle"
        }
    }

    private var statusText: String {
        switch bundle.ocrExtractionStatus {
        case "completed":
            return "Completed"
        case "inProgress":
            return "Extracting..."
        case "failed":
            return "Failed"
        default:
            return "Not Started"
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if bundle.ocrTextByPage.isEmpty {
                    ContentUnavailableView(
                        "No Extracted Text",
                        systemImage: "text.magnifyingglass",
                        description: Text(bundle.ocrPDFPath != nil ?
                            "OCR extraction may still be in progress. Pull down to refresh." :
                            "This bundle has no OCR PDF. Import one to extract text.")
                    )
                } else {
                    List {
                        // Summary section
                        Section {
                            LabeledContent("Bundle Name", value: bundle.displayName)

                            // Extraction status
                            HStack {
                                Text("Status")
                                Spacer()
                                HStack(spacing: 6) {
                                    Image(systemName: statusIcon)
                                        .foregroundColor(statusColor)
                                        .font(.caption)
                                    Text(statusText)
                                        .foregroundColor(statusColor)
                                }
                                .font(.subheadline)
                            }

                            if bundle.ocrExtractionStatus == "inProgress" {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Progress")
                                        Spacer()
                                        Text("\(Int(bundle.ocrExtractionProgress * 100))%")
                                            .foregroundColor(.secondary)
                                    }
                                    ProgressView(value: bundle.ocrExtractionProgress)
                                }
                            }

                            LabeledContent("Pages with Text", value: "\(bundle.ocrTextByPage.count)")
                            LabeledContent("Total Characters", value: "\(totalCharacterCount)")
                            LabeledContent("Last Updated", value: bundle.updatedAt, format: .dateTime)
                        } header: {
                            Text("Summary")
                        }

                        // Page text section
                        Section {
                            ForEach(sortedPages, id: \.0) { pageNumber, text in
                                Button {
                                    selectedPage = pageNumber
                                } label: {
                                    PageTextRowView(pageNumber: pageNumber, text: text)
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            Text("Extracted Text by Page")
                        }
                    }
                }
            }
            .navigationTitle("OCR Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(item: Binding(
                get: { selectedPage.map { PageIdentifier(page: $0) } },
                set: { selectedPage = $0?.page }
            )) { pageId in
                PageTextFullView(
                    pageNumber: pageId.page,
                    text: bundle.ocrTextByPage[pageId.page] ?? "",
                    bundleName: bundle.displayName
                )
            }
        }
    }

    private var totalCharacterCount: Int {
        bundle.ocrTextByPage.values.reduce(0) { $0 + $1.count }
    }
}

/// Row view for each page's text preview
private struct PageTextRowView: View {
    let pageNumber: Int
    let text: String

    private var previewText: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 100 {
            return trimmed
        }
        return String(trimmed.prefix(100)) + "..."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Page \(pageNumber)")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Text("\(text.count) chars")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            }

            Text(previewText)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(3)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Full-page text view
struct PageTextFullView: View {
    @Environment(\.dismiss) private var dismiss
    let pageNumber: Int
    let text: String
    let bundleName: String

    @State private var searchText = ""

    private var displayText: AttributedString {
        if searchText.isEmpty {
            return AttributedString(text)
        }

        var attributed = AttributedString(text)
        if let range = attributed.range(of: searchText, options: .caseInsensitive) {
            attributed[range].backgroundColor = .yellow
        }
        return attributed
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Metadata
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Bundle", value: bundleName)
                        LabeledContent("Page", value: "\(pageNumber)")
                        LabeledContent("Characters", value: "\(text.count)")
                        LabeledContent("Words", value: "\(wordCount)")
                        LabeledContent("Lines", value: "\(lineCount)")
                    }
                    .font(.caption)
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)

                    Divider()

                    // Text content
                    Text(displayText)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                }
                .padding()
            }
            .navigationTitle("Page \(pageNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        copyToClipboard()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search in text")
        }
    }

    private var wordCount: Int {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }

    private var lineCount: Int {
        text.components(separatedBy: .newlines).count
    }

    private func copyToClipboard() {
        UIPasteboard.general.string = text
    }
}

// Helper struct for sheet presentation
private struct PageIdentifier: Identifiable {
    let page: Int
    var id: Int { page }
}

/// Settings view for OCR configuration
struct OCRSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var settings = OCRSettings.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $settings.isVisionOCREnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Vision Framework OCR")
                                .font(.body)

                            Text("Uses Apple's Vision framework to extract text from scanned images")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Picker("Language", selection: $settings.ocrLanguage) {
                        ForEach(OCRLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .disabled(!settings.isVisionOCREnabled)
                } header: {
                    Text("Text Extraction")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("When enabled, the app will use Vision OCR to extract text from image-based PDFs (scanned documents) in the selected language.")

                        Text("When disabled, only embedded text will be extracted (faster, but won't work for scanned documents).")
                    }
                    .font(.caption)
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Embedded Text")
                                .font(.subheadline)
                        }

                        Text("Always extracted first for best performance")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 28)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: settings.isVisionOCREnabled ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundColor(settings.isVisionOCREnabled ? .green : .gray)
                            Text("Vision OCR")
                                .font(.subheadline)
                        }

                        Text(settings.isVisionOCREnabled ?
                             "Will process pages without embedded text" :
                             "Disabled - scanned pages will have no text")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 28)
                    }
                } header: {
                    Text("Extraction Methods")
                }

                Section {
                    Button("Reset to Defaults") {
                        settings.resetToDefaults()
                    }
                }
            }
            .navigationTitle("OCR Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Bundle List") {
    OCRDebugView()
        .modelContainer(for: [PDFBundle.self], inMemory: true)
}

#Preview("Settings") {
    OCRSettingsView()
}

#Preview("Empty State") {
    OCRDebugView()
        .modelContainer(for: [PDFBundle.self], inMemory: true)
}
