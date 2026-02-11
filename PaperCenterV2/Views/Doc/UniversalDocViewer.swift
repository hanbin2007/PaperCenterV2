//
//  UniversalDocViewer.swift
//  PaperCenterV2
//
//  Reusable UniversalDoc viewer with per-page version/source switching.
//

import SwiftUI
import SwiftData
import PDFKit

struct UniversalDocViewer: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var store: UniversalDocSessionStore
    let dataProvider: UniversalDocDataProvider
    let onPageVersionCreated: (_ logicalPageID: UUID, _ pageVersionID: UUID) -> Void

    var body: some View {
        if !store.hasPages {
            ContentUnavailableView(
                "No Pages",
                systemImage: "doc.text.magnifyingglass",
                description: Text("This document has no pages to display.")
            )
        } else {
            TabView(selection: $store.currentPageIndex) {
                ForEach(Array(store.session.slots.enumerated()), id: \.element.id) { index, slot in
                    UniversalDocPageView(
                        slot: slot,
                        pageNumberInDoc: index + 1,
                        totalPages: store.session.slots.count,
                        store: store,
                        dataProvider: dataProvider,
                        onPageVersionCreated: { versionID in
                            onPageVersionCreated(slot.id, versionID)
                        }
                    )
                    .tag(index)
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
    }
}

private struct UniversalDocPageView: View {
    let slot: UniversalDocLogicalPageSlot
    let pageNumberInDoc: Int
    let totalPages: Int

    @Bindable var store: UniversalDocSessionStore
    let dataProvider: UniversalDocDataProvider
    let onPageVersionCreated: (_ pageVersionID: UUID) -> Void

    @State private var showCreateVersionSheet = false

    private var selectedVersionID: UUID {
        store.currentPreviewVersionID(for: slot.id) ?? slot.defaultVersionID
    }

    private var selectedVersion: UniversalDocVersionOption? {
        slot.versionOptions.first(where: { $0.id == selectedVersionID })
    }

    private var sourceBinding: Binding<UniversalDocViewerSource> {
        Binding {
            store.currentSource(for: slot.id) ?? slot.defaultSource
        } set: { newSource in
            store.changeSource(logicalPageID: slot.id, to: newSource)
        }
    }

    private var versionBinding: Binding<UUID> {
        Binding {
            selectedVersionID
        } set: { newVersionID in
            store.changePreviewVersion(logicalPageID: slot.id, to: newVersionID)
            guard let version = slot.versionOptions.first(where: { $0.id == newVersionID }) else { return }
            let available = dataProvider.availableSources(for: version)
            let currentSource = store.currentSource(for: slot.id) ?? slot.defaultSource
            if !available.contains(currentSource),
               let preferred = dataProvider.preferredSource(for: version) {
                store.changeSource(logicalPageID: slot.id, to: preferred)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let version = selectedVersion {
                controls(for: version)
                content(for: version)
            } else {
                ContentUnavailableView(
                    "Version Missing",
                    systemImage: "exclamationmark.triangle",
                    description: Text("The selected version is unavailable.")
                )
            }
        }
        .sheet(isPresented: $showCreateVersionSheet) {
            CreatePageVersionSheet(
                pageID: slot.pageID,
                baseVersionID: selectedVersionID
            ) { createdVersionID in
                onPageVersionCreated(createdVersionID)
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Page \(pageNumberInDoc) / \(totalPages)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    @ViewBuilder
    private func controls(for version: UniversalDocVersionOption) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Picker("Version", selection: versionBinding) {
                    ForEach(slot.versionOptions.reversed()) { option in
                        Text(versionTitle(option))
                            .tag(option.id)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!slot.canPreviewOtherVersions)

                Button {
                    showCreateVersionSheet = true
                } label: {
                    Label("New Version", systemImage: "plus.circle")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
            }

            let availableSources = dataProvider.availableSources(for: version)
            Picker("Source", selection: sourceBinding) {
                ForEach(UniversalDocViewerSource.allCases) { source in
                    Text(sourceLabel(source, available: availableSources.contains(source)))
                        .tag(source)
                }
            }
            .pickerStyle(.menu)
            .disabled(!slot.canSwitchSource || availableSources.isEmpty)
        }
    }

    @ViewBuilder
    private func content(for version: UniversalDocVersionOption) -> some View {
        let source = store.currentSource(for: slot.id) ?? slot.defaultSource
        let renderData = dataProvider.resolve(
            slot: slot,
            selectedVersionID: version.id,
            selectedSource: source
        )

        if let renderData {
            VStack(spacing: 12) {
                GroupBox {
                    if renderData.source == .ocr,
                       let text = renderData.ocrText,
                       !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ScrollView {
                            Text(text)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                        }
                        .frame(maxHeight: 360)
                    } else if let fileURL = renderData.fileURL {
                        UniversalDocPDFPageRepresentable(
                            fileURL: fileURL,
                            pageNumber: renderData.pageNumber
                        )
                        .frame(height: 520)
                    } else {
                        ContentUnavailableView(
                            "Source Unavailable",
                            systemImage: "eye.slash",
                            description: Text("No renderable file is available for this source.")
                        )
                    }
                } label: {
                    HStack {
                        Text("Source: \(renderData.source.title)")
                        Spacer()
                        Text(renderData.bundleDisplayName)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }

                notesSection(notes: renderData.noteBlocks)
            }
        } else {
            ContentUnavailableView(
                "Render Failed",
                systemImage: "xmark.octagon",
                description: Text("Unable to resolve the current page version/source.")
            )
        }
    }

    @ViewBuilder
    private func notesSection(notes: [NoteBlock]) -> some View {
        let noteIndex = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        let ordered = notes.sorted { lhs, rhs in
            lhs.createdAt < rhs.createdAt
        }

        GroupBox {
            if ordered.isEmpty {
                Text("No note blocks for this version.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(ordered.prefix(8)) { note in
                        let level = note.nestingLevel(in: noteIndex)
                        HStack(alignment: .top, spacing: 8) {
                            Text(String(repeating: "  ", count: level) + "•")
                                .foregroundStyle(.secondary)
                            Text(note.title ?? note.body)
                                .lineLimit(2)
                                .font(.caption)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } label: {
            Text("Note Blocks (\(notes.count))")
                .font(.caption)
        }
    }

    private func versionTitle(_ option: UniversalDocVersionOption) -> String {
        let defaultMark = option.isCurrentDefault ? " (Default)" : ""
        return "V\(option.ordinal) • P\(option.pageNumber)\(defaultMark)"
    }

    private func sourceLabel(_ source: UniversalDocViewerSource, available: Bool) -> String {
        available ? source.title : "\(source.title) (Unavailable)"
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

    private var selectedBundle: PDFBundle? {
        guard let selectedBundleID else { return nil }
        return bundles.first(where: { $0.id == selectedBundleID })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Target") {
                    Picker("Bundle", selection: $selectedBundleID) {
                        ForEach(bundles) { bundle in
                            Text(bundle.displayName).tag(bundle.id as UUID?)
                        }
                    }
                    Stepper("Page Number: \(pageNumber)", value: $pageNumber, in: 1...9999)
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
            .onAppear {
                seedDefaultsIfNeeded()
            }
        }
    }

    private var canCreate: Bool {
        selectedBundle != nil
    }

    private func seedDefaultsIfNeeded() {
        guard selectedBundleID == nil else { return }
        guard let page = fetchPage() else { return }
        selectedBundleID = page.currentPDFBundleID
        pageNumber = page.currentPageNumber
    }

    private func createVersion() {
        guard let page = fetchPage() else {
            errorMessage = "Unable to resolve the target page."
            return
        }
        guard let selectedBundle else {
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

    private func fetchPage() -> Page? {
        let descriptor = FetchDescriptor<Page>(
            predicate: #Predicate { page in
                page.id == pageID
            }
        )
        return try? modelContext.fetch(descriptor).first
    }
}

private struct UniversalDocPDFPageRepresentable: UIViewRepresentable {
    let fileURL: URL
    let pageNumber: Int

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePage
        view.displaysPageBreaks = true
        view.backgroundColor = .secondarySystemBackground
        return view
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        if pdfView.document?.documentURL != fileURL {
            pdfView.document = PDFDocument(url: fileURL)
        }

        guard let document = pdfView.document else { return }
        let pageIndex = max(pageNumber - 1, 0)
        guard let page = document.page(at: pageIndex) else { return }
        if pdfView.currentPage != page {
            pdfView.go(to: page)
        }
    }
}
