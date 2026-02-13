//
//  PDFBundleListView.swift
//  PaperCenterV2
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct PDFBundleListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PDFBundle.createdAt, order: .reverse) private var bundles: [PDFBundle]

    @State private var viewModel: PDFBundleListViewModel?
    @State private var showingImport = false
    @State private var selectedBundleForDoc: PDFBundle?

    @State private var bundleToAddPDF: PDFBundle?
    @State private var activeAddPDFType: PDFType?
    @State private var isFileImporterPresented = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(bundles) { bundle in
                    let info = viewModel?.formatBundleInfo(bundle) ?? BundleDisplayInfo(
                        hasDisplay: false,
                        hasOCR: false,
                        hasOriginal: false,
                        pageCount: 0,
                        referenceCount: 0,
                        createdAt: Date()
                    )

                    PDFBundleRowView(bundle: bundle, info: info)
                        .contextMenu {
                            Button {
                                selectedBundleForDoc = bundle
                            } label: {
                                Label("Create Doc", systemImage: "doc.badge.plus")
                            }

                            Button {
                                bundleToAddPDF = bundle
                            } label: {
                                Label("Add PDFs", systemImage: "plus.circle")
                            }

                            Divider()

                            Button(role: .destructive) {
                                try? viewModel?.deleteBundle(bundle)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .disabled(!(viewModel?.canDelete(bundle) ?? false))
                        }
                }
            }
            .navigationTitle("PDF Bundles")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingImport = true
                    } label: {
                        Label("Import Bundle", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingImport) {
                PDFBundleImportView()
            }
            .sheet(item: $selectedBundleForDoc) { bundle in
                DocCreationView(bundle: bundle)
            }
            .confirmationDialog(
                "Add PDF Variant",
                isPresented: Binding(
                    get: { bundleToAddPDF != nil && !isFileImporterPresented },
                    set: { if !$0 { bundleToAddPDF = nil } }
                ),
                presenting: bundleToAddPDF
            ) { bundle in
                if bundle.displayPDFPath == nil {
                    Button("Display PDF") {
                        activeAddPDFType = .display
                        isFileImporterPresented = true
                    }
                }
                if bundle.ocrPDFPath == nil {
                    Button("OCR PDF") {
                        activeAddPDFType = .ocr
                        isFileImporterPresented = true
                    }
                }
                if bundle.originalPDFPath == nil {
                    Button("Original PDF") {
                        activeAddPDFType = .original
                        isFileImporterPresented = true
                    }
                }
            } message: { _ in
                Text("Select the type of PDF to add to this bundle")
            }
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                guard let type = activeAddPDFType, let bundle = bundleToAddPDF else { return }
                activeAddPDFType = nil
                bundleToAddPDF = nil

                if case .success(let urls) = result, let url = urls.first {
                    Task {
                        try? await viewModel?.addPDF(from: url, type: type, to: bundle)
                    }
                }
            }
            .onAppear {
                if viewModel == nil {
                    viewModel = PDFBundleListViewModel(modelContext: modelContext)
                }
            }
        }
    }
}
