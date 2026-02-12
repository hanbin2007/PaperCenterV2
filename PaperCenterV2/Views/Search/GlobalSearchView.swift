//
//  GlobalSearchView.swift
//  PaperCenterV2
//
//  Global search screen with structured filters.
//

import SwiftData
import SwiftUI

struct GlobalSearchView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Doc.createdAt, order: .reverse) private var docs: [Doc]

    @State private var viewModel: GlobalSearchViewModel?
    @State private var searchText: String = ""
    @State private var showingFilterSheet = false

    private var docByID: [UUID: Doc] {
        Dictionary(uniqueKeysWithValues: docs.map { ($0.id, $0) })
    }

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    content(viewModel)
                } else {
                    ProgressView("Preparing Search…")
                }
            }
            .navigationTitle("Search")
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search documents, OCR, notes, tags, variables"
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingFilterSheet = true
                    } label: {
                        Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityIdentifier("globalSearch.filterButton")
                    .disabled(viewModel == nil)
                }
            }
            .sheet(isPresented: $showingFilterSheet) {
                if let viewModel {
                    GlobalSearchFilterSheet(options: viewModel.options) { updated in
                        viewModel.applyOptions(updated)
                    }
                } else {
                    ProgressView()
                        .padding()
                }
            }
            .onAppear {
                initializeIfNeeded()
            }
            .onChange(of: searchText) { _, newValue in
                viewModel?.onQueryChanged(newValue)
            }
        }
    }

    @ViewBuilder
    private func content(_ viewModel: GlobalSearchViewModel) -> some View {
        VStack(spacing: 0) {
            Text(viewModel.filterSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.thinMaterial)
                .accessibilityIdentifier("globalSearch.filterSummary")

            if viewModel.isLoading {
                ProgressView("Searching…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.results.isEmpty {
                ContentUnavailableView(
                    "No Results",
                    systemImage: "magnifyingglass",
                    description: Text(
                        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "Enter keywords or configure filters to search."
                            : "Try broader keywords or adjust filters."
                    )
                )
            } else {
                List(viewModel.results) { result in
                    if let doc = docByID[result.docID] {
                        NavigationLink {
                            DocViewerScreen(doc: doc, launchContext: result.launchContext)
                        } label: {
                            SearchResultRow(result: result)
                        }
                    } else {
                        SearchResultRow(result: result)
                            .opacity(0.5)
                    }
                }
                .listStyle(.plain)
                .accessibilityIdentifier("globalSearch.resultList")
            }
        }
    }

    private func initializeIfNeeded() {
        guard viewModel == nil else { return }
        let vm = GlobalSearchViewModel(modelContext: modelContext)
        viewModel = vm
        searchText = vm.query
        vm.performSearchNow()
    }
}

private struct SearchResultRow: View {
    let result: GlobalSearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label(result.kind.title, systemImage: result.kind.icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(result.docTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(result.title)
                .font(.headline)
                .lineLimit(1)

            if !result.subtitle.isEmpty {
                Text(result.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !result.snippet.isEmpty {
                Text(result.snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 4)
    }
}
