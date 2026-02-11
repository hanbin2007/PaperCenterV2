//
//  DocViewerScreen.swift
//  PaperCenterV2
//
//  Entry screen that builds and hosts a UniversalDoc Viewer session.
//

import SwiftUI
import SwiftData

struct DocViewerScreen: View {
    @Environment(\.modelContext) private var modelContext

    let doc: Doc

    @State private var sessionStore: UniversalDocSessionStore?
    @State private var dataProvider: UniversalDocDataProvider?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let sessionStore, let dataProvider {
                UniversalDocViewer(
                    store: sessionStore,
                    dataProvider: dataProvider
                ) { logicalPageID, createdVersionID in
                    rebuildSession(
                        focusLogicalPageID: logicalPageID,
                        preferredVersionID: createdVersionID
                    )
                }
            } else if let errorMessage {
                ContentUnavailableView(
                    "Viewer Unavailable",
                    systemImage: "xmark.octagon",
                    description: Text(errorMessage)
                )
            } else {
                ProgressView("Preparing Viewer…")
            }
        }
        .navigationTitle(doc.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: doc.id) {
            if sessionStore == nil {
                rebuildSession(focusLogicalPageID: nil, preferredVersionID: nil)
            }
        }
    }

    private func rebuildSession(
        focusLogicalPageID: UUID?,
        preferredVersionID: UUID?
    ) {
        let previous = sessionStore
        let previousSnapshots = previous?.selectionSnapshots()
        let previousLogicalPageID = previousSnapshots.flatMap { snapshots in
            previous?.logicalPageID(at: snapshots.pageIndex)
        }

        let builder = UniversalDocSessionBuilder(modelContext: modelContext)
        let session = builder.buildSession(for: doc)

        let newStore = UniversalDocSessionStore(session: session)
        if let previousSnapshots {
            newStore.applySelectionSnapshots(
                preview: previousSnapshots.preview,
                source: previousSnapshots.source,
                fallbackLogicalPageID: focusLogicalPageID ?? previousLogicalPageID
            )
        } else if let focusLogicalPageID,
                  let index = session.slots.firstIndex(where: { $0.id == focusLogicalPageID }) {
            newStore.navigate(to: index)
        }

        if let focusLogicalPageID, let preferredVersionID {
            newStore.changePreviewVersion(
                logicalPageID: focusLogicalPageID,
                to: preferredVersionID
            )
        }

        sessionStore = newStore
        dataProvider = UniversalDocDataProvider(modelContext: modelContext)
        errorMessage = nil
    }
}
