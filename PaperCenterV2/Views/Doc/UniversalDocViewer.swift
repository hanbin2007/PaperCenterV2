//
//  UniversalDocViewer.swift
//  PaperCenterV2
//
//  Reusable UniversalDoc viewer with continuous PDF scrolling and note anchors.
//

import PDFKit
import SwiftData
import SwiftUI

private enum SourceApplyScope: String, CaseIterable, Identifiable {
    case focused
    case global

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focused:
            return "Current"
        case .global:
            return "Global"
        }
    }
}

private enum NoteInteractionMode: String, CaseIterable, Identifiable {
    case view
    case edit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .view:
            return "View"
        case .edit:
            return "Edit"
        }
    }

    var iconName: String {
        switch self {
        case .view:
            return "eye"
        case .edit:
            return "pencil"
        }
    }
}

private struct ViewerLogicalEntry: Identifiable {
    let id: UUID
    let logicalIndex: Int
    let slot: UniversalDocLogicalPageSlot
    let page: Page?
    let selectedVersion: UniversalDocVersionOption
    let selectedSource: UniversalDocViewerSource
    let renderData: UniversalDocRenderablePage?
}

private struct ViewerGroupEntry: Identifiable {
    let id: String
    let docID: UUID
    let docTitle: String
    let pageGroupID: UUID?
    let pageGroupTitle: String
    let groupOrderKey: Int
    let entries: [ViewerLogicalEntry]

    var firstLogicalPageID: UUID? {
        entries.first?.id
    }
}

struct UniversalDocViewer: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Bindable var store: UniversalDocSessionStore
    let dataProvider: UniversalDocDataProvider
    let initialSelectedNoteID: UUID?
    let onPageVersionCreated: (_ logicalPageID: UUID, _ pageVersionID: UUID) -> Void

    init(
        store: UniversalDocSessionStore,
        dataProvider: UniversalDocDataProvider,
        initialSelectedNoteID: UUID? = nil,
        onPageVersionCreated: @escaping (_ logicalPageID: UUID, _ pageVersionID: UUID) -> Void
    ) {
        self._store = Bindable(store)
        self.dataProvider = dataProvider
        self.initialSelectedNoteID = initialSelectedNoteID
        self.onPageVersionCreated = onPageVersionCreated
        _pendingInitialNoteID = State(initialValue: initialSelectedNoteID)
    }

    @State private var sourceApplyScope: SourceApplyScope = .focused
    @State private var showingCreateVersionSheet = false
    @State private var showingGroupJumpSheet = false

    @State private var pendingJumpComposedIndex: Int?
    @State private var jumpRequestID = 0
    @State private var isNoteCreateMode = false
    @State private var notesDrawerExpanded = true
    @State private var notesPanelCollapsed = false
    @State private var showsInlineNoteBubbles = true
    @State private var noteInteractionMode: NoteInteractionMode = .view
    @State private var loadedNotesSignature = ""
    @State private var pendingInitialNoteID: UUID?

    @State private var notesViewModel: DocNotesEditorViewModel?

    private var logicalEntries: [ViewerLogicalEntry] {
        Array(store.session.slots.enumerated()).compactMap { index, slot in
            let selectedVersionID = store.currentPreviewVersionID(for: slot.id) ?? slot.defaultVersionID
            guard let selectedVersion = slot.versionOptions.first(where: { $0.id == selectedVersionID }) else {
                return nil
            }
            let requestedSource = store.currentSource(for: slot.id) ?? slot.defaultSource
            let renderData = dataProvider.resolve(
                slot: slot,
                selectedVersionID: selectedVersion.id,
                selectedSource: requestedSource
            )
            let effectiveSource = renderData?.source ?? requestedSource

            return ViewerLogicalEntry(
                id: slot.id,
                logicalIndex: index,
                slot: slot,
                page: dataProvider.page(for: slot.pageID),
                selectedVersion: selectedVersion,
                selectedSource: effectiveSource,
                renderData: renderData
            )
        }
    }

    private var focusedEntry: ViewerLogicalEntry? {
        if let focusedID = store.focusedLogicalPageID,
           let matched = logicalEntries.first(where: { $0.id == focusedID }) {
            return matched
        }

        guard store.currentPageIndex >= 0,
              store.currentPageIndex < logicalEntries.count else {
            return logicalEntries.first
        }
        return logicalEntries[store.currentPageIndex]
    }

    private var groupEntries: [ViewerGroupEntry] {
        let grouped = Dictionary(grouping: logicalEntries) { entry in
            let groupToken = entry.slot.pageGroupID?.uuidString ?? "ungrouped"
            return "\(entry.slot.docID.uuidString)|\(groupToken)"
        }

        return grouped.compactMap { key, values in
            guard let first = values.first else { return nil }
            let orderedValues = values.sorted { lhs, rhs in
                if lhs.slot.pageOrderInGroup == rhs.slot.pageOrderInGroup {
                    return lhs.logicalIndex < rhs.logicalIndex
                }
                return lhs.slot.pageOrderInGroup < rhs.slot.pageOrderInGroup
            }

            return ViewerGroupEntry(
                id: key,
                docID: first.slot.docID,
                docTitle: first.slot.docTitle,
                pageGroupID: first.slot.pageGroupID,
                pageGroupTitle: first.slot.pageGroupTitle,
                groupOrderKey: first.slot.groupOrderKey,
                entries: orderedValues
            )
        }
        .sorted { lhs, rhs in
            if lhs.groupOrderKey == rhs.groupOrderKey {
                return lhs.id < rhs.id
            }
            return lhs.groupOrderKey < rhs.groupOrderKey
        }
    }

    private var focusedGroupEntry: ViewerGroupEntry? {
        guard let focusedEntry else { return groupEntries.first }
        return groupEntries.first(where: { group in
            group.entries.contains(where: { $0.id == focusedEntry.id })
        }) ?? groupEntries.first
    }

    private var groupCount: Int {
        groupEntries.count
    }

    private var currentGroupNumber: Int {
        guard let focusedGroupEntry,
              let index = groupEntries.firstIndex(where: { $0.id == focusedGroupEntry.id }) else {
            return 1
        }
        return index + 1
    }

    private var pageCount: Int {
        logicalEntries.count
    }

    private var currentPageNumber: Int {
        (focusedEntry?.logicalIndex ?? 0) + 1
    }

    private var isOCRMode: Bool {
        focusedEntry?.selectedSource == .ocr
    }

    private var focusedPageGroupName: String {
        guard let focusedGroupEntry else { return "" }
        return "\(focusedGroupEntry.docTitle) · \(focusedGroupEntry.pageGroupTitle)"
    }

    private var logicalEntryByID: [UUID: ViewerLogicalEntry] {
        Dictionary(uniqueKeysWithValues: logicalEntries.map { ($0.id, $0) })
    }

    private var composedPDFEntries: [ComposedPDFPageEntry] {
        var composed: [ComposedPDFPageEntry] = []

        for entry in logicalEntries {
            guard let pdfRender = resolvedPDFRenderData(for: entry) else { continue }

            composed.append(
                ComposedPDFPageEntry(
                    id: entry.id,
                    logicalPageID: entry.id,
                    pageID: entry.slot.pageID,
                    pageVersionID: entry.selectedVersion.id,
                    pageNumberInDoc: entry.logicalIndex + 1,
                    fileURL: pdfRender.fileURL,
                    sourcePageNumber: pdfRender.pageNumber
                )
            )
        }

        return composed
    }

    private var composedIndexByLogicalPageID: [UUID: Int] {
        Dictionary(uniqueKeysWithValues: composedPDFEntries.enumerated().map { ($1.logicalPageID, $0) })
    }

    private var focusedComposedIndex: Int? {
        guard let focusedEntry else { return nil }
        return composedIndexByLogicalPageID[focusedEntry.id]
    }

    private var composedIndexByPageVersionID: [UUID: Int] {
        Dictionary(uniqueKeysWithValues: composedPDFEntries.enumerated().map { ($1.pageVersionID, $0) })
    }

    private var noteAnchors: [NoteAnchorOverlayItem] {
        guard let notesViewModel,
              !isOCRMode else {
            return []
        }

        return notesViewModel.notes.compactMap { note in
            guard let composedIndex = composedIndexByPageVersionID[note.pageVersionID] else {
                return nil
            }
            return NoteAnchorOverlayItem(
                id: note.id,
                composedPageIndex: composedIndex,
                normalizedRect: CGRect(
                    x: note.rectX,
                    y: note.rectY,
                    width: note.rectWidth,
                    height: note.rectHeight
                ),
                title: note.title,
                body: note.body
            )
        }
    }

    private var pageTagItems: [PageTagOverlayItem] {
        guard !isOCRMode else { return [] }

        return composedPDFEntries.enumerated().compactMap { composedIndex, composedEntry in
            let tags = dataProvider.tags(pageID: composedEntry.pageID)
            guard !tags.isEmpty else { return nil }

            let chips = tags.map { tag in
                PageTagOverlayChip(
                    id: tag.id,
                    name: tag.name,
                    colorHex: tag.color
                )
            }
            let groupTitle = logicalEntryByID[composedEntry.logicalPageID]?.slot.pageGroupTitle ?? ""
            return PageTagOverlayItem(
                composedPageIndex: composedIndex,
                pageGroupTitle: groupTitle,
                chips: chips
            )
        }
    }

    private var selectedNoteID: UUID? {
        notesViewModel?.selectedNoteID
    }

    private var selectedNoteAnchor: NoteAnchorOverlayItem? {
        guard let selectedNoteID else { return nil }
        return noteAnchors.first(where: { $0.id == selectedNoteID })
    }

    private var currentNotesPageVersionIDs: [UUID] {
        guard !isOCRMode, let focusedGroupEntry else { return [] }
        var seen = Set<UUID>()
        var ordered: [UUID] = []
        for entry in focusedGroupEntry.entries {
            let versionID = entry.selectedVersion.id
            if seen.insert(versionID).inserted {
                ordered.append(versionID)
            }
        }
        return ordered
    }

    private var currentNotesPageSectionTitles: [UUID: String] {
        guard let focusedGroupEntry else { return [:] }
        var map: [UUID: String] = [:]
        for entry in focusedGroupEntry.entries {
            map[entry.selectedVersion.id] = "Page \(entry.logicalIndex + 1)"
        }
        return map
    }

    private var canCreateVersion: Bool {
        focusedEntry != nil
    }

    private var canEditNotes: Bool {
        noteInteractionMode == .edit && !isOCRMode
    }

    var body: some View {
        Group {
            if logicalEntries.isEmpty {
                ContentUnavailableView(
                    "No Pages",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("This document has no pages to display.")
                )
            } else {
                contentLayout
            }
        }
        .sheet(isPresented: $showingCreateVersionSheet) {
            if let focusedEntry {
                CreatePageVersionSheet(
                    pageID: focusedEntry.slot.pageID,
                    baseVersionID: focusedEntry.selectedVersion.id
                ) { createdVersionID in
                    onPageVersionCreated(focusedEntry.id, createdVersionID)
                }
            } else {
                ContentUnavailableView("No Focused Page", systemImage: "xmark.octagon")
            }
        }
        .sheet(isPresented: $showingGroupJumpSheet) {
            GroupJumpSheet(
                groups: groupEntries,
                currentGroupID: focusedGroupEntry?.id
            ) { groupID in
                jumpToGroup(groupID: groupID)
            }
        }
        .onAppear {
            if notesViewModel == nil {
                notesViewModel = DocNotesEditorViewModel(modelContext: modelContext)
            }
            ensureFocusSeeded()
            syncNotesForFocusedGroup()
            applyInitialNoteSelectionIfPossible()
            if let focusedComposedIndex, focusedComposedIndex != 0 {
                requestJump(to: focusedComposedIndex)
            }
        }
        .onChange(of: store.focusedLogicalPageID) { _, _ in
            syncNotesForFocusedGroup()
            applyInitialNoteSelectionIfPossible()
            isNoteCreateMode = false
        }
        .onChange(of: noteInteractionMode) { _, newValue in
            if newValue == .view {
                isNoteCreateMode = false
            }
        }
    }

    private var contentLayout: some View {
        VStack(spacing: 0) {
            topControlBar

            if horizontalSizeClass == .regular {
                HStack(spacing: 0) {
                    mainReader

                    if !isOCRMode {
                        Divider()
                        notesPanel
                            .frame(width: notesPanelCollapsed ? 44 : 320)
                            .animation(.easeInOut(duration: 0.2), value: notesPanelCollapsed)
                    }
                }
            } else {
                mainReader
                .safeAreaInset(edge: .bottom) {
                    if !isOCRMode {
                        notesDrawer
                    }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private var topControlBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    navigateGroup(delta: -1)
                } label: {
                    Image(systemName: "chevron.left.circle")
                        .font(.title2)
                }
                .disabled(currentGroupNumber <= 1)

                Button {
                    showingGroupJumpSheet = true
                } label: {
                    Text("Group \(currentGroupNumber) / \(groupCount)")
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(.systemBackground))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    navigateGroup(delta: 1)
                } label: {
                    Image(systemName: "chevron.right.circle")
                        .font(.title2)
                }
                .disabled(currentGroupNumber >= groupCount)

                Spacer()

                Text("Page \(currentPageNumber) / \(pageCount)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer()

                topActionsMenu
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    versionMenu
                    sourceMenu
                    inlineNotesToggle
                    notesModeToggle
                }
                .padding(.vertical, 1)
            }

            Text(focusedPageGroupName)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var topActionsMenu: some View {
        Menu {
            Picker("Apply", selection: $sourceApplyScope) {
                ForEach(SourceApplyScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }

            Divider()

            Button {
                showingCreateVersionSheet = true
            } label: {
                Label("New Version", systemImage: "plus.circle")
            }
            .disabled(!canCreateVersion)

            Button {
                if canEditNotes {
                    isNoteCreateMode.toggle()
                }
            } label: {
                Label(
                    isNoteCreateMode ? "Exit Add Note" : "Add Note",
                    systemImage: isNoteCreateMode ? "xmark.circle" : "pencil.tip.crop.circle.badge.plus"
                )
            }
            .disabled(!canEditNotes)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
        }
    }

    private var inlineNotesToggle: some View {
        Button {
            showsInlineNoteBubbles.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: showsInlineNoteBubbles ? "eye" : "eye.slash")
                    .font(.caption)
                Text("Inline")
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isOCRMode)
        .opacity(isOCRMode ? 0.5 : 1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var notesModeToggle: some View {
        Button {
            noteInteractionMode = noteInteractionMode == .edit ? .view : .edit
            if noteInteractionMode == .view {
                isNoteCreateMode = false
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: noteInteractionMode.iconName)
                    .font(.caption)
                Text(noteInteractionMode.title)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isOCRMode)
        .opacity(isOCRMode ? 0.5 : 1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var versionMenu: some View {
        Menu {
            if let focusedEntry {
                ForEach(focusedEntry.slot.versionOptions.reversed()) { option in
                    Button {
                        store.changePreviewVersion(logicalPageID: focusedEntry.id, to: option.id)
                        if let focusedComposedIndex {
                            requestJump(to: focusedComposedIndex)
                        }
                        syncNotesForFocusedGroup()
                    } label: {
                        if option.id == focusedEntry.selectedVersion.id {
                            Label(versionTitle(option), systemImage: "checkmark")
                        } else {
                            Text(versionTitle(option))
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.down")
                    .font(.caption)
                Text(versionTitle(focusedEntry?.selectedVersion))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var sourceMenu: some View {
        Menu {
            ForEach(UniversalDocViewerSource.allCases) { source in
                Button {
                    applySource(source)
                } label: {
                    if source == focusedEntry?.selectedSource {
                        Label(source.title, systemImage: "checkmark")
                    } else {
                        Text(source.title)
                    }
                }
            }

            Divider()

            Picker("Scope", selection: $sourceApplyScope) {
                ForEach(SourceApplyScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.down")
                    .font(.caption)
                Text((focusedEntry?.selectedSource.title ?? "Display") + (sourceApplyScope == .global ? " • Global" : ""))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    @ViewBuilder
    private var mainReader: some View {
        if isOCRMode {
            ocrReader
        } else {
            pdfReader
        }
    }

    private var pdfReader: some View {
        ContinuousPDFViewerRepresentable(
            entries: composedPDFEntries,
            preferredInitialComposedPageIndex: focusedComposedIndex,
            jumpToComposedPageIndex: pendingJumpComposedIndex,
            jumpRequestID: jumpRequestID,
            noteAnchors: noteAnchors,
            pageTagItems: pageTagItems,
            selectedNoteID: selectedNoteID,
            focusAnchor: selectedNoteAnchor,
            isNoteCreateMode: isNoteCreateMode && canEditNotes,
            showsInlineNoteBubbles: showsInlineNoteBubbles,
            isEditingEnabled: canEditNotes,
            onFocusedComposedPageChanged: { composedIndex in
                handleFocusedComposedIndex(composedIndex)
            },
            onCreateNoteRect: { composedIndex, normalizedRect in
                createRootNote(composedIndex: composedIndex, normalizedRect: normalizedRect)
            },
            onSelectNote: { noteID in
                notesViewModel?.selectedNoteID = noteID
            },
            onUpdateNoteRect: { noteID, normalizedRect in
                notesViewModel?.updateRect(noteID: noteID, normalizedRect: normalizedRect)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var ocrReader: some View {
        Group {
            if let focusedEntry,
               let text = focusedEntry.renderData?.ocrText,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ScrollView {
                    Text(text)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
                .background(Color(.systemBackground))
            } else {
                ContentUnavailableView(
                    "OCR Content Unavailable",
                    systemImage: "text.viewfinder",
                    description: Text("The selected page has no OCR text.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var notesPanel: some View {
        Group {
            if notesPanelCollapsed {
                VStack(spacing: 10) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            notesPanelCollapsed = false
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 12)

                    Divider()

                    Image(systemName: "text.bubble")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("Notes")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(-90))

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("Notes")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                notesPanelCollapsed = true
                            }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.headline)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.thinMaterial)

                    Divider()

                    Group {
                        if let notesViewModel {
                            DocNotesPane(
                                viewModel: notesViewModel,
                                pageVersionIDs: currentNotesPageVersionIDs,
                                pageSectionTitles: currentNotesPageSectionTitles,
                                isVisible: !isOCRMode,
                                isEditable: canEditNotes
                            )
                        } else {
                            ProgressView()
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                }
                .background(.ultraThinMaterial)
            }
        }
    }

    private var notesDrawer: some View {
        VStack(spacing: 0) {
            Button {
                notesDrawerExpanded.toggle()
            } label: {
                HStack {
                    Image(systemName: notesDrawerExpanded ? "chevron.down" : "chevron.up")
                    Text("Notes")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
            }
            .buttonStyle(.plain)

            if notesDrawerExpanded {
                if let notesViewModel {
                    DocNotesPane(
                        viewModel: notesViewModel,
                        pageVersionIDs: currentNotesPageVersionIDs,
                        pageSectionTitles: currentNotesPageSectionTitles,
                        isVisible: !isOCRMode,
                        isEditable: canEditNotes
                    )
                    .frame(maxHeight: 280)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Actions

    private func ensureFocusSeeded() {
        if store.focusedLogicalPageID == nil,
           let first = store.session.slots.first {
            store.setFocusedPage(first.id)
        }
    }

    private func navigateGroup(delta: Int) {
        guard let focusedGroupEntry,
              let currentIndex = groupEntries.firstIndex(where: { $0.id == focusedGroupEntry.id }) else {
            return
        }
        let targetIndex = currentIndex + delta
        guard targetIndex >= 0, targetIndex < groupEntries.count else { return }
        jumpToGroup(groupID: groupEntries[targetIndex].id)
    }

    private func jumpToGroup(groupID: String) {
        guard let targetGroup = groupEntries.first(where: { $0.id == groupID }) else {
            return
        }

        let targetLogicalPageID = targetGroup.entries
            .first(where: { composedIndexByLogicalPageID[$0.id] != nil })?.id
            ?? targetGroup.firstLogicalPageID

        guard let targetLogicalPageID else { return }
        store.setFocusedPage(targetLogicalPageID)
        if let composedIndex = composedIndexByLogicalPageID[targetLogicalPageID] {
            requestJump(to: composedIndex)
        }
    }

    private func applySource(_ source: UniversalDocViewerSource) {
        let wasOCRMode = isOCRMode
        switch sourceApplyScope {
        case .focused:
            store.changeSourceForFocusedPage(to: source)
        case .global:
            store.changeSourceForAllPages(to: source, using: dataProvider)
        }

        // Keep viewport stable when switching between PDF sources (Display/Original).
        // Only request an explicit jump when OCR mode is involved.
        if (wasOCRMode || source == .ocr),
           let focusedComposedIndex {
            requestJump(to: focusedComposedIndex)
        }
        syncNotesForFocusedGroup()
    }

    private func requestJump(to composedIndex: Int) {
        pendingJumpComposedIndex = composedIndex
        jumpRequestID &+= 1
    }

    private func handleFocusedComposedIndex(_ composedIndex: Int) {
        guard composedIndex >= 0, composedIndex < composedPDFEntries.count else { return }
        let logicalPageID = composedPDFEntries[composedIndex].logicalPageID
        store.setFocusedPage(logicalPageID)
    }

    private func resolvedPDFRenderData(for entry: ViewerLogicalEntry) -> (fileURL: URL, pageNumber: Int)? {
        if let renderData = entry.renderData,
           renderData.source != .ocr,
           let fileURL = renderData.fileURL {
            return (fileURL, renderData.pageNumber)
        }

        for candidate in [UniversalDocViewerSource.display, .original] {
            let fallback = dataProvider.resolve(
                slot: entry.slot,
                selectedVersionID: entry.selectedVersion.id,
                selectedSource: candidate
            )
            if let fallback,
               fallback.source != .ocr,
               let fileURL = fallback.fileURL {
                return (fileURL, fallback.pageNumber)
            }
        }

        return nil
    }

    private func syncNotesForFocusedGroup() {
        guard let notesViewModel else { return }
        let pageVersionIDs = currentNotesPageVersionIDs
        let signature = pageVersionIDs.map(\.uuidString).joined(separator: "|")
        guard signature != loadedNotesSignature else { return }

        loadedNotesSignature = signature
        notesViewModel.loadNotes(pageVersionIDs: pageVersionIDs)
        applyInitialNoteSelectionIfPossible()
    }

    private func applyInitialNoteSelectionIfPossible() {
        guard let pendingInitialNoteID,
              let notesViewModel,
              let note = notesViewModel.noteIndex[pendingInitialNoteID],
              let composedIndex = composedIndexByPageVersionID[note.pageVersionID] else {
            return
        }

        notesViewModel.selectedNoteID = pendingInitialNoteID
        if composedIndex >= 0, composedIndex < composedPDFEntries.count {
            let logicalPageID = composedPDFEntries[composedIndex].logicalPageID
            store.setFocusedPage(logicalPageID)
            requestJump(to: composedIndex)
        }
        self.pendingInitialNoteID = nil
    }

    private func createRootNote(composedIndex: Int, normalizedRect: CGRect) {
        guard composedIndex >= 0,
              composedIndex < composedPDFEntries.count,
              let notesViewModel else {
            return
        }

        let composedEntry = composedPDFEntries[composedIndex]
        guard let logicalEntry = logicalEntries.first(where: { $0.id == composedEntry.logicalPageID }),
              let page = logicalEntry.page else {
            return
        }

        notesViewModel.createRoot(
            pageVersionID: composedEntry.pageVersionID,
            page: page,
            normalizedRect: normalizedRect,
            title: nil,
            body: "New note"
        )

        store.setFocusedPage(composedEntry.logicalPageID)
        isNoteCreateMode = false
    }

    private func versionTitle(_ option: UniversalDocVersionOption?) -> String {
        guard let option else { return "Version" }
        let defaultMark = option.isCurrentDefault ? " (Default)" : ""
        return "V\(option.ordinal) • P\(option.pageNumber)\(defaultMark)"
    }
}

private struct GroupJumpSheet: View {
    @Environment(\.dismiss) private var dismiss

    let groups: [ViewerGroupEntry]
    let currentGroupID: String?
    let onSubmit: (String) -> Void

    var body: some View {
        NavigationStack {
            List {
                SwiftUI.ForEach<[ViewerGroupEntry], String, GroupJumpRow>(groups, id: \.id) { group in
                    GroupJumpRow(
                        group: group,
                        isCurrent: group.id == currentGroupID
                    ) {
                        onSubmit(group.id)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Go to Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct GroupJumpRow: View {
    let group: ViewerGroupEntry
    let isCurrent: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.pageGroupTitle)
                        .foregroundStyle(.primary)
                    Text(group.docTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
        }
    }
}

private struct CreatePageVersionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \PDFBundle.createdAt, order: .reverse) private var bundles: [PDFBundle]

    let pageID: UUID
    let baseVersionID: UUID
    let onCreated: (_ pageVersionID: UUID) -> Void

    @State private var selectedBundleID: UUID?
    @State private var pageNumber: Int = 1
    @State private var inheritTags = true
    @State private var inheritVariables = true
    @State private var inheritNoteBlocks = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingImportBundle = false
    @State private var showingBundleCreationPrompt = false
    @State private var hasPromptedBundleCreation = false

    private var selectedBundle: PDFBundle? {
        guard let selectedBundleID else { return nil }
        return bundles.first(where: { $0.id == selectedBundleID })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Target") {
                    if bundles.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("No PDF bundles available", systemImage: "tray")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Picker("Bundle", selection: $selectedBundleID) {
                            ForEach(bundles) { bundle in
                                Text(bundle.displayName).tag(bundle.id as UUID?)
                            }
                        }
                        Stepper("Page Number: \(pageNumber)", value: $pageNumber, in: 1...9999)
                    }

                    Button {
                        showingImportBundle = true
                    } label: {
                        Label("Import PDF Bundle", systemImage: "plus.circle")
                    }
                }

                Section("Inherit From Base Version") {
                    Toggle("Tags", isOn: $inheritTags)
                    Toggle("Variables", isOn: $inheritVariables)
                    Toggle("Note Blocks", isOn: $inheritNoteBlocks)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New Version")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createVersion()
                    }
                    .disabled(!canCreate || isSaving)
                }
            }
            .sheet(isPresented: $showingImportBundle) {
                PDFBundleImportView()
            }
            .onAppear {
                seedDefaultsIfNeeded()
                promptForBundleCreationIfNeeded()
            }
            .onChange(of: bundles.map(\.id)) { _, _ in
                if bundles.isEmpty {
                    selectedBundleID = nil
                } else if selectedBundle == nil {
                    selectedBundleID = nil
                    seedDefaultsIfNeeded()
                }
                promptForBundleCreationIfNeeded()
            }
            .alert("No PDF Bundle Available", isPresented: $showingBundleCreationPrompt) {
                Button("Import Bundle") {
                    showingImportBundle = true
                }
                Button("Not Now", role: .cancel) {}
            } message: {
                Text("Creating a new page version requires at least one PDF bundle.")
            }
        }
    }

    private var canCreate: Bool {
        selectedBundle != nil
    }

    private func seedDefaultsIfNeeded() {
        guard selectedBundleID == nil else { return }
        guard !bundles.isEmpty else { return }
        guard let page = fetchPage() else {
            selectedBundleID = bundles.first?.id
            return
        }

        let preferredBundleID = page.currentPDFBundleID
        if bundles.contains(where: { $0.id == preferredBundleID }) {
            selectedBundleID = preferredBundleID
        } else {
            selectedBundleID = bundles.first?.id
        }
        pageNumber = max(page.currentPageNumber, 1)
    }

    private func createVersion() {
        guard let page = fetchPage() else {
            errorMessage = "Unable to resolve the target page."
            return
        }
        guard let selectedBundle else {
            if bundles.isEmpty {
                promptForBundleCreationIfNeeded(force: true)
            }
            errorMessage = "Please select a bundle."
            return
        }

        isSaving = true
        defer { isSaving = false }

        let baseVersion = page.versions?.first(where: { $0.id == baseVersionID }) ?? page.latestVersion
        let inheritance = VersionInheritanceOptions(
            inheritTags: inheritTags,
            inheritVariables: inheritVariables,
            inheritNoteBlocks: inheritNoteBlocks
        )

        do {
            let service = PageVersionService(modelContext: modelContext)
            guard let created = try service.createVersion(
                for: page,
                to: selectedBundle,
                pageNumber: pageNumber,
                basedOn: baseVersion,
                inheritance: inheritance
            ) else {
                errorMessage = "No new version created because bundle/page is unchanged."
                return
            }
            try modelContext.save()
            onCreated(created.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func promptForBundleCreationIfNeeded(force: Bool = false) {
        guard bundles.isEmpty else { return }
        guard force || !hasPromptedBundleCreation else { return }
        hasPromptedBundleCreation = true
        showingBundleCreationPrompt = true
    }

    private func fetchPage() -> Page? {
        let descriptor = FetchDescriptor<Page>(
            predicate: #Predicate { page in
                page.id == pageID
            }
        )
        return try? modelContext.fetch(descriptor).first
    }
}
