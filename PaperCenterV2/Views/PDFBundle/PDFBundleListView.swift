//
//  PDFBundleListView.swift
//  PaperCenterV2
//

import SwiftUI
import SwiftData

struct PDFBundleListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PDFBundle.createdAt, order: .reverse) private var bundles: [PDFBundle]

    @State private var viewModel: PDFBundleListViewModel?
    @State private var showingImport = false
    @State private var selectedBundleForDoc: PDFBundle?
    @State private var bundleToCompletePDFs: PDFBundle?

    var body: some View {
        NavigationStack {
            List {
                ForEach(bundles) { bundle in
                    let info = viewModel?.formatBundleInfo(bundle) ?? .placeholder

                    PDFBundleRowView(bundle: bundle, info: info)
                        .contextMenu {
                            Button {
                                selectedBundleForDoc = bundle
                            } label: {
                                Label("Create Doc", systemImage: "doc.badge.plus")
                            }
                            .disabled(!info.hasDisplay)

                            Button {
                                bundleToCompletePDFs = bundle
                            } label: {
                                if info.isComplete {
                                    Label("Review PDF Variants", systemImage: "doc.text.magnifyingglass")
                                } else {
                                    Label("Complete Missing PDFs", systemImage: "plus.circle")
                                }
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
            .sheet(item: $bundleToCompletePDFs) { bundle in
                if let viewModel {
                    BundlePDFCompletionView(
                        bundle: bundle,
                        viewModel: viewModel
                    )
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
