//
//  PaperCenterV2App.swift
//  PaperCenterV2
//
//  Created by zhb on 2025/11/9.
//

import SwiftUI
import SwiftData

@main
struct PaperCenterV2App: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            // Core models
            PDFBundle.self,
            Page.self,
            PageVersion.self,
            PageGroup.self,
            Doc.self,
            // Metadata models
            Tag.self,
            TagGroup.self,
            Variable.self,
            // Variable assignments
            PDFBundleVariableAssignment.self,
            DocVariableAssignment.self,
            PageGroupVariableAssignment.self,
            PageVariableAssignment.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            PlaceholderView()
        }
        .modelContainer(sharedModelContainer)
    }
}
