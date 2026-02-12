//
//  DocNotesPane.swift
//  PaperCenterV2
//
//  Note panel with hierarchical editing actions.
//

import SwiftUI

struct DocNotesPane: View {
    @Bindable var viewModel: DocNotesEditorViewModel

    let pageVersionIDs: [UUID]
    let pageSectionTitles: [UUID: String]
    let isVisible: Bool
    let isEditable: Bool

    @State private var composer: NoteComposer?
    @State private var metadataEditor: NoteMetadataEditor?

    private struct NotesSection: Identifiable {
        let pageVersionID: UUID
        let title: String
        let nodes: [FlattenedNode]

        var id: UUID { pageVersionID }
    }

    private struct FlattenedNode: Identifiable {
        let id: UUID
        let note: NoteBlock
        let depth: Int
    }

    private var sectionedNotes: [NotesSection] {
        var seen = Set<UUID>()
        let orderedIDs = pageVersionIDs.filter { seen.insert($0).inserted }
        return orderedIDs.compactMap { pageVersionID in
            let nodes = flattenedNotes(for: pageVersionID)
            guard !nodes.isEmpty else { return nil }
            return NotesSection(
                pageVersionID: pageVersionID,
                title: pageSectionTitles[pageVersionID] ?? "Page",
                nodes: nodes
            )
        }
    }

    private var totalNoteCount: Int {
        sectionedNotes.reduce(0) { $0 + $1.nodes.count }
    }

    private func flattenedNotes(for pageVersionID: UUID) -> [FlattenedNode] {
        var result: [FlattenedNode] = []
        func visit(_ note: NoteBlock, depth: Int) {
            result.append(FlattenedNode(id: note.id, note: note, depth: depth))
            for child in viewModel.orderedChildren(of: note.id) {
                visit(child, depth: depth + 1)
            }
        }

        for root in viewModel.rootNotes(for: pageVersionID) {
            visit(root, depth: 0)
        }
        return result
    }

    var body: some View {
        Group {
            if !isVisible {
                hiddenState
            } else {
                content
            }
        }
        .onAppear {
            viewModel.loadNotes(pageVersionIDs: pageVersionIDs)
        }
        .onChange(of: pageVersionIDs) { _, newValue in
            viewModel.loadNotes(pageVersionIDs: newValue)
        }
        .onChange(of: isEditable) { _, editable in
            if !editable {
                composer = nil
                metadataEditor = nil
            }
        }
        .sheet(item: $composer) { composer in
            NoteComposerSheet(composer: composer) { payload in
                switch composer.mode {
                case .edit(let noteID):
                    viewModel.updateNote(
                        noteID: noteID,
                        title: payload.title,
                        body: payload.body
                    )
                case .reply(let parentID):
                    viewModel.createReply(
                        parentID: parentID,
                        title: payload.title,
                        body: payload.body
                    )
                }
            }
        }
        .sheet(item: $metadataEditor) { editor in
            if let note = viewModel.noteIndex[editor.noteID] {
                NoteMetadataEditorSheet(note: note)
            } else {
                ContentUnavailableView("Note Missing", systemImage: "xmark.octagon")
            }
        }
    }

    private var hiddenState: some View {
        VStack(spacing: 8) {
            Image(systemName: "eye.slash")
                .foregroundStyle(.secondary)
            Text("Notes are hidden in OCR mode")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if totalNoteCount == 0 {
                ContentUnavailableView(
                    "No Notes",
                    systemImage: "text.bubble",
                    description: Text(
                        isEditable
                            ? "Use Add Note mode and drag a rectangle on PDF to create one."
                            : "Switch to Edit mode to create or modify notes."
                    )
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(sectionedNotes) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(section.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 2)

                                ForEach(section.nodes) { item in
                                    noteRow(item)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            statusRow
        }
        .padding(12)
        .background(.thinMaterial)
    }

    private var header: some View {
        HStack {
            Text("Notes")
                .font(.headline)
            Spacer()
            Text("\(totalNoteCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func noteRow(_ item: FlattenedNode) -> some View {
        let note = item.note
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                viewModel.selectedNoteID = note.id
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    if item.depth > 0 {
                        Text(String(repeating: "\u{2022} ", count: item.depth))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        if let title = note.title, !title.isEmpty {
                            Text(title)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }

                        Text(note.body)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)

                        if let tags = note.tags, !tags.isEmpty {
                            TagDisplayView(tags: tags)
                                .padding(.top, 2)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(8)
                .background(viewModel.selectedNoteID == note.id ? Color.accentColor.opacity(0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                iconButton("arrow.up") {
                    move(noteID: note.id, direction: -1)
                }
                .disabled(!canMove(noteID: note.id, direction: -1))

                iconButton("arrow.down") {
                    move(noteID: note.id, direction: 1)
                }
                .disabled(!canMove(noteID: note.id, direction: 1))

                iconButton("arrowshape.turn.up.left") {
                    composer = NoteComposer(mode: .reply(parentID: note.id), title: nil, body: "")
                }

                iconButton("square.and.pencil") {
                    composer = NoteComposer(mode: .edit(noteID: note.id), title: note.title, body: note.body)
                }

                iconButton("tag") {
                    metadataEditor = NoteMetadataEditor(noteID: note.id)
                }

                Menu {
                    Button("Move to Root") {
                        viewModel.moveToParent(noteID: note.id, newParentID: nil, at: nil)
                    }

                    let candidates = parentCandidates(for: note.id)
                    if !candidates.isEmpty {
                        Divider()
                        ForEach(candidates) { candidate in
                            Button("Move under \(candidate.title ?? candidate.body)") {
                                viewModel.moveToParent(noteID: note.id, newParentID: candidate.id, at: nil)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption)
                }

                Spacer()

                iconButton("trash", role: .destructive) {
                    viewModel.deleteSubtree(noteID: note.id)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.leading, CGFloat(item.depth) * 10)
            .disabled(!isEditable)
            .opacity(isEditable ? 1 : 0.45)
        }
        .padding(.vertical, 2)
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            if let status = viewModel.statusMessage {
                Label(status, systemImage: "checkmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
            if let error = viewModel.errorMessage {
                Label(error, systemImage: "xmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
            Spacer()
        }
    }

    private func canMove(noteID: UUID, direction: Int) -> Bool {
        let siblings = siblingList(for: noteID)
        guard let index = siblings.firstIndex(where: { $0.id == noteID }) else { return false }
        let target = index + direction
        return target >= 0 && target < siblings.count
    }

    private func move(noteID: UUID, direction: Int) {
        let siblings = siblingList(for: noteID)
        guard let index = siblings.firstIndex(where: { $0.id == noteID }) else { return }
        let destination = index + direction
        viewModel.moveSibling(noteID: noteID, from: index, to: destination)
    }

    private func siblingList(for noteID: UUID) -> [NoteBlock] {
        guard let note = viewModel.noteIndex[noteID] else { return [] }
        if let parentID = note.parentNoteID {
            return viewModel.orderedChildren(of: parentID)
        }
        return viewModel.rootNotes
    }

    private func parentCandidates(for noteID: UUID) -> [NoteBlock] {
        guard let note = viewModel.noteIndex[noteID] else { return [] }
        let excluded = Set(note.flattenedThread(from: viewModel.notes).map(\.id)).union([noteID])
        return viewModel.notes
            .filter { $0.id != noteID && !excluded.contains($0.id) && $0.pageVersionID == note.pageVersionID }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.createdAt < rhs.createdAt
            }
    }

    private func iconButton(_ systemName: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemName)
        }
        .buttonStyle(.plain)
    }
}

private struct NoteComposer: Identifiable {
    enum Mode {
        case edit(noteID: UUID)
        case reply(parentID: UUID)
    }

    let mode: Mode
    var title: String?
    var body: String

    var id: String {
        switch mode {
        case .edit(let noteID):
            return "edit-\(noteID.uuidString)"
        case .reply(let parentID):
            return "reply-\(parentID.uuidString)"
        }
    }
}

private struct NoteComposerPayload {
    let title: String?
    let body: String
}

private struct NoteMetadataEditor: Identifiable {
    let noteID: UUID
    var id: UUID { noteID }
}

private struct NoteComposerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let composer: NoteComposer
    let onSave: (NoteComposerPayload) -> Void

    @State private var titleText: String
    @State private var bodyText: String

    init(composer: NoteComposer, onSave: @escaping (NoteComposerPayload) -> Void) {
        self.composer = composer
        self.onSave = onSave
        _titleText = State(initialValue: composer.title ?? "")
        _bodyText = State(initialValue: composer.body)
    }

    private var sheetTitle: String {
        switch composer.mode {
        case .edit:
            return "Edit Note"
        case .reply:
            return "Reply"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Optional", text: $titleText)
                }

                Section("Body") {
                    TextEditor(text: $bodyText)
                        .frame(minHeight: 180)
                }
            }
            .navigationTitle(sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(
                            NoteComposerPayload(
                                title: titleText,
                                body: bodyText
                            )
                        )
                        dismiss()
                    }
                    .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct NoteMetadataEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let note: NoteBlock

    @State private var assignmentViewModel: TagVariableAssignmentViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let assignmentViewModel {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            TagVariableAssignmentView(
                                viewModel: assignmentViewModel,
                                layoutMode: .sheet
                            )

                            VariableValueSectionView(viewModel: assignmentViewModel)
                        }
                        .padding(16)
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Note Metadata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                if assignmentViewModel == nil {
                    assignmentViewModel = TagVariableAssignmentViewModel(
                        modelContext: modelContext,
                        entityType: .noteBlock,
                        target: .noteBlock(note)
                    )
                }
            }
        }
    }
}
