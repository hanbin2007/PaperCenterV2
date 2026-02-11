//
//  DocListView.swift
//  PaperCenterV2
//
//  Created by Claude on 2025-11-09.
//

import SwiftUI
import SwiftData

/// Main list view for Docs
struct DocListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Doc.createdAt, order: .reverse) private var docs: [Doc]

    @State private var viewModel: DocListViewModel?
    @State private var showingCreateDoc = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(docs) { doc in
                    let formattedTags = viewModel?.formatTags(doc.tags) ?? []
                    let formattedVars = viewModel?.formatVariables(doc.variableAssignments) ?? []

                    NavigationLink {
                        DocViewerScreen(doc: doc)
                    } label: {
                        DocRowView(
                            doc: doc,
                            formattedTags: formattedTags,
                            formattedVariables: formattedVars
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            duplicate(doc)
                        } label: {
                            Label("Duplicate", systemImage: "doc.on.doc")
                        }

                        Button(role: .destructive) {
                            deleteDoc(doc)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .onDelete(perform: deleteDocs)
            }
            .navigationTitle("Documents")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCreateDoc = true
                    } label: {
                        Label("Create Doc", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingCreateDoc) {
                DocCreationView()
            }
            .onAppear {
                if viewModel == nil {
                    viewModel = DocListViewModel(modelContext: modelContext)
                }
            }
            .alert(
                "Operation Failed",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func deleteDocs(at offsets: IndexSet) {
        guard let viewModel = viewModel else { return }

        for index in offsets {
            viewModel.deleteDoc(docs[index])
        }
    }

    private func deleteDoc(_ doc: Doc) {
        viewModel?.deleteDoc(doc)
    }

    private func duplicate(_ doc: Doc) {
        guard let viewModel = viewModel else { return }
        do {
            try viewModel.duplicateDoc(doc)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
