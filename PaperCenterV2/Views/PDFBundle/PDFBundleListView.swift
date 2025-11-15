//
//  PDFBundleListView.swift
//  PaperCenterV2
//
//  Created by Claude on 2025-11-09.
//

import SwiftUI
import SwiftData

/// Main list view for PDFBundles
struct PDFBundleListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PDFBundle.createdAt, order: .reverse) private var bundles: [PDFBundle]

    @State private var viewModel: PDFBundleListViewModel?
    @State private var showingImport = false
    @State private var selectedBundleForDoc: PDFBundle?

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
                                // TODO: Add PDFs to existing bundle
                            } label: {
                                Label("Add PDFs", systemImage: "plus.circle")
                            }

                            Divider()

                            Button(role: .destructive) {
                                deleteBundle(bundle)
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
            .onAppear {
                if viewModel == nil {
                    viewModel = PDFBundleListViewModel(modelContext: modelContext)
                }
            }
        }
    }

    private func deleteBundle(_ bundle: PDFBundle) {
        guard let viewModel = viewModel else { return }

        do {
            try viewModel.deleteBundle(bundle)
        } catch {
            // TODO: Show error alert
            print("Error deleting bundle: \(error)")
        }
    }
}
