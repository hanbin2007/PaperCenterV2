//
//  PaperCenterV2Tests.swift
//  PaperCenterV2Tests
//
//  Focused unit tests for domain-level invariants.
//

import XCTest
import SwiftData
import PDFKit
import UIKit
@testable import PaperCenterV2

final class PaperCenterV2Tests: XCTestCase {

    func testPageInitializationCreatesFirstVersion() throws {
        let bundle = PDFBundle(name: "Bundle A")
        let page = Page(pdfBundle: bundle, pageNumber: 3)

        XCTAssertEqual(page.currentPDFBundleID, bundle.id)
        XCTAssertEqual(page.currentPageNumber, 3)

        let versions = try XCTUnwrap(page.versions)
        XCTAssertEqual(versions.count, 1)

        let firstVersion = try XCTUnwrap(versions.first)
        XCTAssertEqual(firstVersion.pdfBundleID, bundle.id)
        XCTAssertEqual(firstVersion.pageNumber, 3)
    }

    func testUpdateReferenceDoesNotCreateVersionWhenUnchanged() {
        let bundle = PDFBundle(name: "Bundle A")
        let page = Page(pdfBundle: bundle, pageNumber: 1)
        let initialCount = page.versions?.count ?? 0

        let didCreateVersion = page.updateReference(to: bundle, pageNumber: 1)

        XCTAssertFalse(didCreateVersion)
        XCTAssertEqual(page.versions?.count, initialCount)
    }

    func testUpdateReferenceCreatesVersionWhenBundleChanges() throws {
        let bundleA = PDFBundle(name: "Bundle A")
        let bundleB = PDFBundle(name: "Bundle B")
        let page = Page(pdfBundle: bundleA, pageNumber: 2)

        let didCreateVersion = page.updateReference(to: bundleB, pageNumber: 2)

        XCTAssertTrue(didCreateVersion)
        XCTAssertEqual(page.currentPDFBundleID, bundleB.id)
        XCTAssertEqual(page.currentPageNumber, 2)
        XCTAssertEqual(page.versions?.count, 2)

        let latest = try XCTUnwrap(page.latestVersion)
        XCTAssertEqual(latest.pdfBundleID, bundleB.id)
        XCTAssertEqual(latest.pageNumber, 2)
    }

    func testUpdateReferenceCreatesVersionWhenPageNumberChanges() throws {
        let bundle = PDFBundle(name: "Bundle A")
        let page = Page(pdfBundle: bundle, pageNumber: 2)

        let didCreateVersion = page.updateReference(to: bundle, pageNumber: 5)

        XCTAssertTrue(didCreateVersion)
        XCTAssertEqual(page.currentPDFBundleID, bundle.id)
        XCTAssertEqual(page.currentPageNumber, 5)
        XCTAssertEqual(page.versions?.count, 2)

        let latest = try XCTUnwrap(page.latestVersion)
        XCTAssertEqual(latest.pageNumber, 5)
    }

    func testDocOrderedPageGroupsFollowsPageGroupOrder() {
        let doc = Doc(title: "Doc")
        let group1 = PageGroup(title: "Group 1")
        let group2 = PageGroup(title: "Group 2")
        let group3 = PageGroup(title: "Group 3")

        doc.addPageGroup(group1)
        doc.addPageGroup(group2)
        doc.addPageGroup(group3)
        doc.reorderPageGroups([group3.id, group1.id, group2.id])

        XCTAssertEqual(doc.orderedPageGroups.map(\.id), [group3.id, group1.id, group2.id])
    }

    func testPageGroupOrderedPagesFollowsPageOrder() {
        let bundle = PDFBundle(name: "Bundle")
        let group = PageGroup(title: "Group")
        let page1 = Page(pdfBundle: bundle, pageNumber: 1)
        let page2 = Page(pdfBundle: bundle, pageNumber: 2)
        let page3 = Page(pdfBundle: bundle, pageNumber: 3)

        group.addPage(page1)
        group.addPage(page2)
        group.addPage(page3)
        group.reorderPages([page2.id, page3.id, page1.id])

        XCTAssertEqual(group.orderedPages.map(\.id), [page2.id, page3.id, page1.id])
    }

    func testTagScopeDocAndBelowDoesNotAllowPDFBundle() {
        XCTAssertTrue(TagScope.docAndBelow.canTag(.doc))
        XCTAssertTrue(TagScope.docAndBelow.canTag(.pageGroup))
        XCTAssertTrue(TagScope.docAndBelow.canTag(.page))
        XCTAssertFalse(TagScope.docAndBelow.canTag(.pdfBundle))
    }

    func testVariableListValidationUsesConfiguredOptions() {
        let variable = Variable(
            name: "Difficulty",
            type: .list,
            scope: .doc,
            listOptions: ["Easy", "Medium", "Hard"]
        )

        XCTAssertTrue(variable.isValid(listValue: "Medium"))
        XCTAssertFalse(variable.isValid(listValue: "Impossible"))
    }

    func testNoteBlockAddChildBuildsHierarchy() throws {
        let root = makeRootNote(body: "Root")
        let child = root.makeReply(body: "Child")

        let inserted = try root.addChild(child)

        XCTAssertTrue(inserted)
        XCTAssertEqual(child.parent?.id, root.id)
        XCTAssertEqual(child.parentNoteID, root.id)
        XCTAssertEqual(root.orderedChildren(from: [root, child]).map(\.id), [child.id])
        XCTAssertEqual(child.nestingLevel(in: [root.id: root, child.id: child]), 1)
    }

    func testNoteBlockAddChildRejectsCrossAnchorParenting() throws {
        let rootA = makeRootNote(body: "A")
        let rootB = makeRootNote(body: "B")
        let child = rootB.makeReply(body: "B child")

        XCTAssertThrowsError(try rootA.addChild(child)) { error in
            guard case NoteHierarchyError.crossAnchorParenting = error else {
                XCTFail("Expected crossAnchorParenting, got \(error)")
                return
            }
        }
    }

    func testNoteBlockAddChildRejectsCircularReference() throws {
        let root = makeRootNote(body: "Root")
        let child = root.makeReply(body: "Child")
        _ = try root.addChild(child)

        XCTAssertThrowsError(try child.addChild(root)) { error in
            guard case NoteHierarchyError.circularReference = error else {
                XCTFail("Expected circularReference, got \(error)")
                return
            }
        }
    }

    func testNoteBlockReorderChildrenValidatesExactSet() throws {
        let root = makeRootNote(body: "Root")
        let child1 = root.makeReply(body: "Child 1")
        let child2 = root.makeReply(body: "Child 2")
        _ = try root.addChild(child1)
        _ = try root.addChild(child2)

        XCTAssertThrowsError(try root.reorderChildren([child1.id], from: [root, child1, child2])) { error in
            guard case NoteHierarchyError.invalidChildOrder = error else {
                XCTFail("Expected invalidChildOrder, got \(error)")
                return
            }
        }

        XCTAssertNoThrow(try root.reorderChildren([child2.id, child1.id], from: [root, child1, child2]))
        XCTAssertEqual(root.orderedChildren(from: [root, child1, child2]).map(\.id), [child2.id, child1.id])
    }

    @MainActor
    func testImportPDFRejectsReplacingExistingBundleVariant() async throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let service = PDFImportService(modelContext: context)

        let bundle = PDFBundle(name: "Protected Bundle")
        context.insert(bundle)
        bundle.setPath("PDFBundles/\(bundle.id.uuidString)/display.pdf", for: .display)

        let sourceURL = try makeTemporaryPDF()
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        do {
            _ = try await service.importPDF(from: sourceURL, type: .display, into: bundle)
            XCTFail("Expected replacement guard to throw")
        } catch PDFImportError.bundleVariantAlreadyExists {
            // Expected
        } catch {
            XCTFail("Expected bundleVariantAlreadyExists, got \(error)")
        }
    }

    private func makeRootNote(body: String) -> NoteBlock {
        let bundle = PDFBundle(name: "Bundle")
        let page = Page(pdfBundle: bundle, pageNumber: 1)
        let pageVersion = page.latestVersion!
        return NoteBlock.createNormalized(
            pageVersion: pageVersion,
            absoluteRect: CGRect(x: 10, y: 10, width: 100, height: 50),
            pageSize: CGSize(width: 200, height: 400),
            title: nil,
            body: body
        )
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            PDFBundle.self,
            Page.self,
            PageVersion.self,
            PageGroup.self,
            Doc.self,
            NoteBlock.self,
            Tag.self,
            TagGroup.self,
            Variable.self,
            PDFBundleVariableAssignment.self,
            DocVariableAssignment.self,
            PageGroupVariableAssignment.self,
            PageVariableAssignment.self,
            NoteBlockVariableAssignment.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeTemporaryPDF() throws -> URL {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 300))
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 200, height: 300))
            UIColor.black.setStroke()
            context.cgContext.setLineWidth(2)
            context.cgContext.stroke(CGRect(x: 8, y: 8, width: 184, height: 284))
        }
        guard let page = PDFPage(image: image) else {
            throw NSError(domain: "PaperCenterV2Tests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create PDF page"])
        }
        let document = PDFDocument()
        document.insert(page, at: 0)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        guard document.write(to: url) else {
            throw NSError(domain: "PaperCenterV2Tests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to write temporary PDF"])
        }
        return url
    }
}
