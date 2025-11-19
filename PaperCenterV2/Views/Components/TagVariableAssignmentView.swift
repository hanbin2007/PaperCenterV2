//
//  TagVariableAssignmentView.swift
//  PaperCenterV2
//
//  Inline tag & variable selector with capsule grid styling.
//

import SwiftData
import SwiftUI

struct TagVariableAssignmentView: View {
    @Bindable var viewModel: TagVariableAssignmentViewModel
    let layoutMode: LayoutMode
    @Environment(\.modelContext) private var modelContext

    @State private var showAddTagGroupPopover = false
    @State private var newTagGroupName = ""
    @State private var newTagNames: [String: String] = [:]
    @State private var showAddVariableSheet = false
    @State private var propertyViewModel: PropertyManagementViewModel?

    enum LayoutMode {
        case form
        case sheet
    }

    private struct TagGroupDisplay: Identifiable {
        let id: String
        let title: String
        let group: TagGroup?
        let tags: [Tag]
    }

    private var groupedTags: [TagGroupDisplay] {
        let filtered = viewModel.searchText.isEmpty
            ? viewModel.availableTags
            : viewModel.availableTags.filter { $0.name.localizedCaseInsensitiveContains(viewModel.searchText) }
        var displays: [TagGroupDisplay] = viewModel.availableTagGroups
            .sortedByManualOrder()
            .map { group in
                let tags = filtered
                    .filter { $0.tagGroup?.id == group.id }
                    .sortedByManualOrder()
                return TagGroupDisplay(
                    id: group.id.uuidString,
                    title: group.name,
                    group: group,
                    tags: tags
                )
            }

        let ungroupedTags = filtered
            .filter { $0.tagGroup == nil }
            .sortedByManualOrder()
        displays.append(
            TagGroupDisplay(
                id: "ungrouped",
                title: "Other",
                group: nil,
                tags: ungroupedTags
            )
        )
        return displays
    }

    private var filteredVariables: [Variable] {
        guard !viewModel.searchText.isEmpty else {
            return viewModel.availableVariables
        }

        return viewModel.availableVariables.filter { $0.name.localizedCaseInsensitiveContains(viewModel.searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            searchField
            Section(header: tagSectionHeader) {
                tagsSection
            }
            Section(header: variableSectionHeader) {
                variableSelectionSection
            }
            statusRow
        }
        .sheet(isPresented: $showAddVariableSheet, onDismiss: {
            viewModel.refresh()
        }) {
            if let propertyViewModel {
                VariableEditView(viewModel: propertyViewModel, variable: nil)
                    .modelContext(modelContext)
            } else {
                ProgressView()
                    .padding()
                    .onAppear {
                        propertyViewModel = PropertyManagementViewModel(modelContext: modelContext)
                    }
            }
        }
        .onAppear {
            if propertyViewModel == nil {
                propertyViewModel = PropertyManagementViewModel(modelContext: modelContext)
            }
        }
    }

    private var searchField: some View {
        TextField("Search tags or variables", text: $viewModel.searchText)
            .textFieldStyle(.roundedBorder)
    }

    private var tagsSection: some View {
        Group {
            if groupedTags.isEmpty {
                contentUnavailable(message: "No tags in scope")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(groupedTags) { group in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(group.title)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                                FlowLayout(spacing: 8) {
                                    ForEach(group.tags) { tag in
                                        TagCapsule(
                                            tag: tag,
                                            isSelected: viewModel.selectedTagIDs.contains(tag.id),
                                            action: { viewModel.toggleTag(tag) }
                                        )
                                    }
                                    AddTagChip(
                                        text: Binding(
                                            get: { newTagNames[tagEntryKey(for: group.group), default: ""] },
                                            set: { newTagNames[tagEntryKey(for: group.group)] = $0 }
                                        ),
                                        placeholder: "Add tag"
                                    ) {
                                        attemptCreateTag(for: group.group)
                                    }
                                }
                                if group.tags.isEmpty && !viewModel.searchText.isEmpty {
                                    Text("No matches in this group")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.leading, 2)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var variableSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(title: "Select Variables")
            LazyVGrid(columns: adaptiveColumns, spacing: 10) {
                ForEach(filteredVariables) { variable in
                    VariableSelectChip(
                        variable: variable,
                        isSelected: viewModel.selectedVariableIDs.contains(variable.id),
                        action: { viewModel.toggleVariableSelection(variable) }
                    )
                }
            }
            if filteredVariables.isEmpty {
                let message = viewModel.searchText.isEmpty ? "No variables in scope" : "No variables match your search"
                contentUnavailable(message: message)
            }
        }
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            if let status = viewModel.statusMessage {
                Label(status, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            if let error = viewModel.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()
            if viewModel.isSaving {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .padding(.top, 4)
    }

    private var tagSectionHeader: some View {
        HStack {
            Text("Tag Settings")
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            Button {
                newTagGroupName = ""
                showAddTagGroupPopover = true
            } label: {
                Label("Add Tag Group", systemImage: "plus.circle")
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showAddTagGroupPopover, arrowEdge: .top) {
                TagGroupQuickAddPopover(
                    name: $newTagGroupName,
                    onCancel: {
                        showAddTagGroupPopover = false
                    },
                    onCreate: {
                        if viewModel.quickCreateTagGroup(name: newTagGroupName) {
                            newTagGroupName = ""
                            showAddTagGroupPopover = false
                        }
                    }
                )
            }
        }
    }

    private var variableSectionHeader: some View {
        HStack {
            Text("Variable Settings")
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            if propertyViewModel != nil {
                Button {
                    showAddVariableSheet = true
                } label: {
                    Label("Add Variable", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func header(title: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            Spacer()
        }
    }

    private var adaptiveColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 8)]
    }

    private func contentUnavailable(message: String) -> some View {
        HStack {
            Image(systemName: "minus.circle")
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
    }

    private func attemptCreateTag(for group: TagGroup?) {
        let key = tagEntryKey(for: group)
        let name = newTagNames[key, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if viewModel.quickCreateTag(name: name, in: group) {
            newTagNames[key] = ""
        }
    }

    private func tagEntryKey(for group: TagGroup?) -> String {
        group?.id.uuidString ?? "ungrouped"
    }
}

// MARK: - Variable Value Section (reusable)

struct VariableValueSectionView: View {
    @Bindable var viewModel: TagVariableAssignmentViewModel

    private var selectedList: [Variable] {
        viewModel.availableVariables.filter { $0.type == .list && viewModel.selectedVariableIDs.contains($0.id) }
    }

    private var selectedInt: [Variable] {
        viewModel.availableVariables.filter { $0.type == .int && viewModel.selectedVariableIDs.contains($0.id) }
    }

    private var adaptiveColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 12)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if selectedList.isEmpty && selectedInt.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("Select at least one variable to set its value.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            if !selectedList.isEmpty {
                Text("List Variables")
                    .font(.headline)
                LazyVGrid(columns: adaptiveColumns, spacing: 12) {
                    ForEach(selectedList) { variable in
                        VariableListRow(
                            variable: variable,
                            selected: viewModel.variableValues[variable.id]?.listValue,
                            onChange: { newValue in
                                viewModel.updateVariable(variable, listValue: newValue)
                            }
                        )
                    }
                }
            }

            if !selectedInt.isEmpty {
                Text("Number Variables")
                    .font(.headline)
                LazyVGrid(columns: adaptiveColumns, spacing: 12) {
                    ForEach(selectedInt) { variable in
                        VariableIntRow(
                            variable: variable,
                            value: viewModel.variableValues[variable.id]?.intValue,
                            onChange: { newValue in
                                viewModel.updateVariable(variable, intValue: newValue)
                            }
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Tag Capsule

private struct TagCapsule: View {
    let tag: Tag
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                Text(tag.name)
                    .font(.callout)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background((Color(hex: tag.color) ?? .blue).opacity(0.12))
            .foregroundStyle(Color(hex: tag.color) ?? .blue)
            .overlay(
                Capsule()
                    .stroke((Color(hex: tag.color) ?? .blue).opacity(0.3), lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct AddTagChip: View {
    @Binding var text: String
    let placeholder: String
    let onCommit: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.circle")
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .submitLabel(.done)
                .onSubmit(onCommit)
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    onCommit()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial)
        .overlay(
            Capsule()
                .stroke(.tertiary, lineWidth: 1)
        )
        .clipShape(Capsule())
    }
}

// MARK: - Variable Rows & Chips

private struct VariableSelectChip: View {
    let variable: Variable
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                VStack(alignment: .leading, spacing: 2) {
                    Text(variable.name)
                        .font(.callout)
                        .fontWeight(.medium)
                    Text(variable.type == .int ? "Number" : "List")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background((Color(hex: variable.color) ?? .purple).opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke((Color(hex: variable.color) ?? .purple).opacity(isSelected ? 0.5 : 0.25), lineWidth: isSelected ? 1.2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(hex: variable.color) ?? .primary)
    }
}

private struct VariableListRow: View {
    let variable: Variable
    let selected: String?
    let onChange: (String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: variable.color) ?? .purple)
                    .frame(width: 8, height: 8)
                Text(variable.name)
                    .font(.callout)
                    .fontWeight(.medium)
                Spacer()
            }

            Menu {
                Button("Clear") {
                    onChange(nil)
                }
                Divider()
                if let options = variable.listOptions {
                    ForEach(options, id: \.self) { option in
                        Button(option) {
                            onChange(option)
                        }
                    }
                }
            } label: {
                HStack {
                    Text(selected ?? "Select")
                        .foregroundStyle(selected == nil ? .secondary : (Color(hex: variable.color) ?? .primary))
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background((Color(hex: variable.color) ?? .purple).opacity(0.08))
                .overlay(
                    Capsule()
                        .stroke((Color(hex: variable.color) ?? .purple).opacity(0.25), lineWidth: 1)
                )
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct VariableIntRow: View {
    let variable: Variable
    let value: Int?
    let onChange: (Int?) -> Void

    @State private var textValue: String = ""

    init(variable: Variable, value: Int?, onChange: @escaping (Int?) -> Void) {
        self.variable = variable
        self.value = value
        self.onChange = onChange
        _textValue = State(initialValue: value.map { String($0) } ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: variable.color) ?? .purple)
                    .frame(width: 8, height: 8)
                Text(variable.name)
                    .font(.subheadline)
                Spacer()
            }

            HStack {
                TextField("Value", text: $textValue)
                    .keyboardType(.numberPad)
                    .onChange(of: textValue) { newValue in
                        let cleaned = Int(newValue)
                        onChange(cleaned)
                    }
                    .textFieldStyle(.roundedBorder)

                Stepper("", value: Binding(
                    get: { value ?? 0 },
                    set: { newValue in
                        textValue = String(newValue)
                        onChange(newValue)
                    }
                ))
                .labelsHidden()
            }
        }
        .padding(10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onChange(of: value) { newValue in
            textValue = newValue.map(String.init) ?? ""
        }
    }
}

// MARK: - Flow Layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y),
                proposal: .unspecified
            )
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: currentX, y: currentY))
                currentX += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }

            self.size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}

// MARK: - Quick Add Popover

private struct TagGroupQuickAddPopover: View {
    @Binding var name: String
    let onCancel: () -> Void
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Tag Group")
                .font(.headline)
            TextField("Group Name", text: $name)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Add") {
                    onCreate()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 260)
    }
}
