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
    @State private var showingStructureEditor = false
    @State private var readingGroupID: UUID?

    private var readingScopeTitle: String {
        if let readingGroupID,
           let group = doc.orderedPageGroups.first(where: { $0.id == readingGroupID }) {
            return group.title
        }
        return "Whole Doc"
    }

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
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button {
                        readingGroupID = nil
                    } label: {
                        if readingGroupID == nil {
                            Label("Whole Document", systemImage: "checkmark")
                        } else {
                            Text("Whole Document")
                        }
                    }

                    if !doc.orderedPageGroups.isEmpty {
                        Divider()
                    }

                    ForEach(doc.orderedPageGroups) { group in
                        Button {
                            readingGroupID = group.id
                        } label: {
                            if readingGroupID == group.id {
                                Label(group.title, systemImage: "checkmark")
                            } else {
                                Text(group.title)
                            }
                        }
                    }
                } label: {
                    Label(readingScopeTitle, systemImage: "square.stack.3d.down.forward")
                        .lineLimit(1)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingStructureEditor = true
                } label: {
                    Image(systemName: "list.bullet.indent")
                }
                .accessibilityLabel("Edit Structure")
            }
        }
        .sheet(isPresented: $showingStructureEditor, onDismiss: {
            if let readingGroupID,
               doc.orderedPageGroups.contains(where: { $0.id == readingGroupID }) == false {
                self.readingGroupID = nil
            }
            rebuildSession(focusLogicalPageID: nil, preferredVersionID: nil)
        }) {
            DocStructureEditorView(doc: doc)
        }
        .task(id: doc.id) {
            if sessionStore == nil {
                rebuildSession(focusLogicalPageID: nil, preferredVersionID: nil)
            }
        }
        .onChange(of: readingGroupID) { _, _ in
            rebuildSession(focusLogicalPageID: nil, preferredVersionID: nil)
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
        let session = builder.buildSession(for: doc, pageGroupID: readingGroupID)

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
