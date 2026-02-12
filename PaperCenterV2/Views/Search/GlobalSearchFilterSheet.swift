//
//  GlobalSearchFilterSheet.swift
//  PaperCenterV2
//
//  Advanced filter editor for global search.
//

import SwiftData
import SwiftUI

struct GlobalSearchFilterSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Tag.sortIndex) private var tags: [Tag]
    @Query(sort: \Variable.sortIndex) private var variables: [Variable]

    @State private var draft: GlobalSearchOptions

    let onApply: (GlobalSearchOptions) -> Void

    init(
        options: GlobalSearchOptions,
        onApply: @escaping (GlobalSearchOptions) -> Void
    ) {
        _draft = State(initialValue: options)
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            Form {
                fieldScopeSection
                resultTypeSection
                tagFilterSection
                variableFilterSection
                utilitySection
            }
            .navigationTitle("Search Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(draft)
                        dismiss()
                    }
                }
            }
        }
    }

    private var fieldScopeSection: some View {
        Section("Search Scope") {
            ForEach(GlobalSearchField.allCases) { field in
                Toggle(isOn: bindingForField(field)) {
                    Text(field.title)
                }
            }

            Toggle("Include Historical Versions", isOn: $draft.includeHistoricalVersions)

            Stepper("Max Results: \(draft.maxResults)", value: $draft.maxResults, in: 20...500, step: 20)
        }
    }

    private var resultTypeSection: some View {
        Section("Result Types") {
            ForEach(GlobalSearchResultKind.allCases) { type in
                Toggle(isOn: bindingForResultType(type)) {
                    Label(type.title, systemImage: type.icon)
                }
            }
        }
    }

    private var tagFilterSection: some View {
        Section("Tag Filter") {
            TextField("Tag name keyword", text: $draft.tagFilter.nameKeyword)
                .textInputAutocapitalization(.never)

            Picker("Tag Logic", selection: $draft.tagFilter.mode) {
                ForEach(TagFilterMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if tags.isEmpty {
                Text("No tags available")
                    .foregroundStyle(.secondary)
            } else {
                SwiftUI.ForEach(tags.sortedByManualOrder(), id: \.id) { (tag: Tag) in
                    Button {
                        toggleSelectedTag(tag.id)
                    } label: {
                        HStack {
                            Circle()
                                .fill(Color(hex: tag.color))
                                .frame(width: 10, height: 10)

                            Text(tag.name)
                                .foregroundStyle(.primary)

                            Spacer()

                            if draft.tagFilter.selectedTagIDs.contains(tag.id) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("globalSearch.tag.\(tag.id.uuidString)")
                }
            }
        }
    }

    private var variableFilterSection: some View {
        Section("Variable Rules") {
            Picker("Rule Logic", selection: $draft.variableRulesMode) {
                ForEach(FilterLogicalMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if draft.variableRules.isEmpty {
                Text("No variable rules")
                    .foregroundStyle(.secondary)
            } else {
                ForEach($draft.variableRules) { $rule in
                    VariableRuleEditorRow(
                        rule: $rule,
                        variables: variables.sortedByManualOrder()
                    ) {
                        removeRule(rule.id)
                    }
                }
            }

            Button {
                addRule()
            } label: {
                Label("Add Rule", systemImage: "plus.circle")
            }
            .disabled(variables.isEmpty)
            .accessibilityIdentifier("globalSearch.addVariableRule")
        }
    }

    private var utilitySection: some View {
        Section {
            Button("Select All Scope + Types") {
                draft.fieldScope = Set(GlobalSearchField.allCases)
                draft.resultTypes = Set(GlobalSearchResultKind.allCases)
            }

            Button("Reset to Defaults") {
                draft = .default
            }
        }
    }

    private func bindingForField(_ field: GlobalSearchField) -> Binding<Bool> {
        Binding(
            get: { draft.fieldScope.contains(field) },
            set: { isOn in
                if isOn {
                    draft.fieldScope.insert(field)
                } else {
                    draft.fieldScope.remove(field)
                }
            }
        )
    }

    private func bindingForResultType(_ type: GlobalSearchResultKind) -> Binding<Bool> {
        Binding(
            get: { draft.resultTypes.contains(type) },
            set: { isOn in
                if isOn {
                    draft.resultTypes.insert(type)
                } else {
                    draft.resultTypes.remove(type)
                }
            }
        )
    }

    private func toggleSelectedTag(_ tagID: UUID) {
        if draft.tagFilter.selectedTagIDs.contains(tagID) {
            draft.tagFilter.selectedTagIDs.remove(tagID)
        } else {
            draft.tagFilter.selectedTagIDs.insert(tagID)
        }
    }

    private func addRule() {
        guard let variable = variables.sortedByManualOrder().first else {
            return
        }

        let op = VariableFilterOperator.defaultOperator(for: variable.type)
        let value = defaultValue(for: variable, op: op)
        let rule = VariableFilterRule(variableID: variable.id, operator: op, value: value)
        draft.variableRules.append(rule)
    }

    private func removeRule(_ id: UUID) {
        draft.variableRules.removeAll { $0.id == id }
    }

    private func defaultValue(for variable: Variable, op: VariableFilterOperator) -> VariableFilterValue? {
        guard op.needsValue else {
            return nil
        }

        switch (variable.type, op) {
        case (.int, .between):
            return .intRange(min: 0, max: 0, lowerInclusion: .closed, upperInclusion: .closed)
        case (.int, _):
            return .int(0)
        case (.date, .between):
            let now = Date()
            return .dateRange(min: now, max: now, lowerInclusion: .closed, upperInclusion: .closed)
        case (.date, _):
            return .date(Date())
        case (.text, _):
            return .text("")
        case (.list, _):
            return .list([])
        }
    }
}

private struct VariableRuleEditorRow: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Binding var rule: VariableFilterRule

    let variables: [Variable]
    let onRemove: () -> Void

    private var selectedVariable: Variable? {
        variables.first(where: { $0.id == rule.variableID })
    }

    private var availableOperators: [VariableFilterOperator] {
        guard let selectedVariable else { return [] }
        return VariableFilterOperator.allowed(for: selectedVariable.type)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Variable", selection: $rule.variableID) {
                    ForEach(variables) { variable in
                        Text(variable.name)
                            .tag(variable.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
            }

            if !availableOperators.isEmpty {
                Picker("Operator", selection: $rule.operator) {
                    ForEach(availableOperators) { op in
                        Text(op.title).tag(op)
                    }
                }
                .pickerStyle(.menu)
            }

            if let selectedVariable {
                valueEditor(for: selectedVariable)
            }
        }
        .padding(.vertical, 4)
        .padding(8)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        .onAppear {
            normalizeRule()
        }
        .onChange(of: rule.variableID) { _, _ in
            normalizeRule()
        }
        .onChange(of: rule.operator) { _, _ in
            normalizeRule()
        }
    }

    @ViewBuilder
    private func valueEditor(for variable: Variable) -> some View {
        if !rule.operator.needsValue {
            EmptyView()
        } else {
            switch variable.type {
            case .int:
                intValueEditor
            case .date:
                dateValueEditor
            case .text:
                textValueEditor
            case .list:
                listValueEditor(for: variable)
            }
        }
    }

    private var intValueEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            if rule.operator == .between {
                HStack(spacing: 8) {
                    TextField("Min", value: intRangeMinBinding, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .frame(maxWidth: .infinity)
                    TextField("Max", value: intRangeMaxBinding, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .frame(maxWidth: .infinity)
                }

                rangeInclusionEditor(
                    lowerTitle: "Lower Bound",
                    upperTitle: "Upper Bound",
                    lowerBinding: intRangeLowerBinding,
                    upperBinding: intRangeUpperBinding
                )
            } else {
                TextField("Value", value: intValueBinding, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
            }
        }
    }

    private var dateValueEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            if rule.operator == .between {
                DatePicker("From", selection: dateRangeMinBinding, displayedComponents: [.date])
                DatePicker("To", selection: dateRangeMaxBinding, displayedComponents: [.date])

                rangeInclusionEditor(
                    lowerTitle: "Lower Bound",
                    upperTitle: "Upper Bound",
                    lowerBinding: dateRangeLowerBinding,
                    upperBinding: dateRangeUpperBinding
                )
            } else {
                DatePicker("Date", selection: dateValueBinding, displayedComponents: [.date])
            }
        }
    }

    private var textValueEditor: some View {
        TextField("Text", text: textValueBinding)
            .textFieldStyle(.roundedBorder)
    }

    @ViewBuilder
    private func listValueEditor(for variable: Variable) -> some View {
        let options = variable.listOptions ?? []
        if options.isEmpty {
            TextField("Comma separated values", text: listCSVBinding)
                .textFieldStyle(.roundedBorder)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                SwiftUI.ForEach(options, id: \.self) { (option: String) in
                    Button {
                        toggleListOption(option)
                    } label: {
                        HStack {
                            Text(option)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedListValues.contains(option) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var intValueBinding: Binding<Int> {
        Binding(
            get: {
                if case .int(let value)? = rule.value {
                    return value
                }
                return 0
            },
            set: { newValue in
                rule.value = .int(newValue)
            }
        )
    }

    private var intRangeMinBinding: Binding<Int> {
        Binding(
            get: {
                if case .intRange(let min, _, _, _)? = rule.value {
                    return min
                }
                return 0
            },
            set: { newValue in
                let current = intRangeTuple
                rule.value = .intRange(
                    min: newValue,
                    max: current.max,
                    lowerInclusion: current.lower,
                    upperInclusion: current.upper
                )
            }
        )
    }

    private var intRangeMaxBinding: Binding<Int> {
        Binding(
            get: {
                if case .intRange(_, let max, _, _)? = rule.value {
                    return max
                }
                return 0
            },
            set: { newValue in
                let current = intRangeTuple
                rule.value = .intRange(
                    min: current.min,
                    max: newValue,
                    lowerInclusion: current.lower,
                    upperInclusion: current.upper
                )
            }
        )
    }

    private var intRangeLowerBinding: Binding<RangeBoundInclusion> {
        Binding(
            get: { intRangeTuple.lower },
            set: { newValue in
                let current = intRangeTuple
                rule.value = .intRange(
                    min: current.min,
                    max: current.max,
                    lowerInclusion: newValue,
                    upperInclusion: current.upper
                )
            }
        )
    }

    private var intRangeUpperBinding: Binding<RangeBoundInclusion> {
        Binding(
            get: { intRangeTuple.upper },
            set: { newValue in
                let current = intRangeTuple
                rule.value = .intRange(
                    min: current.min,
                    max: current.max,
                    lowerInclusion: current.lower,
                    upperInclusion: newValue
                )
            }
        )
    }

    private var dateValueBinding: Binding<Date> {
        Binding(
            get: {
                if case .date(let value)? = rule.value {
                    return value
                }
                return Date()
            },
            set: { newValue in
                rule.value = .date(newValue)
            }
        )
    }

    private var dateRangeMinBinding: Binding<Date> {
        Binding(
            get: { dateRangeTuple.min },
            set: { newValue in
                let current = dateRangeTuple
                rule.value = .dateRange(
                    min: newValue,
                    max: current.max,
                    lowerInclusion: current.lower,
                    upperInclusion: current.upper
                )
            }
        )
    }

    private var dateRangeMaxBinding: Binding<Date> {
        Binding(
            get: { dateRangeTuple.max },
            set: { newValue in
                let current = dateRangeTuple
                rule.value = .dateRange(
                    min: current.min,
                    max: newValue,
                    lowerInclusion: current.lower,
                    upperInclusion: current.upper
                )
            }
        )
    }

    private var dateRangeLowerBinding: Binding<RangeBoundInclusion> {
        Binding(
            get: { dateRangeTuple.lower },
            set: { newValue in
                let current = dateRangeTuple
                rule.value = .dateRange(
                    min: current.min,
                    max: current.max,
                    lowerInclusion: newValue,
                    upperInclusion: current.upper
                )
            }
        )
    }

    private var dateRangeUpperBinding: Binding<RangeBoundInclusion> {
        Binding(
            get: { dateRangeTuple.upper },
            set: { newValue in
                let current = dateRangeTuple
                rule.value = .dateRange(
                    min: current.min,
                    max: current.max,
                    lowerInclusion: current.lower,
                    upperInclusion: newValue
                )
            }
        )
    }

    private var textValueBinding: Binding<String> {
        Binding(
            get: {
                if case .text(let value)? = rule.value {
                    return value
                }
                return ""
            },
            set: { newValue in
                rule.value = .text(newValue)
            }
        )
    }

    private var listCSVBinding: Binding<String> {
        Binding(
            get: { selectedListValues.joined(separator: ",") },
            set: { newValue in
                let values = newValue
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                rule.value = .list(values)
            }
        )
    }

    private var selectedListValues: [String] {
        if case .list(let values)? = rule.value {
            return values
        }
        return []
    }

    private var intRangeTuple: (min: Int, max: Int, lower: RangeBoundInclusion, upper: RangeBoundInclusion) {
        if case .intRange(let min, let max, let lower, let upper)? = rule.value {
            return (min, max, lower, upper)
        }
        return (0, 0, .closed, .closed)
    }

    private var dateRangeTuple: (min: Date, max: Date, lower: RangeBoundInclusion, upper: RangeBoundInclusion) {
        if case .dateRange(let min, let max, let lower, let upper)? = rule.value {
            return (min, max, lower, upper)
        }
        let now = Date()
        return (now, now, .closed, .closed)
    }

    private func toggleListOption(_ option: String) {
        var values = Set(selectedListValues)
        if values.contains(option) {
            values.remove(option)
        } else {
            values.insert(option)
        }
        rule.value = .list(Array(values).sorted())
    }

    private func normalizeRule() {
        guard let variable = selectedVariable else {
            return
        }

        let allowed = VariableFilterOperator.allowed(for: variable.type)
        if !allowed.contains(rule.operator), let first = allowed.first {
            rule.operator = first
        }

        if !rule.operator.needsValue {
            rule.value = nil
            return
        }

        if rule.value == nil {
            rule.value = defaultValue(for: variable, op: rule.operator)
            return
        }

        if !isValueCompatible(variableType: variable.type, op: rule.operator, value: rule.value) {
            rule.value = defaultValue(for: variable, op: rule.operator)
        }
    }

    @ViewBuilder
    private func rangeInclusionEditor(
        lowerTitle: String,
        upperTitle: String,
        lowerBinding: Binding<RangeBoundInclusion>,
        upperBinding: Binding<RangeBoundInclusion>
    ) -> some View {
        if horizontalSizeClass == .regular {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(lowerTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker(lowerTitle, selection: lowerBinding) {
                        ForEach(RangeBoundInclusion.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(upperTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker(upperTitle, selection: upperBinding) {
                        ForEach(RangeBoundInclusion.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(lowerTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker(lowerTitle, selection: lowerBinding) {
                    ForEach(RangeBoundInclusion.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(upperTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker(upperTitle, selection: upperBinding) {
                    ForEach(RangeBoundInclusion.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private func defaultValue(for variable: Variable, op: VariableFilterOperator) -> VariableFilterValue? {
        guard op.needsValue else {
            return nil
        }

        switch (variable.type, op) {
        case (.int, .between):
            return .intRange(min: 0, max: 0, lowerInclusion: .closed, upperInclusion: .closed)
        case (.int, _):
            return .int(0)
        case (.date, .between):
            let now = Date()
            return .dateRange(min: now, max: now, lowerInclusion: .closed, upperInclusion: .closed)
        case (.date, _):
            return .date(Date())
        case (.text, _):
            return .text("")
        case (.list, _):
            return .list([])
        }
    }

    private func isValueCompatible(
        variableType: VariableType,
        op: VariableFilterOperator,
        value: VariableFilterValue?
    ) -> Bool {
        guard let value else {
            return !op.needsValue
        }

        switch (variableType, op, value) {
        case (.int, .between, .intRange(_, _, _, _)):
            return true
        case (.int, _, .int(_)):
            return op != .between

        case (.date, .between, .dateRange(_, _, _, _)):
            return true
        case (.date, _, .date(_)):
            return op != .between

        case (.text, _, .text(_)):
            return true
        case (.list, _, .list(_)):
            return true
        default:
            return false
        }
    }
}
