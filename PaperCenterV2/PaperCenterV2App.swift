//
//  PaperCenterV2App.swift
//  PaperCenterV2
//
//  Created by zhb on 2025/11/9.
//

import SwiftUI
import SwiftData
import Foundation
import CoreGraphics

@main
struct PaperCenterV2App: App {
    private static let appSchema = Schema([
        // Core models
        PDFBundle.self,
        Page.self,
        PageVersion.self,
        PageGroup.self,
        Doc.self,
        NoteBlock.self,
        // Metadata models
        Tag.self,
        TagGroup.self,
        Variable.self,
        // Variable assignments
        PDFBundleVariableAssignment.self,
        DocVariableAssignment.self,
        PageGroupVariableAssignment.self,
        PageVariableAssignment.self,
        NoteBlockVariableAssignment.self,
    ])

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private static var shouldSeedGlobalSearchUITestData: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTestSeedGlobalSearch")
    }

    var sharedModelContainer: ModelContainer = {
        if Self.isRunningTests {
            let testConfiguration = ModelConfiguration(
                schema: Self.appSchema,
                isStoredInMemoryOnly: true
            )
            do {
                let container = try ModelContainer(for: Self.appSchema, configurations: [testConfiguration])
                if Self.shouldSeedGlobalSearchUITestData {
                    try? Self.seedGlobalSearchUITestDataIfNeeded(in: container.mainContext)
                }
                return container
            } catch {
                fatalError("Could not create in-memory test ModelContainer: \(error)")
            }
        }

        let storeURL = Self.defaultStoreURL()
        let modelConfiguration = ModelConfiguration(
            schema: Self.appSchema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(for: Self.appSchema, configurations: [modelConfiguration])
        } catch {
            // If migration fails (schema drift during local development), clear stale store and retry once.
            do {
                try Self.removePersistentStoreFiles(at: storeURL)
                return try ModelContainer(for: Self.appSchema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
        .modelContainer(sharedModelContainer)
    }

    private static func defaultStoreURL() -> URL {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        if !FileManager.default.fileExists(atPath: applicationSupportURL.path) {
            try? FileManager.default.createDirectory(
                at: applicationSupportURL,
                withIntermediateDirectories: true
            )
        }
        return applicationSupportURL.appendingPathComponent("default.store")
    }

    private static func removePersistentStoreFiles(at storeURL: URL) throws {
        let fileManager = FileManager.default
        let sidecarURLs = [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-shm"),
            URL(fileURLWithPath: storeURL.path + "-wal"),
        ]

        for url in sidecarURLs where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    @MainActor
    private static func seedGlobalSearchUITestDataIfNeeded(in context: ModelContext) throws {
        let existingCount = try context.fetchCount(FetchDescriptor<Doc>())
        guard existingCount == 0 else { return }

        let bundle = PDFBundle(
            id: fixedUUID("10000000-0000-0000-0000-000000000001"),
            name: "UITest Bundle"
        )
        bundle.ocrTextByPage = [1: "alpha ocr fixture content"]

        let doc = Doc(
            id: fixedUUID("20000000-0000-0000-0000-000000000001"),
            title: "UITest Doc"
        )
        let group = PageGroup(
            id: fixedUUID("30000000-0000-0000-0000-000000000001"),
            title: "UITest Group",
            doc: doc
        )
        doc.addPageGroup(group)

        let page = Page(
            id: fixedUUID("40000000-0000-0000-0000-000000000001"),
            pdfBundle: bundle,
            pageNumber: 1,
            pageGroup: group
        )
        group.addPage(page)

        let alphaTag = Tag(
            id: fixedUUID("50000000-0000-0000-0000-000000000001"),
            name: "AlphaTag",
            color: "#22C55E",
            scope: .all,
            sortIndex: 0
        )
        let betaTag = Tag(
            id: fixedUUID("60000000-0000-0000-0000-000000000001"),
            name: "BetaTag",
            color: "#3B82F6",
            scope: .all,
            sortIndex: 1
        )
        page.tags = [alphaTag, betaTag]

        let scoreVariable = Variable(
            id: fixedUUID("70000000-0000-0000-0000-000000000001"),
            name: "Score",
            type: .int,
            scope: .all,
            sortIndex: 0
        )
        let pageScoreAssignment = PageVariableAssignment(
            variable: scoreVariable,
            page: page,
            intValue: 0
        )
        page.variableAssignments = [pageScoreAssignment]

        var seededNote: NoteBlock?
        var seededNoteAssignment: NoteBlockVariableAssignment?
        if let version = page.latestVersion {
            let snapshot = MetadataSnapshot(
                tagIDs: [betaTag.id],
                variableAssignments: [
                    VariableAssignmentSnapshot(
                        variableID: scoreVariable.id,
                        intValue: 5,
                        listValue: nil,
                        textValue: nil,
                        dateValue: nil
                    ),
                ]
            )
            version.metadataSnapshot = try? PageVersion.encodeMetadataSnapshot(snapshot)

            let note = NoteBlock.createNormalized(
                pageVersion: version,
                absoluteRect: CGRect(x: 10, y: 10, width: 80, height: 30),
                pageSize: CGSize(width: 200, height: 300),
                title: "UITest Note",
                body: "alpha note fixture"
            )
            note.tags = [alphaTag]

            let noteScoreAssignment = NoteBlockVariableAssignment(
                variable: scoreVariable,
                noteBlock: note,
                intValue: 0
            )
            note.variableAssignments = [noteScoreAssignment]
            seededNote = note
            seededNoteAssignment = noteScoreAssignment
        }

        context.insert(bundle)
        context.insert(doc)
        context.insert(group)
        context.insert(page)
        context.insert(alphaTag)
        context.insert(betaTag)
        context.insert(scoreVariable)
        context.insert(pageScoreAssignment)
        if let seededNote {
            context.insert(seededNote)
        }
        if let seededNoteAssignment {
            context.insert(seededNoteAssignment)
        }

        try context.save()
    }

    private static func fixedUUID(_ raw: String) -> UUID {
        guard let value = UUID(uuidString: raw) else {
            preconditionFailure("Invalid fixed UUID: \(raw)")
        }
        return value
    }
}
