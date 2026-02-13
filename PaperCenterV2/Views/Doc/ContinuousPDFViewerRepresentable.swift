//
//  ContinuousPDFViewerRepresentable.swift
//  PaperCenterV2
//
//  Single PDFView host that renders composed pages continuously.

import Foundation
import PDFKit
import SwiftUI
import UIKit

// 增加 Equatable 用于变化监测
struct ComposedPDFPageEntry: Identifiable, Equatable {
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
    let focusRequestID: Int
    
    let noteAnchors: [NoteAnchorOverlayItem]
    let pageTagsByComposedIndex: [Int: PageTagOverlayItem]
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
            pageTagsByComposedIndex: pageTagsByComposedIndex,
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
        
        // 我们已经在内部做了 Equatable 检查，杜绝无谓的排版冲刷
        context.coordinator.updateOverlay(
            anchors: noteAnchors,
            pageTagsByComposedIndex: pageTagsByComposedIndex,
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
        
        context.coordinator.focus(on: focusAnchor, requestID: focusRequestID)
    }

    final class Coordinator: NSObject {
        private struct ViewportState {
            let logicalPageID: UUID?
            let composedPageIndex: Int?
            let normalizedCenter: CGPoint?
            let scaleFactor: CGFloat
        }

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
        private var lastHandledFocusRequestID: Int?

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
                scrollView.decelerationRate = .normal
                
                contentOffsetObserver = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                    self?.overlay.scheduleRefresh()
                }
                zoomScaleObserver = scrollView.observe(\.zoomScale, options: [.new]) { [weak self] _, _ in
                    self?.overlay.scheduleRefresh()
                }
            }
        }

        func updateOverlay(
            anchors: [NoteAnchorOverlayItem],
            pageTagsByComposedIndex: [Int: PageTagOverlayItem],
            selectedNoteID: UUID?,
            isCreateMode: Bool,
            showsInlineNoteBubbles: Bool,
            isEditingEnabled: Bool
        ) {
            // 利用 Equatable 完全截断无变化的传递事件，解绑 View 层求值与底层 Overlay 渲染的强耦合关系
            if overlay.anchors != anchors {
                overlay.anchors = anchors
            }
            if overlay.pageTagsByComposedIndex != pageTagsByComposedIndex {
                overlay.pageTagsByComposedIndex = pageTagsByComposedIndex
            }
            if overlay.selectedNoteID != selectedNoteID {
                overlay.selectedNoteID = selectedNoteID
            }
            if overlay.isCreateMode != isCreateMode {
                overlay.isCreateMode = isCreateMode
            }
            if overlay.showsContentBubbles != showsInlineNoteBubbles {
                overlay.showsContentBubbles = showsInlineNoteBubbles
            }
            if overlay.isEditingEnabled != isEditingEnabled {
                overlay.isEditingEnabled = isEditingEnabled
            }
        }

        func apply(entries: [ComposedPDFPageEntry], to pdfView: PDFView) {
            let newSignature = makeSignature(entries)
            guard newSignature != signature else {
                return
            }
            
            let previousViewport = captureViewportState(from: pdfView)
            
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
            pdfView.autoScales = previousViewport == nil
            pdfView.usePageViewController(false, withViewOptions: nil)
            
            // 只有当整个文档变动时，才更新底层的索引映射，从而切断每帧传递造成的调度阻塞
            overlay.pageByComposedIndex = pageByComposedIndex
            overlay.scheduleRefresh()
            
            var restoredComposedIndex: Int?
            if let previousViewport {
                restoredComposedIndex = restoreViewportState(previousViewport, on: pdfView)
            } else if composedIndex > 0, let firstPage = document.page(at: 0) {
                pdfView.go(to: firstPage)
                restoredComposedIndex = 0
            }
            
            if let restoredComposedIndex {
                notifyFocusedComposedPageChanged(restoredComposedIndex)
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
            overlay.scheduleRefresh()
        }

        func focus(on anchor: NoteAnchorOverlayItem?, requestID: Int) {
            guard let pdfView else { return }
            
            guard let anchor else {
                lastFocusedNoteID = nil
                lastHandledFocusRequestID = requestID
                return
            }
            
            if lastFocusedNoteID == anchor.id,
               lastHandledFocusRequestID == requestID {
                return
            }
            
            lastFocusedNoteID = anchor.id
            lastHandledFocusRequestID = requestID
            
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
            overlay.scheduleRefresh()
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
            overlay.scheduleRefresh()
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

        private func captureViewportState(from pdfView: PDFView) -> ViewportState? {
            guard let document = pdfView.document,
                  let currentPage = pdfView.currentPage else {
                return nil
            }
            
            let currentIndex = document.index(for: currentPage)
            guard currentIndex >= 0 else { return nil }
            
            let logicalPageID = pageEntryByComposedIndex[currentIndex]?.logicalPageID
            
            let pageBounds = currentPage.bounds(for: .mediaBox)
            let visibleRect = pdfView.convert(pdfView.bounds, to: currentPage)
            
            var normalizedCenter: CGPoint?
            if !visibleRect.isNull,
               !visibleRect.isEmpty,
               pageBounds.width > 0,
               pageBounds.height > 0 {
                normalizedCenter = CGPoint(
                    x: clamp01((visibleRect.midX - pageBounds.minX) / pageBounds.width),
                    y: clamp01((visibleRect.midY - pageBounds.minY) / pageBounds.height)
                )
            }
            
            return ViewportState(
                logicalPageID: logicalPageID,
                composedPageIndex: currentIndex,
                normalizedCenter: normalizedCenter,
                scaleFactor: pdfView.scaleFactor
            )
        }

        private func restoreViewportState(_ state: ViewportState, on pdfView: PDFView) -> Int? {
            guard let document = pdfView.document, document.pageCount > 0 else {
                return nil
            }
            
            let targetIndex = resolvedComposedIndex(for: state, pageCount: document.pageCount) ?? 0
            guard let targetPage = document.page(at: targetIndex) else {
                return nil
            }
            
            pdfView.go(to: targetPage)
            
            let clampedScale = max(pdfView.minScaleFactor, min(pdfView.maxScaleFactor, state.scaleFactor))
            if clampedScale.isFinite, clampedScale > 0 {
                pdfView.autoScales = false
                pdfView.scaleFactor = clampedScale
            }
            
            if let normalizedCenter = state.normalizedCenter {
                restoreViewportCenter(
                    normalizedCenter: normalizedCenter,
                    on: targetPage,
                    in: pdfView
                )
            }
            
            return targetIndex
        }

        private func resolvedComposedIndex(for state: ViewportState, pageCount: Int) -> Int? {
            if let logicalPageID = state.logicalPageID,
               let matchedIndex = pageEntryByComposedIndex.first(where: { $0.value.logicalPageID == logicalPageID })?.key,
               matchedIndex >= 0,
               matchedIndex < pageCount {
                return matchedIndex
            }
            
            if let composedPageIndex = state.composedPageIndex,
               composedPageIndex >= 0,
               composedPageIndex < pageCount {
                return composedPageIndex
            }
            
            return nil
        }

        private func restoreViewportCenter(
            normalizedCenter: CGPoint,
            on page: PDFPage,
            in pdfView: PDFView
        ) {
            let pageBounds = page.bounds(for: .mediaBox)
            guard pageBounds.width > 0, pageBounds.height > 0 else { return }
            
            let clampedCenter = CGPoint(
                x: clamp01(normalizedCenter.x),
                y: clamp01(normalizedCenter.y)
            )
            
            let centerPoint = CGPoint(
                x: pageBounds.minX + clampedCenter.x * pageBounds.width,
                y: pageBounds.minY + clampedCenter.y * pageBounds.height
            )
            
            var visibleRect = pdfView.convert(pdfView.bounds, to: page)
            if visibleRect.isNull || visibleRect.isEmpty {
                let scale = max(pdfView.scaleFactor, 0.01)
                visibleRect = CGRect(
                    x: pageBounds.minX,
                    y: pageBounds.minY,
                    width: pageBounds.width / scale,
                    height: pageBounds.height / scale
                )
            }
            
            var targetRect = CGRect(
                x: centerPoint.x - visibleRect.width / 2,
                y: centerPoint.y - visibleRect.height / 2,
                width: min(visibleRect.width, pageBounds.width),
                height: min(visibleRect.height, pageBounds.height)
            )
            
            targetRect.origin.x = max(
                pageBounds.minX,
                min(pageBounds.maxX - targetRect.width, targetRect.origin.x)
            )
            targetRect.origin.y = max(
                pageBounds.minY,
                min(pageBounds.maxY - targetRect.height, targetRect.origin.y)
            )
            
            pdfView.go(to: targetRect, on: page)
        }

        private func clamp01(_ value: CGFloat) -> CGFloat {
            max(0, min(1, value))
        }
    }
}
