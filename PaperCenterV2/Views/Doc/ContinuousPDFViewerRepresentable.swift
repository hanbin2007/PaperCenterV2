//
//  ContinuousPDFViewerRepresentable.swift
//  PaperCenterV2
//
//  Single PDFView host that renders composed pages continuously.
//

import Foundation
import PDFKit
import SwiftUI
import UIKit

struct ComposedPDFPageEntry: Identifiable {
    let id: UUID
    let logicalPageID: UUID
    let pageID: UUID
    let pageVersionID: UUID
    let pageNumberInDoc: Int
    let fileURL: URL
    let sourcePageNumber: Int
}

struct ContinuousPDFViewerRepresentable: UIViewRepresentable {
    let entries: [ComposedPDFPageEntry]
    let jumpToComposedPageIndex: Int?
    let jumpRequestID: Int

    let noteAnchors: [NoteAnchorOverlayItem]
    let selectedNoteID: UUID?
    let focusAnchor: NoteAnchorOverlayItem?
    let isNoteCreateMode: Bool
    let showsInlineNoteBubbles: Bool
    let isEditingEnabled: Bool

    let onFocusedComposedPageChanged: (_ composedPageIndex: Int) -> Void
    let onCreateNoteRect: (_ composedPageIndex: Int, _ normalizedRect: CGRect) -> Void
    let onSelectNote: (_ noteID: UUID?) -> Void
    let onUpdateNoteRect: (_ noteID: UUID, _ normalizedRect: CGRect) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.clipsToBounds = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        pdfView.backgroundColor = .secondarySystemBackground
        pdfView.minScaleFactor = 0.6
        pdfView.maxScaleFactor = 6.0
        pdfView.usePageViewController(false, withViewOptions: nil)

        context.coordinator.install(on: pdfView)
        context.coordinator.apply(entries: entries, to: pdfView)
        context.coordinator.updateOverlay(
            anchors: noteAnchors,
            selectedNoteID: selectedNoteID,
            isCreateMode: isNoteCreateMode,
            showsInlineNoteBubbles: showsInlineNoteBubbles,
            isEditingEnabled: isEditingEnabled
        )

        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.apply(entries: entries, to: pdfView)
        context.coordinator.updateOverlay(
            anchors: noteAnchors,
            selectedNoteID: selectedNoteID,
            isCreateMode: isNoteCreateMode,
            showsInlineNoteBubbles: showsInlineNoteBubbles,
            isEditingEnabled: isEditingEnabled
        )

        if let jumpToComposedPageIndex,
           context.coordinator.lastHandledJumpRequestID != jumpRequestID {
            context.coordinator.lastHandledJumpRequestID = jumpRequestID
            context.coordinator.jump(to: jumpToComposedPageIndex)
        }

        context.coordinator.focus(on: focusAnchor)
    }

    final class Coordinator: NSObject {
        var parent: ContinuousPDFViewerRepresentable

        private weak var pdfView: PDFView?
        private let overlay = NoteAnchorOverlayView()

        private var signature: String?
        private var pageEntryByComposedIndex: [Int: ComposedPDFPageEntry] = [:]
        private var pageByComposedIndex: [Int: PDFPage] = [:]

        private var pageChangedObserver: NSObjectProtocol?
        private var contentOffsetObserver: NSKeyValueObservation?
        private var zoomScaleObserver: NSKeyValueObservation?
        private var lastFocusedNoteID: UUID?
        fileprivate var lastHandledJumpRequestID: Int?

        init(_ parent: ContinuousPDFViewerRepresentable) {
            self.parent = parent
            super.init()
        }

        deinit {
            if let pageChangedObserver {
                NotificationCenter.default.removeObserver(pageChangedObserver)
            }
            contentOffsetObserver?.invalidate()
            zoomScaleObserver?.invalidate()
        }

        func install(on pdfView: PDFView) {
            self.pdfView = pdfView

            overlay.pdfView = pdfView
            overlay.translatesAutoresizingMaskIntoConstraints = false
            pdfView.addSubview(overlay)
            NSLayoutConstraint.activate([
                overlay.leadingAnchor.constraint(equalTo: pdfView.leadingAnchor),
                overlay.trailingAnchor.constraint(equalTo: pdfView.trailingAnchor),
                overlay.topAnchor.constraint(equalTo: pdfView.topAnchor),
                overlay.bottomAnchor.constraint(equalTo: pdfView.bottomAnchor),
            ])

            overlay.onCreateRect = { [weak self] composedIndex, normalizedRect in
                self?.parent.onCreateNoteRect(composedIndex, normalizedRect)
            }
            overlay.onSelectNote = { [weak self] noteID in
                self?.parent.onSelectNote(noteID)
            }
            overlay.onUpdateRect = { [weak self] noteID, normalizedRect in
                self?.parent.onUpdateNoteRect(noteID, normalizedRect)
            }

            pageChangedObserver = NotificationCenter.default.addObserver(
                forName: Notification.Name.PDFViewPageChanged,
                object: pdfView,
                queue: .main
            ) { [weak self] _ in
                self?.handlePageChanged()
            }

            if let scrollView = pdfView.subviews.compactMap({ $0 as? UIScrollView }).first {
                scrollView.isPagingEnabled = false
                contentOffsetObserver = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                    self?.overlay.refresh()
                }
                zoomScaleObserver = scrollView.observe(\.zoomScale, options: [.new]) { [weak self] _, _ in
                    self?.overlay.refresh()
                }
            }
        }

        func updateOverlay(
            anchors: [NoteAnchorOverlayItem],
            selectedNoteID: UUID?,
            isCreateMode: Bool,
            showsInlineNoteBubbles: Bool,
            isEditingEnabled: Bool
        ) {
            overlay.anchors = anchors
            overlay.selectedNoteID = selectedNoteID
            overlay.isCreateMode = isCreateMode
            overlay.showsContentBubbles = showsInlineNoteBubbles
            overlay.isEditingEnabled = isEditingEnabled
            overlay.pageByComposedIndex = pageByComposedIndex
        }

        func apply(entries: [ComposedPDFPageEntry], to pdfView: PDFView) {
            let newSignature = makeSignature(entries)
            guard newSignature != signature else {
                return
            }

            signature = newSignature
            pageEntryByComposedIndex.removeAll()
            pageByComposedIndex.removeAll()

            let document = PDFDocument()
            var sourceDocumentCache: [URL: PDFDocument] = [:]
            var composedIndex = 0

            for entry in entries {
                let sourceDocument: PDFDocument
                if let cached = sourceDocumentCache[entry.fileURL] {
                    sourceDocument = cached
                } else {
                    guard let loaded = PDFDocument(url: entry.fileURL) else { continue }
                    sourceDocumentCache[entry.fileURL] = loaded
                    sourceDocument = loaded
                }

                let sourceIndex = max(entry.sourcePageNumber - 1, 0)
                guard let sourcePage = sourceDocument.page(at: sourceIndex),
                      let copiedPage = sourcePage.copy() as? PDFPage else {
                    continue
                }

                document.insert(copiedPage, at: composedIndex)
                pageEntryByComposedIndex[composedIndex] = entry
                pageByComposedIndex[composedIndex] = copiedPage
                composedIndex += 1
            }

            pdfView.document = document
            pdfView.displayMode = .singlePageContinuous
            pdfView.displayDirection = .vertical
            pdfView.displaysPageBreaks = true
            pdfView.minScaleFactor = 0.6
            pdfView.maxScaleFactor = 6.0
            pdfView.autoScales = true
            pdfView.usePageViewController(false, withViewOptions: nil)

            overlay.pageByComposedIndex = pageByComposedIndex
            overlay.refresh()

            if composedIndex > 0 {
                notifyFocusedComposedPageChanged(0)
            }
        }

        func jump(to composedPageIndex: Int) {
            guard let pdfView,
                  let document = pdfView.document,
                  composedPageIndex >= 0,
                  composedPageIndex < document.pageCount,
                  let page = document.page(at: composedPageIndex) else {
                return
            }
            pdfView.go(to: page)
            notifyFocusedComposedPageChanged(composedPageIndex)
            overlay.refresh()
        }

        func focus(on anchor: NoteAnchorOverlayItem?) {
            guard let pdfView else { return }

            guard let anchor else {
                lastFocusedNoteID = nil
                return
            }

            if lastFocusedNoteID == anchor.id {
                return
            }
            lastFocusedNoteID = anchor.id

            guard let document = pdfView.document,
                  anchor.composedPageIndex >= 0,
                  anchor.composedPageIndex < document.pageCount,
                  let page = document.page(at: anchor.composedPageIndex) else {
                return
            }

            let pageBounds = page.bounds(for: .mediaBox)
            let pageRect = CGRect(
                x: pageBounds.minX + anchor.normalizedRect.origin.x * pageBounds.width,
                y: pageBounds.minY + anchor.normalizedRect.origin.y * pageBounds.height,
                width: anchor.normalizedRect.width * pageBounds.width,
                height: anchor.normalizedRect.height * pageBounds.height
            )

            pdfView.go(to: pageRect.insetBy(dx: -24, dy: -24), on: page)
            notifyFocusedComposedPageChanged(anchor.composedPageIndex)
            overlay.refresh()
        }

        private func handlePageChanged() {
            guard let pdfView,
                  let document = pdfView.document,
                  let currentPage = pdfView.currentPage else {
                return
            }
            let index = document.index(for: currentPage)
            guard index >= 0 else { return }
            notifyFocusedComposedPageChanged(index)
            overlay.refresh()
        }

        private func notifyFocusedComposedPageChanged(_ index: Int) {
            DispatchQueue.main.async { [weak self] in
                self?.parent.onFocusedComposedPageChanged(index)
            }
        }

        private func makeSignature(_ entries: [ComposedPDFPageEntry]) -> String {
            entries
                .map { entry in
                    "\(entry.logicalPageID.uuidString)|\(entry.pageVersionID.uuidString)|\(entry.fileURL.absoluteString)|\(entry.sourcePageNumber)"
                }
                .joined(separator: "#")
        }
    }
}
