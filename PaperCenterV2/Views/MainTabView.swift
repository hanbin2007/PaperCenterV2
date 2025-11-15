//
//  MainTabView.swift
//  PaperCenterV2
//
//  Created by Claude on 2025-11-09.
//

import SwiftUI

/// Main tab view for the app
struct MainTabView: View {
    var body: some View {
        TabView {
            DocListView()
                .tabItem {
                    Label("Documents", systemImage: "doc.text")
                }

            PDFBundleListView()
                .tabItem {
                    Label("Bundles", systemImage: "folder")
                }

            OCRDebugView()
                .tabItem {
                    Label("OCR Debug", systemImage: "text.magnifyingglass")
                }
        }
    }
}
