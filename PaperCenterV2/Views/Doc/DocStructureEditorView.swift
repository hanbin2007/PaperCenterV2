//
//  DocStructureEditorView.swift
//  PaperCenterV2
//
//  Tree editor for a single Doc with metadata assignment per node.
//

import SwiftUI
import SwiftData

struct DocStructureEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \PDFBundle.createdAt, order: .reverse)
    private var bundles: [PDFBundle]

    let doc: Doc

    @State private var viewModel: DocStructureEditorViewModel?
    @State private var selectedNode: TreeNodeSelection = .doc
    @State private var assignmentViewModel: TagVariableAssignmentViewModel?
    @State private var expandedGroupIDs: Set<UUID> = []
    @State private var presentedSheet: PresentedSheet?
    @State private var draftDocTitle: String = ""

    var body: some View {
        NavigationStack {
            List {
                structureSection
                metadataSection
                statusSection
            }
            .navigationTitle("Edit Structure")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        presentedSheet = .newGroup
                    } label: {
                        Label("Add Group", systemImage: "folder.badge.plus")
                    }
                }
            }
            .sheet(item: $presentedSheet) { sheet in
                buildSheet(for: sheet)
            }
            .onAppear {
                initializeStateIfNeeded()
            }
            .onChange(of: selectedNode) { _, _ in
                rebuildAssignmentViewModel()
            }
        }
    }

    // MARK: - Sections

    private var structureSection: some View {
        Section("Structure") {
            docRow

            if let viewModel {
                if viewModel.orderedGroups.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "tray")
                            .foregroundStyle(.secondary)
                        Text("No page groups yet")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                ForEach(viewModel.orderedGroups) { group in
                    groupRow(group)

                    if expandedGroupIDs.contains(group.id) {
                        if group.orderedPages.isEmpty {
                            HStack {
                                Color.clear
                                    .frame(width: 28)
                                Text("No pages")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        }

                        ForEach(group.orderedPages) { page in
                            pageRow(page, in: group)
                        }

                        HStack {
                            Color.clear
                                .frame(width: 22)
                            Button {
                                presentedSheet = .newPage(group)
                            } label: {
                                Label("Add Page", systemImage: "plus.circle")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                    }
                }
            }
        }
    }

    private var metadataSection: some View {
        Section(selectedNodeMetadataTitle) {
            if selectedNode == .doc {
                TextField("Document Title", text: $draftDocTitle)
                    .textInputAutocapitalization(.words)
                    .onSubmit {
                        commitDocTitle()
                    }

                Button("Update Title") {
                    commitDocTitle()
                }
                .disabled(draftDocTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let assignmentViewModel {
                TagVariableAssignmentView(
                    viewModel: assignmentViewModel,
                    layoutMode: .sheet
                )

                VariableValueSectionView(viewModel: assignmentViewModel)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Text("Unable to resolve the selected node")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if let viewModel,
           viewModel.statusMessage != nil || viewModel.errorMessage != nil {
            Section("Status") {
                if let status = viewModel.statusMessage {
                    Label(status, systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                        .font(.caption)
                }

                if let error = viewModel.errorMessage {
                    Label(error, systemImage: "xmark.circle")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
    }

    // MARK: - Tree Rows

    private var docRow: some View {
        HStack(spacing: 10) {
            nodeButton(
                node: .doc,
                icon: "doc.text",
                title: doc.title,
                subtitle: "\(doc.orderedPageGroups.count) groups · \(doc.totalPageCount) pages",
                tagCount: doc.tags?.count ?? 0
            )

            Spacer(minLength: 8)

            Menu {
                Button {
                    selectedNode = .doc
                } label: {
                    Label("Edit Metadata", systemImage: "tag")
                }

                Button {
                    presentedSheet = .newGroup
                } label: {
                    Label("Add Page Group", systemImage: "folder.badge.plus")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .listRowBackground(rowBackground(for: .doc))
    }

    private func groupRow(_ group: PageGroup) -> some View {
        HStack(spacing: 10) {
            Button {
                toggleGroupExpansion(group.id)
            } label: {
                Image(systemName: expandedGroupIDs.contains(group.id) ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)

            nodeButton(
                node: .group(group.id),
                icon: "folder",
                title: group.title,
                subtitle: "\(group.orderedPages.count) pages",
                tagCount: group.tags?.count ?? 0
            )

            Spacer(minLength: 8)

            Menu {
                Button {
                    selectedNode = .group(group.id)
                } label: {
                    Label("Edit Metadata", systemImage: "tag")
                }

                Button {
                    presentedSheet = .renameGroup(group)
                } label: {
                    Label("Rename Group", systemImage: "pencil")
                }

                Button {
                    presentedSheet = .newPage(group)
                } label: {
                    Label("Add Page", systemImage: "plus.circle")
                }

                Button {
                    viewModel?.movePageGroup(group, by: -1)
                } label: {
                    Label("Move Up", systemImage: "arrow.up")
                }
                .disabled(!canMoveGroup(group, offset: -1))

                Button {
                    viewModel?.movePageGroup(group, by: 1)
                } label: {
                    Label("Move Down", systemImage: "arrow.down")
                }
                .disabled(!canMoveGroup(group, offset: 1))

                Divider()

                Button(role: .destructive) {
                    viewModel?.deletePageGroup(group)
                    didMutateStructure()
                } label: {
                    Label("Delete Group", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowBackground(rowBackground(for: .group(group.id)))
    }

    private func pageRow(_ page: Page, in group: PageGroup) -> some View {
        HStack(spacing: 10) {
            Color.clear
                .frame(width: 22)

            nodeButton(
                node: .page(page.id),
                icon: "doc.richtext",
                title: "Page \(page.currentPageNumber)",
                subtitle: pageSubtitle(page),
                tagCount: page.tags?.count ?? 0
            )

            Spacer(minLength: 8)

            Menu {
                Button {
                    selectedNode = .page(page.id)
                } label: {
                    Label("Edit Metadata", systemImage: "tag")
                }

                Button {
                    presentedSheet = .editPage(page)
                } label: {
                    Label("Edit Page Reference", systemImage: "pencil")
                }

                Button {
                    viewModel?.movePage(page, in: group, by: -1)
                } label: {
                    Label("Move Up", systemImage: "arrow.up")
                }
                .disabled(!canMovePage(page, in: group, offset: -1))

                Button {
                    viewModel?.movePage(page, in: group, by: 1)
                } label: {
                    Label("Move Down", systemImage: "arrow.down")
                }
                .disabled(!canMovePage(page, in: group, offset: 1))

                if let viewModel {
                    Menu("Move To Group") {
                        ForEach(viewModel.orderedGroups) { target in
                            Button(target.title) {
                                viewModel.movePage(page, from: group, to: target)
                                selectedNode = .page(page.id)
                                expandedGroupIDs.insert(target.id)
                                didMutateStructure()
                            }
                            .disabled(target.id == group.id)
                        }
                    }
                }

                Divider()

                Button(role: .destructive) {
                    viewModel?.deletePage(page)
                    didMutateStructure()
                } label: {
                    Label("Delete Page", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowBackground(rowBackground(for: .page(page.id)))
    }

    private func nodeButton(
        node: TreeNodeSelection,
        icon: String,
        title: String,
        subtitle: String,
        tagCount: Int
    ) -> some View {
        Button {
            selectedNode = node
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)
                }

                HStack(spacing: 8) {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if tagCount > 0 {
                        Text("\(tagCount) tags")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                .padding(.leading, 24)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sheet Builders

    @ViewBuilder
    private func buildSheet(for sheet: PresentedSheet) -> some View {
        switch sheet {
        case .newGroup:
            PageGroupEditorSheet(
                title: "New Page Group",
                initialTitle: "",
                actionTitle: "Create"
            ) { title in
                guard let group = viewModel?.createPageGroup(title: title) else { return }
                expandedGroupIDs.insert(group.id)
                selectedNode = .group(group.id)
                didMutateStructure()
            }

        case .renameGroup(let group):
            PageGroupEditorSheet(
                title: "Rename Page Group",
                initialTitle: group.title,
                actionTitle: "Save"
            ) { title in
                viewModel?.renamePageGroup(group, title: title)
                didMutateStructure()
            }

        case .newPage(let group):
            PageEditorSheet(
                title: "Add Page",
                actionTitle: "Create",
                bundles: bundles,
                initialBundleID: bundles.first?.id,
                initialPageNumber: 1,
                pageCountProvider: { bundle in
                    viewModel?.pageCount(for: bundle) ?? 0
                }
            ) { bundle, pageNumber in
                guard let created = viewModel?.createPage(in: group, bundle: bundle, pageNumber: pageNumber) else {
                    return viewModel?.errorMessage ?? "Unable to add page"
                }
                selectedNode = .page(created.id)
                expandedGroupIDs.insert(group.id)
                didMutateStructure()
                return nil
            }

        case .editPage(let page):
            let resolvedGroup = page.pageGroup
            PageEditorSheet(
                title: "Edit Page",
                actionTitle: "Save",
                bundles: bundles,
                initialBundleID: page.pdfBundle?.id,
                initialPageNumber: page.currentPageNumber,
                pageCountProvider: { bundle in
                    viewModel?.pageCount(for: bundle) ?? 0
                }
            ) { bundle, pageNumber in
                guard resolvedGroup != nil else {
                    return "The selected page no longer belongs to a group"
                }
                viewModel?.updatePage(page, bundle: bundle, pageNumber: pageNumber)
                didMutateStructure()
                return viewModel?.errorMessage
            }
        }
    }

    // MARK: - Helpers

    private var selectedNodeMetadataTitle: String {
        switch selectedNode {
        case .doc:
            return "Metadata • Document"
        case .group(let id):
            let group = viewModel?.orderedGroups.first(where: { $0.id == id })
            return "Metadata • \(group?.title ?? "Page Group")"
        case .page(let id):
            let page = resolvePage(id)
            return "Metadata • Page \(page?.currentPageNumber ?? 0)"
        }
    }

    private func initializeStateIfNeeded() {
        guard viewModel == nil else { return }
        viewModel = DocStructureEditorViewModel(modelContext: modelContext, doc: doc)
        draftDocTitle = doc.title
        expandedGroupIDs = Set(doc.orderedPageGroups.map(\.id))
        selectedNode = .doc
        rebuildAssignmentViewModel()
    }

    private func commitDocTitle() {
        guard let viewModel else { return }
        viewModel.renameDocument(title: draftDocTitle)
        draftDocTitle = doc.title
    }

    private func rebuildAssignmentViewModel() {
        guard let target = resolveSelectionTarget() else {
            assignmentViewModel = nil
            return
        }

        assignmentViewModel = TagVariableAssignmentViewModel(
            modelContext: modelContext,
            entityType: target.entityType,
            target: target.target
        )
    }

    private func resolveSelectionTarget() -> SelectionTarget? {
        switch selectedNode {
        case .doc:
            return SelectionTarget(entityType: .doc, target: .doc(doc))
        case .group(let id):
            guard let group = viewModel?.orderedGroups.first(where: { $0.id == id }) else {
                return nil
            }
            return SelectionTarget(entityType: .pageGroup, target: .pageGroup(group))
        case .page(let id):
            guard let page = resolvePage(id) else {
                return nil
            }
            return SelectionTarget(entityType: .page, target: .page(page))
        }
    }

    private func resolvePage(_ id: UUID) -> Page? {
        guard let viewModel else { return nil }
        for group in viewModel.orderedGroups {
            if let page = group.orderedPages.first(where: { $0.id == id }) {
                return page
            }
        }
        return nil
    }

    private func toggleGroupExpansion(_ groupID: UUID) {
        if expandedGroupIDs.contains(groupID) {
            expandedGroupIDs.remove(groupID)
        } else {
            expandedGroupIDs.insert(groupID)
        }
    }

    private func rowBackground(for node: TreeNodeSelection) -> Color {
        selectedNode == node ? Color.accentColor.opacity(0.12) : Color.clear
    }

    private func pageSubtitle(_ page: Page) -> String {
        let bundle = page.pdfBundle?.displayName ?? "Missing Bundle"
        return "\(bundle)"
    }

    private func canMoveGroup(_ group: PageGroup, offset: Int) -> Bool {
        guard let viewModel,
              let index = viewModel.orderedGroups.firstIndex(where: { $0.id == group.id }) else {
            return false
        }
        let destination = index + offset
        return destination >= 0 && destination < viewModel.orderedGroups.count
    }

    private func canMovePage(_ page: Page, in group: PageGroup, offset: Int) -> Bool {
        guard let index = group.pageOrder.firstIndex(of: page.id) else {
            return false
        }
        let destination = index + offset
        return destination >= 0 && destination < group.pageOrder.count
    }

    private func didMutateStructure() {
        sanitizeSelection()
        rebuildAssignmentViewModel()
    }

    private func sanitizeSelection() {
        expandedGroupIDs = expandedGroupIDs.intersection(Set(doc.orderedPageGroups.map(\.id)))

        switch selectedNode {
        case .doc:
            return
        case .group(let groupID):
            if viewModel?.orderedGroups.contains(where: { $0.id == groupID }) != true {
                selectedNode = .doc
            }
        case .page(let pageID):
            if resolvePage(pageID) == nil {
                selectedNode = .doc
            }
        }
    }
}

// MARK: - Supporting Types

private struct SelectionTarget {
    let entityType: TaggableEntityType
    let target: TagVariableAssignmentViewModel.Target
}

private enum TreeNodeSelection: Hashable {
    case doc
    case group(UUID)
    case page(UUID)
}

private enum PresentedSheet: Identifiable {
    case newGroup
    case renameGroup(PageGroup)
    case newPage(PageGroup)
    case editPage(Page)

    var id: String {
        switch self {
        case .newGroup:
            return "new-group"
        case .renameGroup(let group):
            return "rename-group-\(group.id.uuidString)"
        case .newPage(let group):
            return "new-page-\(group.id.uuidString)"
        case .editPage(let page):
            return "edit-page-\(page.id.uuidString)"
        }
    }
}

private struct PageGroupEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let initialTitle: String
    let actionTitle: String
    let onSubmit: (_ title: String) -> Void

    @State private var name: String

    init(
        title: String,
        initialTitle: String,
        actionTitle: String,
        onSubmit: @escaping (_ title: String) -> Void
    ) {
        self.title = title
        self.initialTitle = initialTitle
        self.actionTitle = actionTitle
        self.onSubmit = onSubmit
        _name = State(initialValue: initialTitle)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Page Group Title", text: $name)
                        .textInputAutocapitalization(.words)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(actionTitle) {
                        onSubmit(name)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct PageEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let actionTitle: String
    let bundles: [PDFBundle]
    let initialBundleID: UUID?
    let initialPageNumber: Int
    let pageCountProvider: (PDFBundle) -> Int
    let onSubmit: (_ bundle: PDFBundle, _ pageNumber: Int) -> String?

    @State private var selectedBundleID: UUID?
    @State private var pageNumber: Int
    @State private var errorMessage: String?

    init(
        title: String,
        actionTitle: String,
        bundles: [PDFBundle],
        initialBundleID: UUID?,
        initialPageNumber: Int,
        pageCountProvider: @escaping (PDFBundle) -> Int,
        onSubmit: @escaping (_ bundle: PDFBundle, _ pageNumber: Int) -> String?
    ) {
        self.title = title
        self.actionTitle = actionTitle
        self.bundles = bundles
        self.initialBundleID = initialBundleID
        self.initialPageNumber = max(initialPageNumber, 1)
        self.pageCountProvider = pageCountProvider
        self.onSubmit = onSubmit
        _selectedBundleID = State(initialValue: initialBundleID)
        _pageNumber = State(initialValue: max(initialPageNumber, 1))
    }

    private var selectedBundle: PDFBundle? {
        guard let selectedBundleID else { return nil }
        return bundles.first(where: { $0.id == selectedBundleID })
    }

    private var maxPage: Int {
        guard let selectedBundle else { return 9_999 }
        let count = pageCountProvider(selectedBundle)
        return count > 0 ? count : 9_999
    }

    var body: some View {
        NavigationStack {
            Form {
                if bundles.isEmpty {
                    Section {
                        Label("No PDF bundles available", systemImage: "tray")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Source") {
                        Picker("Bundle", selection: $selectedBundleID) {
                            ForEach(bundles) { bundle in
                                Text(bundle.displayName)
                                    .tag(bundle.id as UUID?)
                            }
                        }

                        Stepper("Page Number: \(pageNumber)", value: $pageNumber, in: 1...maxPage)

                        if let selectedBundle {
                            let count = pageCountProvider(selectedBundle)
                            if count > 0 {
                                Text("Available pages: 1 - \(count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Page count unavailable for this bundle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(actionTitle) {
                        submit()
                    }
                    .disabled(selectedBundle == nil)
                }
            }
            .onAppear {
                if selectedBundleID == nil {
                    selectedBundleID = bundles.first?.id
                }
                pageNumber = min(max(pageNumber, 1), maxPage)
            }
            .onChange(of: selectedBundleID) { _, _ in
                pageNumber = min(max(pageNumber, 1), maxPage)
            }
        }
    }

    private func submit() {
        guard let selectedBundle else {
            errorMessage = "Please choose a bundle"
            return
        }

        let clampedPage = min(max(pageNumber, 1), maxPage)
        if let error = onSubmit(selectedBundle, clampedPage) {
            errorMessage = error
            return
        }

        dismiss()
    }
}

#Preview {
    let schema = Schema([
        PDFBundle.self,
        Doc.self,
        PageGroup.self,
        Page.self,
        PageVersion.self,
        Tag.self,
        TagGroup.self,
        Variable.self,
        DocVariableAssignment.self,
        PageGroupVariableAssignment.self,
        PageVariableAssignment.self,
    ])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [configuration])

    let bundle = PDFBundle(name: "Preview Bundle")
    let doc = Doc(title: "Preview Doc")
    let group = PageGroup(title: "Section A", doc: doc)
    doc.addPageGroup(group)
    let page = Page(pdfBundle: bundle, pageNumber: 1, pageGroup: group)
    group.addPage(page)

    let context = container.mainContext
    context.insert(bundle)
    context.insert(doc)

    return DocStructureEditorView(doc: doc)
        .modelContainer(container)
}
