//
//  GlobalSearchView.swift
//  PaperCenterV2
//
//  Global search screen with structured filters.
//

import SwiftData
import SwiftUI
import UIKit

struct GlobalSearchView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Doc.createdAt, order: .reverse) private var docs: [Doc]
    @Query(sort: \PDFBundle.createdAt, order: .reverse) private var bundles: [PDFBundle]

    @State private var viewModel: GlobalSearchViewModel?
    @State private var searchText: String = ""
    @State private var showingFilterSheet = false

    private var docByID: [UUID: Doc] {
        Dictionary(uniqueKeysWithValues: docs.map { ($0.id, $0) })
    }

    private var bundleByID: [UUID: PDFBundle] {
        Dictionary(uniqueKeysWithValues: bundles.map { ($0.id, $0) })
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
                    let previewBundle = result.notePreview.flatMap { bundleByID[$0.bundleID] }
                    if let doc = docByID[result.docID] {
                        NavigationLink {
                            DocViewerScreen(doc: doc, launchContext: result.launchContext)
                        } label: {
                            SearchResultRow(
                                result: result,
                                previewBundle: previewBundle
                            )
                        }
                    } else {
                        SearchResultRow(
                            result: result,
                            previewBundle: previewBundle
                        )
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
    let previewBundle: PDFBundle?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let preview = result.notePreview,
               let previewBundle {
                NoteSearchPreviewCard(
                    bundle: previewBundle,
                    preview: preview
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Label(result.kind.title, systemImage: result.kind.icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let page = result.docPageNumber {
                        Text("P\(page)")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    if let pageGroupTitle = result.pageGroupTitle,
                       !pageGroupTitle.isEmpty {
                        Text(pageGroupTitle)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Capsule())
                            .lineLimit(1)
                    }

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
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct NoteSearchPreviewCard: View {
    let bundle: PDFBundle
    let preview: NotePreviewContext

    @State private var thumbnail: UIImage?
    @State private var isLoading = false

    private let cardSize = CGSize(width: 74, height: 98)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.systemGray6))

            if let thumbnail {
                GeometryReader { proxy in
                    let normalizedRect = clampedNormalizedRect(preview.normalizedRect)
                    let drawRect = fittedRect(
                        imageSize: thumbnail.size,
                        in: proxy.size
                    )
                    let highlightRect = CGRect(
                        x: drawRect.minX + normalizedRect.minX * drawRect.width,
                        y: drawRect.minY + (1 - normalizedRect.maxY) * drawRect.height,
                        width: normalizedRect.width * drawRect.width,
                        height: normalizedRect.height * drawRect.height
                    )

                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .frame(width: proxy.size.width, height: proxy.size.height)

                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.orange.opacity(0.18))
                        .frame(width: highlightRect.width, height: highlightRect.height)
                        .position(x: highlightRect.midX, y: highlightRect.midY)

                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.orange, lineWidth: 1.5)
                        .frame(width: highlightRect.width, height: highlightRect.height)
                        .position(x: highlightRect.midX, y: highlightRect.midY)
                }
            } else {
                Image(systemName: isLoading ? "hourglass" : "doc.richtext")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.24), lineWidth: 0.5)
        )
        .task(id: "\(bundle.id.uuidString)-\(preview.pageNumber)") {
            await loadThumbnailIfNeeded()
        }
    }

    private func loadThumbnailIfNeeded() async {
        guard !isLoading, thumbnail == nil else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let descriptor = try await UniversalThumbnailService.shared.thumbnail(
                for: bundle,
                page: preview.pageNumber,
                size: cardSize
            )
            await MainActor.run {
                thumbnail = descriptor.image
            }
        } catch {
            // Keep placeholder on failure.
        }
    }

    private func fittedRect(imageSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0,
              imageSize.height > 0,
              containerSize.width > 0,
              containerSize.height > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }

        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height

        if imageAspect > containerAspect {
            let drawHeight = containerSize.width / imageAspect
            return CGRect(
                x: 0,
                y: (containerSize.height - drawHeight) / 2,
                width: containerSize.width,
                height: drawHeight
            )
        }

        let drawWidth = containerSize.height * imageAspect
        return CGRect(
            x: (containerSize.width - drawWidth) / 2,
            y: 0,
            width: drawWidth,
            height: containerSize.height
        )
    }

    private func clampedNormalizedRect(_ rect: CGRect) -> CGRect {
        let x = max(0, min(1, rect.minX))
        let y = max(0, min(1, rect.minY))
        let width = max(0.01, min(1 - x, rect.width))
        let height = max(0.01, min(1 - y, rect.height))
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
