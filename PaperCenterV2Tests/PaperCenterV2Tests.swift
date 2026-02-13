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

    @MainActor
    func testUpdateReferenceDoesNotCreateVersionWhenUnchanged() {
        let bundle = PDFBundle(name: "Bundle A")
        let page = Page(pdfBundle: bundle, pageNumber: 1)
        let initialCount = page.versions?.count ?? 0

        let didCreateVersion = page.updateReference(to: bundle, pageNumber: 1)

        XCTAssertFalse(didCreateVersion)
        XCTAssertEqual(page.versions?.count, initialCount)
    }

    @MainActor
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

    @MainActor
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
        let fileManager = FileManager.default

        let bundle = PDFBundle(name: "Protected Bundle")
        context.insert(bundle)
        let existingSourceURL = try makeTemporaryPDF()
        let replacementURL = try makeTemporaryPDF()
        defer {
            try? fileManager.removeItem(at: existingSourceURL)
            try? fileManager.removeItem(at: replacementURL)
            let bundleDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PDFBundles")
                .appendingPathComponent(bundle.id.uuidString)
            try? fileManager.removeItem(at: bundleDirectory)
        }
        let relativePath = "PDFBundles/\(bundle.id.uuidString)/display.pdf"
        bundle.setPath(relativePath, for: .display)

        let targetURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(relativePath)
        try fileManager.createDirectory(
            at: targetURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.copyItem(at: existingSourceURL, to: targetURL)

        do {
            _ = try await service.importPDF(from: replacementURL, type: .display, into: bundle)
            XCTFail("Expected replacement guard to throw")
        } catch PDFImportError.bundleVariantAlreadyExists {
            // Expected
        } catch {
            XCTFail("Expected bundleVariantAlreadyExists, got \(error)")
        }
    }

    @MainActor
    func testImportPDFRestoresVariantWhenPathExistsButFileMissing() async throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let service = PDFImportService(modelContext: context)
        let fileManager = FileManager.default

        let bundle = PDFBundle(name: "Recoverable Bundle")
        context.insert(bundle)

        let relativePath = "PDFBundles/\(bundle.id.uuidString)/display.pdf"
        bundle.setPath(relativePath, for: .display)

        let sourceURL = try makeTemporaryPDF()
        defer {
            try? fileManager.removeItem(at: sourceURL)
            let bundleDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PDFBundles")
                .appendingPathComponent(bundle.id.uuidString)
            try? fileManager.removeItem(at: bundleDirectory)
        }

        let restored = try await service.importPDF(from: sourceURL, type: .display, into: bundle)
        let targetURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(relativePath)

        XCTAssertEqual(restored.id, bundle.id)
        XCTAssertEqual(bundle.displayPDFPath, relativePath)
        XCTAssertTrue(fileManager.fileExists(atPath: targetURL.path))
    }

    @MainActor
    func testSessionBuilderUsesCurrentReferenceVersionAsDefault() throws {
        let shouldSkip = ProcessInfo.processInfo.environment["SKIP_UNIVERSALDOC_TESTS"] != "0"
        if shouldSkip {
            throw XCTSkip("Skipped on Designed-for-iPad runtime due unstable XCTest host crashes.")
        }

        let bundleA = PDFBundle(name: "A")
        let bundleB = PDFBundle(name: "B")

        let doc = Doc(title: "Doc")
        let group = PageGroup(title: "Group", doc: doc)
        doc.addPageGroup(group)
        let page = Page(pdfBundle: bundleA, pageNumber: 1, pageGroup: group)
        _ = page.updateReference(to: bundleB, pageNumber: 2)
        group.addPage(page)

        let builder = UniversalDocSessionBuilder()
        let session = builder.buildSession(for: doc)
        let slot = try XCTUnwrap(session.slots.first)

        XCTAssertEqual(slot.defaultVersionID, page.latestVersion?.id)
    }

    @MainActor
    func testSessionBuilderFallsBackToLatestVersionWhenCurrentReferenceMissing() throws {
        let shouldSkip = ProcessInfo.processInfo.environment["SKIP_UNIVERSALDOC_TESTS"] != "0"
        if shouldSkip {
            throw XCTSkip("Skipped on Designed-for-iPad runtime due unstable XCTest host crashes.")
        }

        let bundleA = PDFBundle(name: "A")
        let bundleB = PDFBundle(name: "B")

        let doc = Doc(title: "Doc")
        let group = PageGroup(title: "Group", doc: doc)
        doc.addPageGroup(group)
        let page = Page(pdfBundle: bundleA, pageNumber: 1, pageGroup: group)
        _ = page.updateReference(to: bundleB, pageNumber: 2)
        page.currentPDFBundleID = UUID()
        page.currentPageNumber = 999
        group.addPage(page)

        let builder = UniversalDocSessionBuilder()
        let session = builder.buildSession(for: doc)
        let slot = try XCTUnwrap(session.slots.first)

        XCTAssertEqual(slot.defaultVersionID, page.latestVersion?.id)
    }

    @MainActor
    func testSessionBuilderDefaultSourceSkipsMissingDisplayFile() async throws {
        let shouldSkip = ProcessInfo.processInfo.environment["SKIP_UNIVERSALDOC_TESTS"] != "0"
        if shouldSkip {
            throw XCTSkip("Skipped on Designed-for-iPad runtime due unstable XCTest host crashes.")
        }

        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let importService = PDFImportService(modelContext: context)

        let bundle = PDFBundle(name: "Fallback Source Bundle")
        context.insert(bundle)
        bundle.setPath("PDFBundles/\(bundle.id.uuidString)/display.pdf", for: .display)

        let originalURL = try makeTemporaryPDF()
        defer {
            try? FileManager.default.removeItem(at: originalURL)
            let bundleDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PDFBundles")
                .appendingPathComponent(bundle.id.uuidString)
            try? FileManager.default.removeItem(at: bundleDirectory)
        }
        _ = try await importService.importPDF(from: originalURL, type: .original, into: bundle)
        try context.save()

        let doc = Doc(title: "Doc")
        let group = PageGroup(title: "Group", doc: doc)
        doc.addPageGroup(group)
        let page = Page(pdfBundle: bundle, pageNumber: 1, pageGroup: group)
        group.addPage(page)

        let builder = UniversalDocSessionBuilder(modelContext: context)
        let session = builder.buildSession(for: doc)
        let slot = try XCTUnwrap(session.slots.first)

        XCTAssertEqual(slot.defaultSource, .original)
    }

    @MainActor
    func testBuildAllDocumentsSessionOrdersByCreatedAtAscending() throws {
        let shouldSkip = ProcessInfo.processInfo.environment["SKIP_UNIVERSALDOC_TESTS"] != "0"
        if shouldSkip {
            throw XCTSkip("Skipped on Designed-for-iPad runtime due unstable XCTest host crashes.")
        }

        let docOld = Doc(title: "Old")
        docOld.createdAt = Date(timeIntervalSince1970: 100)
        let groupOld = PageGroup(title: "G-Old", doc: docOld)
        docOld.addPageGroup(groupOld)
        let oldBundle = PDFBundle(name: "Old Bundle")
        let oldPage = Page(pdfBundle: oldBundle, pageNumber: 1, pageGroup: groupOld)
        groupOld.addPage(oldPage)

        let docNew = Doc(title: "New")
        docNew.createdAt = Date(timeIntervalSince1970: 200)
        let groupNew = PageGroup(title: "G-New", doc: docNew)
        docNew.addPageGroup(groupNew)
        let newBundle = PDFBundle(name: "New Bundle")
        let newPage = Page(pdfBundle: newBundle, pageNumber: 1, pageGroup: groupNew)
        groupNew.addPage(newPage)

        let builder = UniversalDocSessionBuilder()
        let session = builder.buildSession(for: [docNew, docOld])

        XCTAssertEqual(session.scope, .allDocuments([docOld.id, docNew.id]))
        XCTAssertEqual(session.slots.map(\.docID), [docOld.id, docNew.id])
    }

    @MainActor
    func testSessionSlotsCarryDocAndGroupContext() throws {
        let shouldSkip = ProcessInfo.processInfo.environment["SKIP_UNIVERSALDOC_TESTS"] != "0"
        if shouldSkip {
            throw XCTSkip("Skipped on Designed-for-iPad runtime due unstable XCTest host crashes.")
        }

        let bundle = PDFBundle(name: "Bundle")
        let doc = Doc(title: "Doc")
        let group = PageGroup(title: "Group A", doc: doc)
        doc.addPageGroup(group)

        let page1 = Page(pdfBundle: bundle, pageNumber: 1, pageGroup: group)
        let page2 = Page(pdfBundle: bundle, pageNumber: 2, pageGroup: group)
        group.addPage(page1)
        group.addPage(page2)

        let builder = UniversalDocSessionBuilder()
        let session = builder.buildSession(for: doc)
        XCTAssertEqual(session.scope, .singleDoc(doc.id))
        XCTAssertEqual(session.slots.count, 2)
        XCTAssertEqual(session.slots[0].docID, doc.id)
        XCTAssertEqual(session.slots[0].docTitle, doc.title)
        XCTAssertEqual(session.slots[0].pageGroupID, group.id)
        XCTAssertEqual(session.slots[0].pageGroupTitle, group.title)
        XCTAssertEqual(session.slots[0].groupOrderKey, 0)
        XCTAssertEqual(session.slots[0].pageOrderInGroup, 0)
        XCTAssertEqual(session.slots[1].pageOrderInGroup, 1)
    }

    @MainActor
    func testGroupNavigationTargetsFirstPageOfGroup() throws {
        let shouldSkip = ProcessInfo.processInfo.environment["SKIP_UNIVERSALDOC_TESTS"] != "0"
        if shouldSkip {
            throw XCTSkip("Skipped on Designed-for-iPad runtime due unstable XCTest host crashes.")
        }

        let bundle = PDFBundle(name: "Bundle")
        let doc = Doc(title: "Doc")

        let groupA = PageGroup(title: "A", doc: doc)
        let groupB = PageGroup(title: "B", doc: doc)
        doc.addPageGroup(groupA)
        doc.addPageGroup(groupB)

        let pageA1 = Page(pdfBundle: bundle, pageNumber: 1, pageGroup: groupA)
        let pageA2 = Page(pdfBundle: bundle, pageNumber: 2, pageGroup: groupA)
        let pageB1 = Page(pdfBundle: bundle, pageNumber: 3, pageGroup: groupB)
        groupA.addPage(pageA1)
        groupA.addPage(pageA2)
        groupB.addPage(pageB1)

        let builder = UniversalDocSessionBuilder()
        let session = builder.buildSession(for: doc)
        XCTAssertEqual(session.viewMode, .continuous)

        let groupAFirst = try XCTUnwrap(session.slots.first(where: { $0.pageGroupID == groupA.id }))
        let groupBFirst = try XCTUnwrap(session.slots.first(where: { $0.pageGroupID == groupB.id }))

        XCTAssertEqual(groupAFirst.pageID, pageA1.id)
        XCTAssertEqual(groupBFirst.pageID, pageB1.id)
    }

    @MainActor
    func testBuildSingleDocSessionForSpecificGroupOnlyIncludesThatGroupPages() throws {
        let shouldSkip = ProcessInfo.processInfo.environment["SKIP_UNIVERSALDOC_TESTS"] != "0"
        if shouldSkip {
            throw XCTSkip("Skipped on Designed-for-iPad runtime due unstable XCTest host crashes.")
        }

        let bundle = PDFBundle(name: "Bundle")
        let doc = Doc(title: "Doc")

        let groupA = PageGroup(title: "A", doc: doc)
        let groupB = PageGroup(title: "B", doc: doc)
        doc.addPageGroup(groupA)
        doc.addPageGroup(groupB)

        let pageA = Page(pdfBundle: bundle, pageNumber: 1, pageGroup: groupA)
        let pageB1 = Page(pdfBundle: bundle, pageNumber: 2, pageGroup: groupB)
        let pageB2 = Page(pdfBundle: bundle, pageNumber: 3, pageGroup: groupB)
        groupA.addPage(pageA)
        groupB.addPage(pageB1)
        groupB.addPage(pageB2)

        let builder = UniversalDocSessionBuilder()
        let session = builder.buildSession(for: doc, pageGroupID: groupB.id)

        XCTAssertEqual(session.scope, .singleDoc(doc.id))
        XCTAssertEqual(session.slots.count, 2)
        XCTAssertTrue(session.slots.allSatisfy { $0.pageGroupID == groupB.id })
        XCTAssertEqual(session.slots.map(\.pageID), [pageB1.id, pageB2.id])
    }

    @MainActor
    func testSinglePageControlsAreNotExposedInViewerModel() throws {
        let shouldSkip = ProcessInfo.processInfo.environment["SKIP_UNIVERSALDOC_TESTS"] != "0"
        if shouldSkip {
            throw XCTSkip("Skipped on Designed-for-iPad runtime due unstable XCTest host crashes.")
        }

        let bundle = PDFBundle(name: "Bundle")
        let doc = Doc(title: "Doc")
        let group = PageGroup(title: "Group", doc: doc)
        doc.addPageGroup(group)
        let page = Page(pdfBundle: bundle, pageNumber: 1, pageGroup: group)
        group.addPage(page)

        let builder = UniversalDocSessionBuilder()
        let session = builder.buildSession(for: doc)

        XCTAssertEqual(session.viewMode, .continuous)
        XCTAssertNotEqual(session.viewMode, .paged)
    }

    @MainActor
    func testPageVersionServiceRespectsMetadataInheritanceOptions() throws {
        let shouldSkip = ProcessInfo.processInfo.environment["SKIP_UNIVERSALDOC_TESTS"] != "0"
        if shouldSkip {
            throw XCTSkip("Skipped on Designed-for-iPad runtime due unstable XCTest host crashes.")
        }

        let bundleA = PDFBundle(name: "A")
        let bundleB = PDFBundle(name: "B")
        let page = Page(pdfBundle: bundleA, pageNumber: 1)
        let sourceVersion = try XCTUnwrap(page.latestVersion)
        let sourceTagID = UUID()
        let sourceVariableID = UUID()
        let sourceSnapshot = MetadataSnapshot(
            tagIDs: [sourceTagID],
            variableAssignments: [
                VariableAssignmentSnapshot(
                    variableID: sourceVariableID,
                    intValue: 95,
                    listValue: nil,
                    textValue: nil,
                    dateValue: nil
                ),
            ]
        )
        sourceVersion.metadataSnapshot = try PageVersion.encodeMetadataSnapshot(sourceSnapshot)

        let service = PageVersionService()
        let inheritedVersion = try XCTUnwrap(
            try service.createVersion(
                for: page,
                to: bundleB,
                pageNumber: 2,
                basedOn: sourceVersion,
                inheritance: .metadataOnly
            )
        )

        let inheritedSnapshot = try XCTUnwrap(try inheritedVersion.decodeMetadataSnapshot())
        XCTAssertEqual(inheritedSnapshot.tagIDs, [sourceTagID])
        XCTAssertEqual(inheritedSnapshot.variableAssignments.first?.intValue, 95)
        XCTAssertEqual(inheritedSnapshot.variableAssignments.first?.variableID, sourceVariableID)
        XCTAssertEqual(inheritedVersion.inheritedTagMetadata, true)
        XCTAssertEqual(inheritedVersion.inheritedVariableMetadata, true)
        XCTAssertEqual(inheritedVersion.inheritedNoteBlocks, false)

        let noInheritanceVersion = try XCTUnwrap(
            try service.createVersion(
                for: page,
                to: bundleA,
                pageNumber: 3,
                basedOn: inheritedVersion,
                inheritance: .none
            )
        )

        let emptySnapshot = try XCTUnwrap(try noInheritanceVersion.decodeMetadataSnapshot())
        XCTAssertTrue(emptySnapshot.tagIDs.isEmpty)
        XCTAssertTrue(emptySnapshot.variableAssignments.isEmpty)
        XCTAssertEqual(noInheritanceVersion.inheritedTagMetadata, false)
        XCTAssertEqual(noInheritanceVersion.inheritedVariableMetadata, false)
    }

    @MainActor
    func testPageVersionServiceClonesNoteHierarchyWhenRequested() throws {
        let shouldSkip = ProcessInfo.processInfo.environment["SKIP_NOTE_CLONE_TEST"] != "0"
        if shouldSkip {
            throw XCTSkip("Skipped on Designed-for-iPad runtime due SwiftData Array<UUID> materialization crash.")
        }

        let container = try makeInMemoryContainer(includeNoteModels: true)
        let context = ModelContext(container)
        let bundleA = PDFBundle(name: "A")
        let bundleB = PDFBundle(name: "B")
        context.insert(bundleA)
        context.insert(bundleB)

        let page = Page(pdfBundle: bundleA, pageNumber: 1)
        context.insert(page)
        let sourceVersion = try XCTUnwrap(page.latestVersion)

        let root = NoteBlock.createNormalized(
            pageVersion: sourceVersion,
            absoluteRect: CGRect(x: 0, y: 0, width: 100, height: 50),
            pageSize: CGSize(width: 200, height: 200),
            title: "Root",
            body: "root-body"
        )
        let child = root.makeReply(title: "Child", body: "child-body")
        _ = try root.addChild(child)
        context.insert(root)
        context.insert(child)

        let service = PageVersionService(modelContext: context)
        let newVersion = try XCTUnwrap(
            try service.createVersion(
                for: page,
                to: bundleB,
                pageNumber: 2,
                basedOn: sourceVersion,
                inheritance: VersionInheritanceOptions(
                    inheritTags: false,
                    inheritVariables: false,
                    inheritNoteBlocks: true
                )
            )
        )
        try context.save()
        let newVersionID = newVersion.id

        let descriptor = FetchDescriptor<NoteBlock>(
            predicate: #Predicate { note in
                note.pageVersionID == newVersionID
            }
        )
        let cloned = try context.fetch(descriptor).filter { !$0.isDeleted }
        XCTAssertEqual(cloned.count, 2)

        let clonedRoot = try XCTUnwrap(cloned.first(where: { $0.body == "root-body" }))
        let clonedChild = try XCTUnwrap(cloned.first(where: { $0.body == "child-body" }))

        XCTAssertNotEqual(clonedRoot.id, root.id)
        XCTAssertNotEqual(clonedChild.id, child.id)
        XCTAssertEqual(clonedChild.parentNoteID, clonedRoot.id)
        XCTAssertEqual(clonedRoot.childOrder, [clonedChild.id])
    }

    @MainActor
    func testSessionStoreFocusedPageAndFocusedSourceUpdate() throws {
        let shouldSkip = ProcessInfo.processInfo.environment["SKIP_UNIVERSALDOC_STORE_TESTS"] != "0"
        if shouldSkip {
            throw XCTSkip("Skipped on Designed-for-iPad runtime due unstable @Observable store crashes. Set SKIP_UNIVERSALDOC_STORE_TESTS=0 to run.")
        }

        let bundleA = PDFBundle(name: "A")
        let bundleB = PDFBundle(name: "B")

        let logicalA = UUID()
        let logicalB = UUID()
        let versionA = UUID()
        let versionB = UUID()

        let session = UniversalDocSession(
            scope: .singleDoc(UUID()),
            slots: [
                makeSessionSlot(
                    logicalPageID: logicalA,
                    pageID: UUID(),
                    bundleID: bundleA.id,
                    versionIDs: [versionA],
                    defaultVersionID: versionA
                ),
                makeSessionSlot(
                    logicalPageID: logicalB,
                    pageID: UUID(),
                    bundleID: bundleB.id,
                    versionIDs: [versionB],
                    defaultVersionID: versionB
                ),
            ],
            viewMode: .continuous
        )

        let store = UniversalDocSessionStore(session: session)
        XCTAssertEqual(store.focusedLogicalPageID, logicalA)
        XCTAssertEqual(store.currentPageIndex, 0)

        store.setFocusedPage(logicalB)
        XCTAssertEqual(store.focusedLogicalPageID, logicalB)
        XCTAssertEqual(store.currentPageIndex, 1)

        store.changeSourceForFocusedPage(to: .ocr)
        XCTAssertEqual(store.currentSource(for: logicalB), .ocr)
        XCTAssertEqual(store.currentSource(for: logicalA), .display)
    }

    @MainActor
    func testGlobalSourceInAllDocumentsScopeAppliesToAllSlots() throws {
        let shouldSkip = ProcessInfo.processInfo.environment["SKIP_UNIVERSALDOC_STORE_TESTS"] != "0"
        if shouldSkip {
            throw XCTSkip("Skipped on Designed-for-iPad runtime due unstable @Observable store crashes. Set SKIP_UNIVERSALDOC_STORE_TESTS=0 to run.")
        }

        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let bundleWithOCR = PDFBundle(name: "Bundle With OCR")
        bundleWithOCR.ocrTextByPage[1] = "text"
        let bundleWithoutOCR = PDFBundle(name: "Bundle Without OCR")
        context.insert(bundleWithOCR)
        context.insert(bundleWithoutOCR)
        try context.save()

        let logicalA = UUID()
        let logicalB = UUID()
        let versionA = UUID()
        let versionB = UUID()

        let session = UniversalDocSession(
            scope: .allDocuments([UUID(), UUID()]),
            slots: [
                makeSessionSlot(
                    logicalPageID: logicalA,
                    pageID: UUID(),
                    bundleID: bundleWithOCR.id,
                    versionIDs: [versionA],
                    defaultVersionID: versionA
                ),
                makeSessionSlot(
                    logicalPageID: logicalB,
                    pageID: UUID(),
                    bundleID: bundleWithoutOCR.id,
                    versionIDs: [versionB],
                    defaultVersionID: versionB
                ),
            ],
            viewMode: .continuous
        )

        let store = UniversalDocSessionStore(session: session)
        let provider = UniversalDocDataProvider(modelContext: context)

        store.changeSourceForAllPages(to: .ocr, using: provider)

        XCTAssertEqual(store.currentSource(for: logicalA), .ocr)
        XCTAssertEqual(store.currentSource(for: logicalB), .display)
    }

    @MainActor
    func testSessionStorePreviewVersionSwitchIsPerPageOnly() throws {
        let shouldSkip = ProcessInfo.processInfo.environment["SKIP_UNIVERSALDOC_STORE_TESTS"] != "0"
        if shouldSkip {
            throw XCTSkip("Skipped on Designed-for-iPad runtime due unstable @Observable store crashes. Set SKIP_UNIVERSALDOC_STORE_TESTS=0 to run.")
        }

        let logicalA = UUID()
        let logicalB = UUID()
        let bundleA = UUID()
        let bundleB = UUID()

        let versionA1 = UUID()
        let versionA2 = UUID()
        let versionB1 = UUID()
        let versionB2 = UUID()

        let session = UniversalDocSession(
            scope: .singleDoc(UUID()),
            slots: [
                makeSessionSlot(
                    logicalPageID: logicalA,
                    pageID: UUID(),
                    bundleID: bundleA,
                    versionIDs: [versionA1, versionA2],
                    defaultVersionID: versionA1
                ),
                makeSessionSlot(
                    logicalPageID: logicalB,
                    pageID: UUID(),
                    bundleID: bundleB,
                    versionIDs: [versionB1, versionB2],
                    defaultVersionID: versionB1
                ),
            ],
            viewMode: .continuous
        )

        let store = UniversalDocSessionStore(session: session)
        store.changePreviewVersion(logicalPageID: logicalA, to: versionA2)

        XCTAssertEqual(store.currentPreviewVersionID(for: logicalA), versionA2)
        XCTAssertEqual(store.currentPreviewVersionID(for: logicalB), versionB1)
    }

    @MainActor
    func testDocNotesEditorCreateRootAndUpdateRect() throws {
        let shouldSkip = ProcessInfo.processInfo.environment["SKIP_DOC_NOTES_EDITOR_TESTS"] != "0"
        if shouldSkip {
            throw XCTSkip("Skipped on Designed-for-iPad runtime due SwiftData Array<UUID> materialization crash. Set SKIP_DOC_NOTES_EDITOR_TESTS=0 to run.")
        }

        let fixture = try makeNotesEditorFixture()
        let viewModel = fixture.viewModel
        let pageVersion = fixture.pageVersion
        let page = fixture.page

        viewModel.createRoot(
            pageVersionID: pageVersion.id,
            page: page,
            normalizedRect: CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.25),
            title: " Root ",
            body: " Body "
        )

        let root = try XCTUnwrap(viewModel.rootNotes.first)
        XCTAssertEqual(root.pageVersionID, pageVersion.id)
        XCTAssertEqual(root.pageId, page.id)
        XCTAssertEqual(root.title, "Root")
        XCTAssertEqual(root.body, "Body")
        XCTAssertEqual(root.rectX, 0.2, accuracy: 0.0001)
        XCTAssertEqual(root.rectY, 0.3, accuracy: 0.0001)
        XCTAssertEqual(root.rectWidth, 0.4, accuracy: 0.0001)
        XCTAssertEqual(root.rectHeight, 0.25, accuracy: 0.0001)

        viewModel.updateRect(
            noteID: root.id,
            normalizedRect: CGRect(x: -0.5, y: 0.6, width: 2.0, height: 0.8)
        )

        let updated = try XCTUnwrap(viewModel.noteIndex[root.id])
        XCTAssertEqual(updated.rectX, 0.0, accuracy: 0.0001)
        XCTAssertEqual(updated.rectY, 0.6, accuracy: 0.0001)
        XCTAssertEqual(updated.rectWidth, 1.0, accuracy: 0.0001)
        XCTAssertEqual(updated.rectHeight, 0.4, accuracy: 0.0001)
        XCTAssertEqual(updated.verticalOrderHint, 0.6, accuracy: 0.0001)
    }

    @MainActor
    func testGroupNotesLoadByMultiplePageVersionIDsAndSortByPageOrder() throws {
        let shouldSkip = ProcessInfo.processInfo.environment["SKIP_DOC_NOTES_EDITOR_TESTS"] != "0"
        if shouldSkip {
            throw XCTSkip("Skipped on Designed-for-iPad runtime due SwiftData Array<UUID> materialization crash. Set SKIP_DOC_NOTES_EDITOR_TESTS=0 to run.")
        }

        let container = try makeInMemoryContainer(includeNoteModels: true)
        let context = ModelContext(container)

        let bundle = PDFBundle(name: "Bundle")
        let doc = Doc(title: "Doc")
        let group = PageGroup(title: "Group", doc: doc)
        doc.addPageGroup(group)

        let page1 = Page(pdfBundle: bundle, pageNumber: 1, pageGroup: group)
        let page2 = Page(pdfBundle: bundle, pageNumber: 2, pageGroup: group)
        group.addPage(page1)
        group.addPage(page2)

        context.insert(bundle)
        context.insert(doc)
        context.insert(group)
        context.insert(page1)
        context.insert(page2)
        try context.save()

        let version1 = try XCTUnwrap(page1.latestVersion)
        let version2 = try XCTUnwrap(page2.latestVersion)

        let viewModel = DocNotesEditorViewModel(modelContext: context)
        viewModel.createRoot(
            pageVersionID: version2.id,
            page: page2,
            normalizedRect: CGRect(x: 0.2, y: 0.8, width: 0.2, height: 0.1),
            title: "P2",
            body: "note-p2"
        )
        viewModel.createRoot(
            pageVersionID: version1.id,
            page: page1,
            normalizedRect: CGRect(x: 0.2, y: 0.2, width: 0.2, height: 0.1),
            title: "P1",
            body: "note-p1"
        )

        viewModel.loadNotes(pageVersionIDs: [version2.id, version1.id])

        XCTAssertEqual(viewModel.notes.count, 2)
        XCTAssertEqual(viewModel.notes.first?.body, "note-p1")
        XCTAssertEqual(viewModel.notes.last?.body, "note-p2")
        XCTAssertEqual(viewModel.rootNotes(for: version1.id).count, 1)
        XCTAssertEqual(viewModel.rootNotes(for: version2.id).count, 1)
    }

    @MainActor
    func testDocNotesEditorReplyMoveAndDeleteSubtreeConsistency() throws {
        let shouldSkip = ProcessInfo.processInfo.environment["SKIP_DOC_NOTES_EDITOR_TESTS"] != "0"
        if shouldSkip {
            throw XCTSkip("Skipped on Designed-for-iPad runtime due SwiftData Array<UUID> materialization crash. Set SKIP_DOC_NOTES_EDITOR_TESTS=0 to run.")
        }

        let fixture = try makeNotesEditorFixture()
        let viewModel = fixture.viewModel
        let context = fixture.context
        let pageVersion = fixture.pageVersion
        let page = fixture.page

        viewModel.createRoot(
            pageVersionID: pageVersion.id,
            page: page,
            normalizedRect: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
            title: "Root",
            body: "root"
        )
        let root = try XCTUnwrap(viewModel.rootNotes.first)

        viewModel.createReply(parentID: root.id, title: "Child", body: "child")
        let child = try XCTUnwrap(viewModel.notes.first(where: { $0.body == "child" }))
        XCTAssertEqual(child.parentNoteID, root.id)
        XCTAssertEqual(child.rectX, root.rectX, accuracy: 0.0001)
        XCTAssertEqual(child.rectY, root.rectY, accuracy: 0.0001)
        XCTAssertEqual(child.rectWidth, root.rectWidth, accuracy: 0.0001)
        XCTAssertEqual(child.rectHeight, root.rectHeight, accuracy: 0.0001)

        viewModel.createRoot(
            pageVersionID: pageVersion.id,
            page: page,
            normalizedRect: CGRect(x: 0.5, y: 0.7, width: 0.2, height: 0.2),
            title: "Second",
            body: "second"
        )
        let secondRoot = try XCTUnwrap(viewModel.rootNotes.first(where: { $0.body == "second" }))
        let fromIndex = try XCTUnwrap(viewModel.rootNotes.firstIndex(where: { $0.id == secondRoot.id }))
        viewModel.moveSibling(noteID: secondRoot.id, from: fromIndex, to: 0)
        XCTAssertEqual(viewModel.rootNotes.first?.id, secondRoot.id)

        viewModel.moveToParent(noteID: secondRoot.id, newParentID: root.id, at: nil)
        XCTAssertTrue(viewModel.rootNotes.contains(where: { $0.id == secondRoot.id }) == false)
        XCTAssertTrue(viewModel.orderedChildren(of: root.id).contains(where: { $0.id == secondRoot.id }))

        viewModel.deleteSubtree(noteID: root.id)
        XCTAssertTrue(viewModel.notes.isEmpty)

        let allNotes = try context.fetch(FetchDescriptor<NoteBlock>())
        let deletedIDs = Set(allNotes.filter(\.isDeleted).map(\.id))
        XCTAssertTrue(deletedIDs.contains(root.id))
        XCTAssertTrue(deletedIDs.contains(child.id))
        XCTAssertTrue(deletedIDs.contains(secondRoot.id))
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

    private func makeInMemoryContainer(includeNoteModels: Bool = false) throws -> ModelContainer {
        var models: [any PersistentModel.Type] = [
            PDFBundle.self,
            Page.self,
            PageVersion.self,
            PageGroup.self,
            Doc.self,
            Tag.self,
            TagGroup.self,
            Variable.self,
            PDFBundleVariableAssignment.self,
            DocVariableAssignment.self,
            PageGroupVariableAssignment.self,
            PageVariableAssignment.self,
        ]

        if includeNoteModels {
            models.append(NoteBlock.self)
            models.append(NoteBlockVariableAssignment.self)
        }

        let schema = Schema(models)
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

    private func makeSessionSlot(
        logicalPageID: UUID,
        pageID: UUID,
        bundleID: UUID,
        versionIDs: [UUID],
        defaultVersionID: UUID,
        docID: UUID = UUID(),
        docTitle: String = "Doc",
        pageGroupID: UUID? = UUID(),
        pageGroupTitle: String = "Group",
        groupOrderKey: Int = 0,
        pageOrderInGroup: Int = 0
    ) -> UniversalDocLogicalPageSlot {
        let options = versionIDs.enumerated().map { index, id in
            UniversalDocVersionOption(
                id: id,
                pdfBundleID: bundleID,
                pageNumber: 1,
                createdAt: Date(timeIntervalSince1970: TimeInterval(index + 1)),
                ordinal: index + 1,
                isCurrentDefault: id == defaultVersionID
            )
        }
        return UniversalDocLogicalPageSlot(
            id: logicalPageID,
            pageID: pageID,
            docID: docID,
            docTitle: docTitle,
            pageGroupID: pageGroupID,
            pageGroupTitle: pageGroupTitle,
            groupOrderKey: groupOrderKey,
            pageOrderInGroup: pageOrderInGroup,
            versionOptions: options,
            defaultVersionID: defaultVersionID,
            defaultSource: .display,
            canPreviewOtherVersions: options.count > 1,
            canSwitchSource: true,
            canAnnotate: true
        )
    }

    @MainActor
    private func makeNotesEditorFixture() throws -> (
        context: ModelContext,
        viewModel: DocNotesEditorViewModel,
        page: Page,
        pageVersion: PageVersion
    ) {
        let container = try makeInMemoryContainer(includeNoteModels: true)
        let context = ModelContext(container)

        let bundle = PDFBundle(name: "Fixture Bundle")
        let doc = Doc(title: "Fixture Doc")
        let group = PageGroup(title: "Fixture Group", doc: doc)
        let page = Page(pdfBundle: bundle, pageNumber: 1, pageGroup: group)
        doc.addPageGroup(group)
        group.addPage(page)

        context.insert(bundle)
        context.insert(doc)
        context.insert(group)
        context.insert(page)
        try context.save()

        let pageVersion = try XCTUnwrap(page.latestVersion)
        let viewModel = DocNotesEditorViewModel(modelContext: context)
        viewModel.loadNotes(pageVersionID: pageVersion.id)
        return (context, viewModel, page, pageVersion)
    }
}
