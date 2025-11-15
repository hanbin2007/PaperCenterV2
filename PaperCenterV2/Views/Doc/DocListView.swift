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

    var body: some View {
        NavigationStack {
            List {
                ForEach(docs) { doc in
                    let formattedTags = viewModel?.formatTags(doc.tags) ?? []
                    let formattedVars = viewModel?.formatVariables(doc.variableAssignments) ?? []

                    DocRowView(
                        doc: doc,
                        formattedTags: formattedTags,
                        formattedVariables: formattedVars
                    )
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
        }
    }

    private func deleteDocs(at offsets: IndexSet) {
        guard let viewModel = viewModel else { return }

        for index in offsets {
            viewModel.deleteDoc(docs[index])
        }
    }
}
