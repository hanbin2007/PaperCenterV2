//
//  PaperCenterV2App.swift
//  PaperCenterV2
//
//  Created by zhb on 2025/11/9.
//

import SwiftUI
import SwiftData
import Foundation

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

    var sharedModelContainer: ModelContainer = {
        if Self.isRunningTests {
            let testConfiguration = ModelConfiguration(
                schema: Self.appSchema,
                isStoredInMemoryOnly: true
            )
            do {
                return try ModelContainer(for: Self.appSchema, configurations: [testConfiguration])
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
}
