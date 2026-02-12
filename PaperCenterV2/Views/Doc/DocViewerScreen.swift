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
    let launchContext: DocViewerLaunchContext?

    @State private var sessionStore: UniversalDocSessionStore?
    @State private var dataProvider: UniversalDocDataProvider?
    @State private var errorMessage: String?
    @State private var showingStructureEditor = false
    @State private var readingGroupID: UUID?
    @State private var pendingLaunchContext: DocViewerLaunchContext?
    @State private var initialSelectedNoteID: UUID?

    init(doc: Doc, launchContext: DocViewerLaunchContext? = nil) {
        self.doc = doc
        self.launchContext = launchContext
        _pendingLaunchContext = State(initialValue: launchContext)
        _initialSelectedNoteID = State(initialValue: launchContext?.preferredNoteID)
    }

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
                    dataProvider: dataProvider,
                    initialSelectedNoteID: initialSelectedNoteID
                ) { logicalPageID, createdVersionID in
                    rebuildSession(
                        focusLogicalPageID: logicalPageID,
                        preferredDocPageNumber: nil,
                        preferredVersionID: createdVersionID,
                        preferredSource: nil
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
            rebuildSession(
                focusLogicalPageID: nil,
                preferredDocPageNumber: nil,
                preferredVersionID: nil,
                preferredSource: nil
            )
        }) {
            DocStructureEditorView(doc: doc)
        }
        .task(id: doc.id) {
            if sessionStore == nil {
                let launch = pendingLaunchContext
                rebuildSession(
                    focusLogicalPageID: launch?.logicalPageID,
                    preferredDocPageNumber: launch?.preferredDocPageNumber,
                    preferredVersionID: launch?.preferredVersionID,
                    preferredSource: launch?.preferredSource
                )
                pendingLaunchContext = nil
            }
        }
        .onChange(of: readingGroupID) { _, _ in
            rebuildSession(
                focusLogicalPageID: nil,
                preferredDocPageNumber: nil,
                preferredVersionID: nil,
                preferredSource: nil
            )
        }
    }

    private func rebuildSession(
        focusLogicalPageID: UUID?,
        preferredDocPageNumber: Int?,
        preferredVersionID: UUID?,
        preferredSource: UniversalDocViewerSource?
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
        } else if let navigationIndex = resolvedNavigationIndex(
            in: session,
            logicalPageID: focusLogicalPageID,
            preferredDocPageNumber: preferredDocPageNumber
        ) {
            newStore.navigate(to: navigationIndex)
        }

        if focusLogicalPageID == nil,
           let preferredDocPageNumber,
           let pageIndex = pageIndex(for: preferredDocPageNumber, in: session) {
            newStore.navigate(to: pageIndex)
        }

        if let focusLogicalPageID, let preferredVersionID {
            newStore.changePreviewVersion(
                logicalPageID: focusLogicalPageID,
                to: preferredVersionID
            )
        }
        if let focusLogicalPageID, let preferredSource {
            newStore.changeSource(logicalPageID: focusLogicalPageID, to: preferredSource)
        }

        sessionStore = newStore
        dataProvider = UniversalDocDataProvider(modelContext: modelContext)
        errorMessage = nil
    }

    private func resolvedNavigationIndex(
        in session: UniversalDocSession,
        logicalPageID: UUID?,
        preferredDocPageNumber: Int?
    ) -> Int? {
        if let logicalPageID,
           let index = session.slots.firstIndex(where: { $0.id == logicalPageID }) {
            return index
        }
        if let preferredDocPageNumber {
            return pageIndex(for: preferredDocPageNumber, in: session)
        }
        return nil
    }

    private func pageIndex(for docPageNumber: Int, in session: UniversalDocSession) -> Int? {
        guard !session.slots.isEmpty else { return nil }
        let clamped = min(max(docPageNumber, 1), session.slots.count)
        return clamped - 1
    }
}
