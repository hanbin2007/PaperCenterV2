//
//  GlobalSearchView.swift
//  PaperCenterV2
//
//  Global search screen with structured filters.
//

import SwiftData
import SwiftUI
import PDFKit
import UIKit

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
        HStack(alignment: .top, spacing: 12) {
            if result.kind == .noteHit, let noteID = result.noteID {
                NotePreviewThumbnail(noteID: noteID)
                    .frame(width: 88, height: 112)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Label(result.kind.title, systemImage: result.kind.icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let docPageNumber = result.docPageNumber {
                        Text("P\(docPageNumber)")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.14), in: Capsule())
                            .foregroundStyle(.secondary)
                    }

                }

                Text(result.docTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(result.title)
                    .font(.headline)
                    .lineLimit(2)

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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}

private struct NotePreviewThumbnail: View {
    @Environment(\.modelContext) private var modelContext

    let noteID: UUID

    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var loadAttempted = false

    private var cacheKey: String {
        noteID.uuidString
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.secondarySystemBackground))
                    .overlay {
                        if isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "text.bubble")
                                .foregroundStyle(.secondary)
                        }
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
        )
        .task(id: noteID) {
            await loadIfNeeded()
        }
    }

    @MainActor
    private func loadIfNeeded() async {
        guard !loadAttempted else { return }
        loadAttempted = true

        if let cached = NotePreviewCache.shared.object(forKey: cacheKey as NSString) {
            image = cached
            return
        }

        isLoading = true
        let context = resolveRenderContext(noteID: noteID)

        guard let context else {
            isLoading = false
            return
        }
        let rendered = await Task.detached(priority: .utility) {
            NotePreviewRenderer.renderPreviewImage(context: context)
        }.value
        isLoading = false

        guard let rendered else { return }
        NotePreviewCache.shared.setObject(rendered, forKey: cacheKey as NSString)
        image = rendered
    }

    @MainActor
    private func resolveRenderContext(noteID: UUID) -> NotePreviewRenderContext? {
        let noteDescriptor = FetchDescriptor<NoteBlock>(
            predicate: #Predicate { note in
                note.id == noteID && note.isDeleted == false
            }
        )

        guard let note = try? modelContext.fetch(noteDescriptor).first else {
            return nil
        }

        let noteBundleID = note.pdfBundleId
        let bundleDescriptor = FetchDescriptor<PDFBundle>(
            predicate: #Predicate { bundle in
                bundle.id == noteBundleID
            }
        )
        guard let bundle = try? modelContext.fetch(bundleDescriptor).first else {
            return nil
        }

        guard let fileURL = bundle.fileURL(for: .display)
            ?? bundle.fileURL(for: .original)
            ?? bundle.fileURL(for: .ocr) else {
            return nil
        }

        let normalizedRect = CGRect(
            x: note.rectX,
            y: note.rectY,
            width: note.rectWidth,
            height: note.rectHeight
        )

        return NotePreviewRenderContext(
            fileURL: fileURL,
            pageIndex: max(note.pageIndexInBundle, 0),
            normalizedRect: normalizedRect
        )
    }
}

private enum NotePreviewCache {
    static let shared = NSCache<NSString, UIImage>()
}

private struct NotePreviewRenderContext {
    let fileURL: URL
    let pageIndex: Int
    let normalizedRect: CGRect
}

private enum NotePreviewRenderer {
    nonisolated static func renderPreviewImage(context: NotePreviewRenderContext) -> UIImage? {
        guard let document = PDFDocument(url: context.fileURL),
              let page = document.page(at: context.pageIndex) else {
            return nil
        }

        let pageBounds = page.bounds(for: .mediaBox)
        guard pageBounds.width > 0, pageBounds.height > 0 else {
            return nil
        }

        let targetHeight: CGFloat = 360
        let targetWidth = max(260, targetHeight * pageBounds.width / pageBounds.height)
        let pageImage = page.thumbnail(of: CGSize(width: targetWidth, height: targetHeight), for: .mediaBox)
        let imageBounds = CGRect(origin: .zero, size: pageImage.size)

        let x = context.normalizedRect.origin.x * pageImage.size.width
        let width = context.normalizedRect.size.width * pageImage.size.width
        let height = context.normalizedRect.size.height * pageImage.size.height
        let bottomY = context.normalizedRect.origin.y * pageImage.size.height
        let y = pageImage.size.height - bottomY - height

        let rawRect = CGRect(x: x, y: y, width: width, height: height)
        let noteRect = rawRect.standardized.intersection(imageBounds)
        guard noteRect.width > 1, noteRect.height > 1 else {
            return pageImage
        }

        let expandX = max(noteRect.width * 0.6, 18)
        let expandY = max(noteRect.height * 0.8, 18)
        let cropRect = noteRect
            .insetBy(dx: -expandX, dy: -expandY)
            .intersection(imageBounds)
        guard cropRect.width > 1, cropRect.height > 1 else {
            return pageImage
        }

        let renderer = UIGraphicsImageRenderer(size: cropRect.size)
        return renderer.image { context in
            pageImage.draw(at: CGPoint(x: -cropRect.minX, y: -cropRect.minY))

            let highlight = CGRect(
                x: noteRect.minX - cropRect.minX,
                y: noteRect.minY - cropRect.minY,
                width: noteRect.width,
                height: noteRect.height
            )
            context.cgContext.setStrokeColor(UIColor.systemYellow.cgColor)
            context.cgContext.setLineWidth(3)
            let rounded = UIBezierPath(roundedRect: highlight, cornerRadius: 6)
            context.cgContext.addPath(rounded.cgPath)
            context.cgContext.strokePath()
        }
    }
}
