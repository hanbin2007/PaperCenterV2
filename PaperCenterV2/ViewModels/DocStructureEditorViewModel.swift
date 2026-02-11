//
//  DocStructureEditorViewModel.swift
//  PaperCenterV2
//
//  Editing logic for a single document tree (Doc -> PageGroup -> Page).
//

import Foundation
import PDFKit
import SwiftData

@MainActor
@Observable
final class DocStructureEditorViewModel {

    let doc: Doc

    var statusMessage: String?
    var errorMessage: String?

    private let modelContext: ModelContext

    init(modelContext: ModelContext, doc: Doc) {
        self.modelContext = modelContext
        self.doc = doc
    }

    var orderedGroups: [PageGroup] {
        doc.orderedPageGroups
    }

    func renameDocument(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Document title cannot be empty"
            return
        }

        doc.title = trimmed
        doc.touch()
        persist(success: "Document title updated")
    }

    @discardableResult
    func createPageGroup(title: String) -> PageGroup? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Page group title cannot be empty"
            return nil
        }

        let group = PageGroup(title: trimmed, doc: doc)
        doc.addPageGroup(group)
        modelContext.insert(group)
        persist(success: "Page group added")
        return group
    }

    func renamePageGroup(_ group: PageGroup, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Page group title cannot be empty"
            return
        }

        group.title = trimmed
        group.touch()
        doc.touch()
        persist(success: "Page group renamed")
    }

    func deletePageGroup(_ group: PageGroup) {
        doc.removePageGroup(group)
        modelContext.delete(group)
        persist(success: "Page group deleted")
    }

    func movePageGroup(_ group: PageGroup, by offset: Int) {
        guard let index = doc.pageGroupOrder.firstIndex(of: group.id) else { return }
        let destination = index + offset
        guard destination >= 0, destination < doc.pageGroupOrder.count else { return }

        var order = doc.pageGroupOrder
        let moved = order.remove(at: index)
        order.insert(moved, at: destination)
        doc.reorderPageGroups(order)
        persist(success: "Page group moved")
    }

    @discardableResult
    func createPage(
        in group: PageGroup,
        bundle: PDFBundle,
        pageNumber: Int
    ) -> Page? {
        guard pageNumber > 0 else {
            errorMessage = "Page number must be greater than 0"
            return nil
        }

        guard isValidPageNumber(pageNumber, in: bundle) else {
            errorMessage = "Page number is out of range for the selected bundle"
            return nil
        }

        let page = Page(pdfBundle: bundle, pageNumber: pageNumber, pageGroup: group)
        group.addPage(page)
        modelContext.insert(page)
        doc.touch()
        persist(success: "Page added")
        return page
    }

    func updatePage(
        _ page: Page,
        bundle: PDFBundle,
        pageNumber: Int
    ) {
        guard pageNumber > 0 else {
            errorMessage = "Page number must be greater than 0"
            return
        }

        guard isValidPageNumber(pageNumber, in: bundle) else {
            errorMessage = "Page number is out of range for the selected bundle"
            return
        }

        _ = page.updateReference(to: bundle, pageNumber: pageNumber)
        doc.touch()
        persist(success: "Page updated")
    }

    func deletePage(_ page: Page) {
        if let group = page.pageGroup {
            group.removePage(page)
        }
        modelContext.delete(page)
        doc.touch()
        persist(success: "Page deleted")
    }

    func movePage(_ page: Page, in group: PageGroup, by offset: Int) {
        guard let index = group.pageOrder.firstIndex(of: page.id) else { return }
        let destination = index + offset
        guard destination >= 0, destination < group.pageOrder.count else { return }

        var order = group.pageOrder
        let moved = order.remove(at: index)
        order.insert(moved, at: destination)
        group.reorderPages(order)
        doc.touch()
        persist(success: "Page moved")
    }

    func movePage(
        _ page: Page,
        from sourceGroup: PageGroup,
        to destinationGroup: PageGroup
    ) {
        if sourceGroup.id == destinationGroup.id { return }

        sourceGroup.removePage(page)
        destinationGroup.addPage(page)
        doc.touch()
        persist(success: "Page moved to \(destinationGroup.title)")
    }

    func pageCount(for bundle: PDFBundle) -> Int {
        for type in [PDFType.display, PDFType.original, PDFType.ocr] {
            guard let url = bundle.fileURL(for: type),
                  let document = PDFDocument(url: url) else {
                continue
            }
            return document.pageCount
        }
        return 0
    }

    func isValidPageNumber(_ pageNumber: Int, in bundle: PDFBundle) -> Bool {
        let count = pageCount(for: bundle)
        if count <= 0 {
            return pageNumber > 0
        }
        return (1...count).contains(pageNumber)
    }

    private func persist(success: String) {
        do {
            try modelContext.save()
            statusMessage = success
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
