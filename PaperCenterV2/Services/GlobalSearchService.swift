//
//  GlobalSearchService.swift
//  PaperCenterV2
//
//  Global search engine with structured tag/variable filters.
//

import Foundation
import SwiftData

@MainActor
final class GlobalSearchService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func search(query: String, options: GlobalSearchOptions) -> [GlobalSearchResult] {
        let normalizedQuery = Self.normalize(query)
        let tokens = Self.tokenize(normalizedQuery)

        if tokens.isEmpty && !options.hasStructuredFilters {
            return []
        }

        do {
            let tags = try modelContext.fetch(FetchDescriptor<Tag>())
            let variables = try modelContext.fetch(FetchDescriptor<Variable>())
            let docs = try modelContext.fetch(FetchDescriptor<Doc>())
            let bundles = try modelContext.fetch(FetchDescriptor<PDFBundle>())
            let notes = try modelContext.fetch(
                FetchDescriptor<NoteBlock>(
                    predicate: #Predicate { note in
                        note.isDeleted == false
                    }
                )
            )

            let tagByID = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
            let variableByID = Dictionary(uniqueKeysWithValues: variables.map { ($0.id, $0) })
            let bundleByID = Dictionary(uniqueKeysWithValues: bundles.map { ($0.id, $0) })

            let context = BuildContext(
                tagByID: tagByID,
                variableByID: variableByID,
                bundleByID: bundleByID,
                normalizedQuery: normalizedQuery,
                tokens: tokens,
                options: options
            )

            var candidates: [SearchCandidate] = []
            var pageByID: [UUID: Page] = [:]
            var pageByVersionID: [UUID: Page] = [:]
            var docPageNumberByPageID: [UUID: Int] = [:]
            var docByID: [UUID: Doc] = [:]

            for doc in docs {
                docByID[doc.id] = doc
                let firstPageInDoc = doc.orderedPageGroups.first?.orderedPages.first
                candidates.append(
                    buildDocCandidate(
                        doc: doc,
                        firstLogicalPageID: firstPageInDoc?.id,
                        firstDocPageNumber: firstPageInDoc == nil ? nil : 1,
                        context: context
                    )
                )

                var docPageCounter = 0

                for pageGroup in doc.orderedPageGroups {
                    let firstPageNumberInGroup: Int? = pageGroup.orderedPages.isEmpty ? nil : docPageCounter + 1
                    candidates.append(
                        buildPageGroupCandidate(
                            doc: doc,
                            pageGroup: pageGroup,
                            firstDocPageNumber: firstPageNumberInGroup,
                            context: context
                        )
                    )

                    for page in pageGroup.orderedPages {
                        docPageCounter += 1
                        docPageNumberByPageID[page.id] = docPageCounter
                        pageByID[page.id] = page
                        let versions = filteredVersions(for: page, includeHistorical: options.includeHistoricalVersions)

                        candidates.append(
                            buildPageCandidate(
                                doc: doc,
                                pageGroup: pageGroup,
                                page: page,
                                docPageNumber: docPageCounter,
                                versions: versions,
                                context: context
                            )
                        )

                        for version in versions {
                            pageByVersionID[version.id] = page

                            if let ocrCandidate = buildOCRCandidate(
                                doc: doc,
                                pageGroup: pageGroup,
                                page: page,
                                docPageNumber: docPageCounter,
                                version: version,
                                context: context
                            ) {
                                candidates.append(ocrCandidate)
                            }

                            if let metadataCandidate = buildVersionMetadataCandidate(
                                doc: doc,
                                pageGroup: pageGroup,
                                page: page,
                                docPageNumber: docPageCounter,
                                version: version,
                                context: context
                            ) {
                                candidates.append(metadataCandidate)
                            }
                        }
                    }
                }
            }

            for note in notes {
                guard let candidate = buildNoteCandidate(
                    note: note,
                    docByID: docByID,
                    pageByID: pageByID,
                    pageByVersionID: pageByVersionID,
                    docPageNumberByPageID: docPageNumberByPageID,
                    context: context
                ) else {
                    continue
                }
                candidates.append(candidate)
            }

            let results = candidates.compactMap { candidate -> GlobalSearchResult? in
                guard tagFilterMatch(
                    candidateTagIDs: candidate.tagIDs,
                    candidateTagNames: candidate.tagNames,
                    filter: options.tagFilter
                ) else {
                    return nil
                }

                guard variableFilterMatch(
                    candidateVariableValues: candidate.variableValues,
                    variableByID: variableByID,
                    options: options
                ) else {
                    return nil
                }

                let textMatch = textQueryMatch(
                    candidate: candidate,
                    tokens: tokens,
                    normalizedQuery: normalizedQuery,
                    fieldScope: options.fieldScope
                )
                guard textMatch.isMatch else {
                    return nil
                }

                guard options.resultTypes.contains(candidate.kind) else {
                    return nil
                }

                let score = score(
                    candidate: candidate,
                    matchedFields: textMatch.matchedFields,
                    phraseMatched: textMatch.phraseMatched
                )

                return GlobalSearchResult(
                    id: candidate.stableID,
                    kind: candidate.kind,
                    matchedFields: textMatch.matchedFields,
                    score: score,
                    docID: candidate.docID,
                    docTitle: candidate.docTitle,
                    pageGroupID: candidate.pageGroupID,
                    pageGroupTitle: candidate.pageGroupTitle,
                    logicalPageID: candidate.logicalPageID,
                    docPageNumber: candidate.docPageNumber,
                    pageVersionID: candidate.pageVersionID,
                    noteID: candidate.noteID,
                    title: candidate.title,
                    subtitle: candidate.subtitle,
                    snippet: candidate.snippet
                )
            }

            return Array(
                results.sorted(by: { lhs, rhs in
                    if lhs.score != rhs.score {
                        return lhs.score > rhs.score
                    }
                    if lhs.docTitle != rhs.docTitle {
                        return lhs.docTitle.localizedCaseInsensitiveCompare(rhs.docTitle) == .orderedAscending
                    }
                    return lhs.id < rhs.id
                })
                .prefix(max(options.maxResults, 1))
            )
        } catch {
            return []
        }
    }

    private func buildDocCandidate(
        doc: Doc,
        firstLogicalPageID: UUID?,
        firstDocPageNumber: Int?,
        context: BuildContext
    ) -> SearchCandidate {
        let tagInfo = tagInfo(from: doc.tags, tagByID: context.tagByID)
        let variableValues = variableValues(
            from: doc.variableAssignments,
            variableID: { $0.variable?.id },
            intValue: { $0.intValue },
            listValue: { $0.listValue },
            textValue: { $0.textValue },
            dateValue: { $0.dateValue }
        )

        let variableText = variableText(
            valuesByVariableID: variableValues,
            variableByID: context.variableByID
        )

        var textByField: [GlobalSearchField: [String]] = [:]
        append(doc.title, to: &textByField, field: .docTitle)
        append(contentsOf: tagInfo.names, to: &textByField, field: .tagName)
        append(contentsOf: variableText.names, to: &textByField, field: .variableName)
        append(contentsOf: variableText.values, to: &textByField, field: .variableValue)

        return SearchCandidate(
            kind: .doc,
            docID: doc.id,
            docTitle: doc.title,
            pageGroupID: nil,
            pageGroupTitle: nil,
            logicalPageID: firstLogicalPageID,
            docPageNumber: firstDocPageNumber,
            pageVersionID: nil,
            noteID: nil,
            title: doc.title,
            subtitle: "Document",
            snippet: makeSnippet(from: [doc.title] + tagInfo.names + variableText.values),
            sortDate: doc.updatedAt,
            textByField: textByField,
            tagIDs: tagInfo.ids,
            tagNames: tagInfo.names,
            variableValues: variableValues
        )
    }

    private func buildPageGroupCandidate(
        doc: Doc,
        pageGroup: PageGroup,
        firstDocPageNumber: Int?,
        context: BuildContext
    ) -> SearchCandidate {
        let tagInfo = tagInfo(from: pageGroup.tags, tagByID: context.tagByID)
        let variableValues = variableValues(
            from: pageGroup.variableAssignments,
            variableID: { $0.variable?.id },
            intValue: { $0.intValue },
            listValue: { $0.listValue },
            textValue: { $0.textValue },
            dateValue: { $0.dateValue }
        )
        let variableText = variableText(
            valuesByVariableID: variableValues,
            variableByID: context.variableByID
        )

        var textByField: [GlobalSearchField: [String]] = [:]
        append(pageGroup.title, to: &textByField, field: .pageGroupTitle)
        append(contentsOf: tagInfo.names, to: &textByField, field: .tagName)
        append(contentsOf: variableText.names, to: &textByField, field: .variableName)
        append(contentsOf: variableText.values, to: &textByField, field: .variableValue)

        return SearchCandidate(
            kind: .pageGroup,
            docID: doc.id,
            docTitle: doc.title,
            pageGroupID: pageGroup.id,
            pageGroupTitle: pageGroup.title,
            logicalPageID: pageGroup.orderedPages.first?.id,
            docPageNumber: firstDocPageNumber,
            pageVersionID: nil,
            noteID: nil,
            title: pageGroup.title,
            subtitle: doc.title,
            snippet: makeSnippet(from: tagInfo.names + variableText.values),
            sortDate: pageGroup.updatedAt,
            textByField: textByField,
            tagIDs: tagInfo.ids,
            tagNames: tagInfo.names,
            variableValues: variableValues
        )
    }

    private func buildPageCandidate(
        doc: Doc,
        pageGroup: PageGroup,
        page: Page,
        docPageNumber: Int,
        versions: [PageVersion],
        context: BuildContext
    ) -> SearchCandidate {
        let tagInfo = tagInfo(from: page.tags, tagByID: context.tagByID)
        let variableValues = variableValues(
            from: page.variableAssignments,
            variableID: { $0.variable?.id },
            intValue: { $0.intValue },
            listValue: { $0.listValue },
            textValue: { $0.textValue },
            dateValue: { $0.dateValue }
        )
        var snapshotValues: [UUID: [CandidateVariableValue]] = [:]
        for version in versions {
            let snapshot = try? version.decodeMetadataSnapshot()
            let values = snapshotVariableValues(from: snapshot)
            snapshotValues = merge(snapshotValues, values)
        }

        let mergedVariableValues = merge(variableValues, snapshotValues)
        let variableText = variableText(
            valuesByVariableID: mergedVariableValues,
            variableByID: context.variableByID
        )

        var textByField: [GlobalSearchField: [String]] = [:]
        append(contentsOf: tagInfo.names, to: &textByField, field: .tagName)
        append(contentsOf: variableText.names, to: &textByField, field: .variableName)
        append(contentsOf: variableText.values, to: &textByField, field: .variableValue)

        return SearchCandidate(
            kind: .page,
            docID: doc.id,
            docTitle: doc.title,
            pageGroupID: pageGroup.id,
            pageGroupTitle: pageGroup.title,
            logicalPageID: page.id,
            docPageNumber: docPageNumber,
            pageVersionID: page.latestVersion?.id,
            noteID: nil,
            title: "Page \(docPageNumber)",
            subtitle: "\(doc.title) · \(pageGroup.title)",
            snippet: makeSnippet(from: tagInfo.names + variableText.values),
            sortDate: page.updatedAt,
            textByField: textByField,
            tagIDs: tagInfo.ids,
            tagNames: tagInfo.names,
            variableValues: mergedVariableValues
        )
    }

    private func buildOCRCandidate(
        doc: Doc,
        pageGroup: PageGroup,
        page: Page,
        docPageNumber: Int,
        version: PageVersion,
        context: BuildContext
    ) -> SearchCandidate? {
        guard let bundle = context.bundleByID[version.pdfBundleID],
              let ocrText = bundle.ocrTextByPage[version.pageNumber],
              !ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let currentTagInfo = tagInfo(from: page.tags, tagByID: context.tagByID)
        let currentValues = variableValues(
            from: page.variableAssignments,
            variableID: { $0.variable?.id },
            intValue: { $0.intValue },
            listValue: { $0.listValue },
            textValue: { $0.textValue },
            dateValue: { $0.dateValue }
        )

        let snapshot = try? version.decodeMetadataSnapshot()
        let snapshotTagInfo = snapshotTagInfo(from: snapshot, tagByID: context.tagByID)
        let snapshotValues = snapshotVariableValues(from: snapshot)

        let mergedTagIDs = currentTagInfo.ids.union(snapshotTagInfo.ids)
        let mergedTagNames = Array(Set(currentTagInfo.names + snapshotTagInfo.names)).sorted()
        let mergedVariableValues = merge(
            currentValues,
            snapshotValues
        )

        let variableText = variableText(
            valuesByVariableID: mergedVariableValues,
            variableByID: context.variableByID
        )

        var textByField: [GlobalSearchField: [String]] = [:]
        append(ocrText, to: &textByField, field: .ocrText)
        append(contentsOf: mergedTagNames, to: &textByField, field: .tagName)
        append(contentsOf: variableText.names, to: &textByField, field: .variableName)
        append(contentsOf: variableText.values, to: &textByField, field: .variableValue)

        return SearchCandidate(
            kind: .ocrHit,
            docID: doc.id,
            docTitle: doc.title,
            pageGroupID: pageGroup.id,
            pageGroupTitle: pageGroup.title,
            logicalPageID: page.id,
            docPageNumber: docPageNumber,
            pageVersionID: version.id,
            noteID: nil,
            title: "OCR · Page \(docPageNumber)",
            subtitle: "\(doc.title) · \(pageGroup.title)",
            snippet: makeSnippet(from: [ocrText]),
            sortDate: version.createdAt,
            textByField: textByField,
            tagIDs: mergedTagIDs,
            tagNames: mergedTagNames,
            variableValues: mergedVariableValues
        )
    }

    private func buildVersionMetadataCandidate(
        doc: Doc,
        pageGroup: PageGroup,
        page: Page,
        docPageNumber: Int,
        version: PageVersion,
        context: BuildContext
    ) -> SearchCandidate? {
        guard let snapshot = try? version.decodeMetadataSnapshot() else {
            return nil
        }

        let snapshotTagInfo = snapshotTagInfo(from: snapshot, tagByID: context.tagByID)
        let snapshotValues = snapshotVariableValues(from: snapshot)

        guard !snapshotTagInfo.ids.isEmpty || !snapshotValues.isEmpty else {
            return nil
        }

        let variableText = variableText(
            valuesByVariableID: snapshotValues,
            variableByID: context.variableByID
        )
        let metadataText = snapshotTagInfo.names + variableText.names + variableText.values

        var textByField: [GlobalSearchField: [String]] = [:]
        append(contentsOf: metadataText, to: &textByField, field: .versionSnapshotMetadata)
        append(contentsOf: snapshotTagInfo.names, to: &textByField, field: .tagName)
        append(contentsOf: variableText.names, to: &textByField, field: .variableName)
        append(contentsOf: variableText.values, to: &textByField, field: .variableValue)

        return SearchCandidate(
            kind: .versionMetadataHit,
            docID: doc.id,
            docTitle: doc.title,
            pageGroupID: pageGroup.id,
            pageGroupTitle: pageGroup.title,
            logicalPageID: page.id,
            docPageNumber: docPageNumber,
            pageVersionID: version.id,
            noteID: nil,
            title: "Version Metadata · Page \(docPageNumber)",
            subtitle: "\(doc.title) · \(pageGroup.title)",
            snippet: makeSnippet(from: metadataText),
            sortDate: version.createdAt,
            textByField: textByField,
            tagIDs: snapshotTagInfo.ids,
            tagNames: snapshotTagInfo.names,
            variableValues: snapshotValues
        )
    }

    private func buildNoteCandidate(
        note: NoteBlock,
        docByID: [UUID: Doc],
        pageByID: [UUID: Page],
        pageByVersionID: [UUID: Page],
        docPageNumberByPageID: [UUID: Int],
        context: BuildContext
    ) -> SearchCandidate? {
        let resolvedPage = note.pageId.flatMap { pageByID[$0] } ?? pageByVersionID[note.pageVersionID]
        let resolvedDocID = note.docId ?? resolvedPage?.pageGroup?.doc?.id

        guard let docID = resolvedDocID,
              let doc = docByID[docID] else {
            return nil
        }

        let tagInfo = tagInfo(from: note.tags, tagByID: context.tagByID)
        let variableValues = variableValues(
            from: note.variableAssignments,
            variableID: { $0.variable?.id },
            intValue: { $0.intValue },
            listValue: { $0.listValue },
            textValue: { $0.textValue },
            dateValue: { $0.dateValue }
        )
        let variableText = variableText(
            valuesByVariableID: variableValues,
            variableByID: context.variableByID
        )

        var textByField: [GlobalSearchField: [String]] = [:]
        append(note.title, to: &textByField, field: .noteTitleBody)
        append(note.body, to: &textByField, field: .noteTitleBody)
        append(contentsOf: tagInfo.names, to: &textByField, field: .tagName)
        append(contentsOf: variableText.names, to: &textByField, field: .variableName)
        append(contentsOf: variableText.values, to: &textByField, field: .variableValue)

        let docPageNumber = resolvedPage.flatMap { docPageNumberByPageID[$0.id] }
        let pageLabel = docPageNumber.map { "Page \($0)" } ?? "Page"
        let groupTitle = resolvedPage?.pageGroup?.title

        return SearchCandidate(
            kind: .noteHit,
            docID: doc.id,
            docTitle: doc.title,
            pageGroupID: resolvedPage?.pageGroup?.id,
            pageGroupTitle: groupTitle,
            logicalPageID: resolvedPage?.id,
            docPageNumber: docPageNumber,
            pageVersionID: note.pageVersionID,
            noteID: note.id,
            title: note.title?.isEmpty == false ? note.title! : "Note",
            subtitle: "\(doc.title) · \(pageLabel)",
            snippet: makeSnippet(from: [note.body]),
            sortDate: note.updatedAt,
            textByField: textByField,
            tagIDs: tagInfo.ids,
            tagNames: tagInfo.names,
            variableValues: variableValues
        )
    }

    private func filteredVersions(for page: Page, includeHistorical: Bool) -> [PageVersion] {
        let versions = (page.versions ?? []).sorted { lhs, rhs in
            lhs.createdAt < rhs.createdAt
        }

        guard !versions.isEmpty else {
            return []
        }

        if includeHistorical {
            return versions
        }

        if let matched = versions.first(where: { version in
            version.pdfBundleID == page.currentPDFBundleID &&
            version.pageNumber == page.currentPageNumber
        }) {
            return [matched]
        }

        if let latest = versions.max(by: { $0.createdAt < $1.createdAt }) {
            return [latest]
        }

        return [versions[versions.count - 1]]
    }

    private func textQueryMatch(
        candidate: SearchCandidate,
        tokens: [String],
        normalizedQuery: String,
        fieldScope: Set<GlobalSearchField>
    ) -> (isMatch: Bool, matchedFields: Set<GlobalSearchField>, phraseMatched: Bool) {
        guard !tokens.isEmpty else {
            return (true, [], false)
        }

        guard !fieldScope.isEmpty else {
            return (false, [], false)
        }

        var matchedFields: Set<GlobalSearchField> = []
        var phraseMatched = false

        for token in tokens {
            var tokenMatched = false

            for field in fieldScope {
                guard let sources = candidate.textByField[field], !sources.isEmpty else {
                    continue
                }

                for source in sources {
                    let normalized = Self.normalize(source)
                    if normalized.contains(token) {
                        tokenMatched = true
                        matchedFields.insert(field)

                        if !normalizedQuery.isEmpty, normalized.contains(normalizedQuery) {
                            phraseMatched = true
                        }
                        break
                    }
                }

                if tokenMatched {
                    break
                }
            }

            if !tokenMatched {
                return (false, [], false)
            }
        }

        return (true, matchedFields, phraseMatched)
    }

    private func tagFilterMatch(
        candidateTagIDs: Set<UUID>,
        candidateTagNames: [String],
        filter: TagFilter
    ) -> Bool {
        if !filter.isActive {
            return true
        }

        let trimmedKeyword = filter.nameKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let keywordSatisfied: Bool
        if trimmedKeyword.isEmpty {
            keywordSatisfied = true
        } else {
            let normalizedKeyword = Self.normalize(trimmedKeyword)
            keywordSatisfied = candidateTagNames.contains(where: {
                Self.normalize($0).contains(normalizedKeyword)
            })
        }

        let selectionSatisfied: Bool
        if filter.selectedTagIDs.isEmpty {
            selectionSatisfied = true
        } else {
            switch filter.mode {
            case .any:
                selectionSatisfied = !candidateTagIDs.intersection(filter.selectedTagIDs).isEmpty
            case .all:
                selectionSatisfied = filter.selectedTagIDs.isSubset(of: candidateTagIDs)
            }
        }

        return keywordSatisfied && selectionSatisfied
    }

    private func variableFilterMatch(
        candidateVariableValues: [UUID: [CandidateVariableValue]],
        variableByID: [UUID: Variable],
        options: GlobalSearchOptions
    ) -> Bool {
        guard !options.variableRules.isEmpty else {
            return true
        }

        let evaluations = options.variableRules.map { rule in
            evaluate(
                rule: rule,
                candidateVariableValues: candidateVariableValues,
                variableByID: variableByID
            )
        }

        switch options.variableRulesMode {
        case .and:
            return evaluations.allSatisfy { $0 }
        case .or:
            return evaluations.contains(true)
        }
    }

    private func evaluate(
        rule: VariableFilterRule,
        candidateVariableValues: [UUID: [CandidateVariableValue]],
        variableByID: [UUID: Variable]
    ) -> Bool {
        guard let variable = variableByID[rule.variableID] else {
            return false
        }

        guard VariableFilterOperator.allowed(for: variable.type).contains(rule.operator) else {
            return false
        }

        let values = candidateVariableValues[rule.variableID] ?? []

        switch rule.operator {
        case .isSet:
            return !values.isEmpty

        case .isEmpty:
            return values.isEmpty

        case .eq:
            switch (variable.type, rule.value) {
            case (.int, .int(let target)):
                return values.contains { if case .int(let value) = $0 { return value == target } else { return false } }
            case (.date, .date(let targetDate)):
                let target = startOfDay(targetDate)
                return values.contains { if case .date(let value) = $0 { return startOfDay(value) == target } else { return false } }
            default:
                return false
            }

        case .neq:
            switch (variable.type, rule.value) {
            case (.int, .int(let target)):
                let ints = values.compactMap { if case .int(let value) = $0 { return value } else { return nil } }
                return !ints.isEmpty && ints.allSatisfy { $0 != target }
            case (.date, .date(let targetDate)):
                let target = startOfDay(targetDate)
                let dates = values.compactMap { if case .date(let value) = $0 { return startOfDay(value) } else { return nil } }
                return !dates.isEmpty && dates.allSatisfy { $0 != target }
            default:
                return false
            }

        case .gt:
            switch (variable.type, rule.value) {
            case (.int, .int(let target)):
                return values.contains { if case .int(let value) = $0 { return value > target } else { return false } }
            case (.date, .date(let targetDate)):
                let target = startOfDay(targetDate)
                return values.contains { if case .date(let value) = $0 { return startOfDay(value) > target } else { return false } }
            default:
                return false
            }

        case .gte:
            switch (variable.type, rule.value) {
            case (.int, .int(let target)):
                return values.contains { if case .int(let value) = $0 { return value >= target } else { return false } }
            case (.date, .date(let targetDate)):
                let target = startOfDay(targetDate)
                return values.contains { if case .date(let value) = $0 { return startOfDay(value) >= target } else { return false } }
            default:
                return false
            }

        case .lt:
            switch (variable.type, rule.value) {
            case (.int, .int(let target)):
                return values.contains { if case .int(let value) = $0 { return value < target } else { return false } }
            case (.date, .date(let targetDate)):
                let target = startOfDay(targetDate)
                return values.contains { if case .date(let value) = $0 { return startOfDay(value) < target } else { return false } }
            default:
                return false
            }

        case .lte:
            switch (variable.type, rule.value) {
            case (.int, .int(let target)):
                return values.contains { if case .int(let value) = $0 { return value <= target } else { return false } }
            case (.date, .date(let targetDate)):
                let target = startOfDay(targetDate)
                return values.contains { if case .date(let value) = $0 { return startOfDay(value) <= target } else { return false } }
            default:
                return false
            }

        case .between:
            switch (variable.type, rule.value) {
            case (
                .int,
                .intRange(
                    min: let min,
                    max: let max,
                    lowerInclusion: let lower,
                    upperInclusion: let upper
                )
            ):
                return values.contains {
                    guard case .int(let value) = $0 else { return false }
                    return inRange(value, min: min, max: max, lower: lower, upper: upper)
                }

            case (
                .date,
                .dateRange(
                    min: let min,
                    max: let max,
                    lowerInclusion: let lower,
                    upperInclusion: let upper
                )
            ):
                let minDay = startOfDay(min)
                let maxDay = startOfDay(max)
                return values.contains {
                    guard case .date(let value) = $0 else { return false }
                    return inRange(startOfDay(value), min: minDay, max: maxDay, lower: lower, upper: upper)
                }

            default:
                return false
            }

        case .contains:
            guard case .text(let queryText)? = rule.value else {
                return false
            }
            let target = Self.normalize(queryText)
            guard !target.isEmpty else { return false }
            return values.contains {
                guard case .text(let value) = $0 else { return false }
                return Self.normalize(value).contains(target)
            }

        case .equals:
            guard case .text(let queryText)? = rule.value else {
                return false
            }
            let target = Self.normalize(queryText)
            guard !target.isEmpty else { return false }
            return values.contains {
                guard case .text(let value) = $0 else { return false }
                return Self.normalize(value) == target
            }

        case .in:
            guard case .list(let selected)? = rule.value else {
                return false
            }
            let targets = Set(selected.map(Self.normalize).filter { !$0.isEmpty })
            guard !targets.isEmpty else { return false }

            return values.contains {
                guard case .list(let value) = $0 else { return false }
                return targets.contains(Self.normalize(value))
            }

        case .notIn:
            guard case .list(let selected)? = rule.value else {
                return false
            }
            let targets = Set(selected.map(Self.normalize).filter { !$0.isEmpty })
            guard !targets.isEmpty else { return false }

            let listValues = values.compactMap { value -> String? in
                if case .list(let option) = value {
                    return Self.normalize(option)
                }
                return nil
            }

            return !listValues.isEmpty && listValues.allSatisfy { !targets.contains($0) }
        }
    }

    private func score(
        candidate: SearchCandidate,
        matchedFields: Set<GlobalSearchField>,
        phraseMatched: Bool
    ) -> Int {
        let base: Int
        switch candidate.kind {
        case .doc:
            base = 700
        case .noteHit:
            base = 660
        case .ocrHit:
            base = 620
        case .pageGroup:
            base = 560
        case .page:
            base = 540
        case .versionMetadataHit:
            base = 520
        }

        var score = base + matchedFields.count * 20
        if phraseMatched {
            score += 120
        }
        return score
    }

    private func variableText(
        valuesByVariableID: [UUID: [CandidateVariableValue]],
        variableByID: [UUID: Variable]
    ) -> (names: [String], values: [String]) {
        var names: [String] = []
        var values: [String] = []

        for (variableID, candidates) in valuesByVariableID {
            let name = variableByID[variableID]?.name ?? variableID.uuidString
            names.append(name)

            for candidate in candidates {
                switch candidate {
                case .int(let intValue):
                    values.append(String(intValue))
                case .list(let listValue):
                    values.append(listValue)
                case .text(let textValue):
                    values.append(textValue)
                case .date(let dateValue):
                    values.append(Self.dateFormatter.string(from: dateValue))
                }
            }
        }

        return (Array(Set(names)).sorted(), Array(Set(values)).sorted())
    }

    private func tagInfo(from tags: [Tag]?, tagByID: [UUID: Tag]) -> (ids: Set<UUID>, names: [String]) {
        let ids = Set(tags?.map(\.id) ?? [])
        let names = ids.compactMap { tagByID[$0]?.name }
        return (ids, Array(Set(names)).sorted())
    }

    private func snapshotTagInfo(
        from snapshot: MetadataSnapshot?,
        tagByID: [UUID: Tag]
    ) -> (ids: Set<UUID>, names: [String]) {
        let tagIDs = Set(snapshot?.tagIDs ?? [])
        let names = tagIDs.compactMap { tagByID[$0]?.name }
        return (tagIDs, Array(Set(names)).sorted())
    }

    private func snapshotVariableValues(from snapshot: MetadataSnapshot?) -> [UUID: [CandidateVariableValue]] {
        guard let assignments = snapshot?.variableAssignments else {
            return [:]
        }

        var result: [UUID: [CandidateVariableValue]] = [:]
        for assignment in assignments {
            if let intValue = assignment.intValue {
                result[assignment.variableID, default: []].append(.int(intValue))
            }
            if let listValue = assignment.listValue,
               !listValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result[assignment.variableID, default: []].append(.list(listValue))
            }
            if let textValue = assignment.textValue,
               !textValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result[assignment.variableID, default: []].append(.text(textValue))
            }
            if let dateValue = assignment.dateValue {
                result[assignment.variableID, default: []].append(.date(dateValue))
            }
        }

        return result
    }

    private func variableValues<Assignment>(
        from assignments: [Assignment]?,
        variableID: (Assignment) -> UUID?,
        intValue: (Assignment) -> Int?,
        listValue: (Assignment) -> String?,
        textValue: (Assignment) -> String?,
        dateValue: (Assignment) -> Date?
    ) -> [UUID: [CandidateVariableValue]] {
        guard let assignments else { return [:] }

        var result: [UUID: [CandidateVariableValue]] = [:]

        for assignment in assignments {
            guard let variableID = variableID(assignment) else { continue }

            if let intValue = intValue(assignment) {
                result[variableID, default: []].append(.int(intValue))
            }

            if let listValue = listValue(assignment),
               !listValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result[variableID, default: []].append(.list(listValue))
            }

            if let textValue = textValue(assignment),
               !textValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result[variableID, default: []].append(.text(textValue))
            }

            if let dateValue = dateValue(assignment) {
                result[variableID, default: []].append(.date(dateValue))
            }
        }

        return result
    }

    private func merge(
        _ lhs: [UUID: [CandidateVariableValue]],
        _ rhs: [UUID: [CandidateVariableValue]]
    ) -> [UUID: [CandidateVariableValue]] {
        var merged = lhs
        for (key, values) in rhs {
            merged[key, default: []].append(contentsOf: values)
        }
        return merged
    }

    private func append(_ value: String?, to dictionary: inout [GlobalSearchField: [String]], field: GlobalSearchField) {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        dictionary[field, default: []].append(value)
    }

    private func append(contentsOf values: [String], to dictionary: inout [GlobalSearchField: [String]], field: GlobalSearchField) {
        let cleaned = values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !cleaned.isEmpty else { return }
        dictionary[field, default: []].append(contentsOf: cleaned)
    }

    private func makeSnippet(from texts: [String], maxLength: Int = 180) -> String {
        guard let first = texts.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return ""
        }

        let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= maxLength {
            return trimmed
        }

        let index = trimmed.index(trimmed.startIndex, offsetBy: maxLength)
        return String(trimmed[..<index]) + "…"
    }

    private func inRange<T: Comparable>(
        _ value: T,
        min: T,
        max: T,
        lower: RangeBoundInclusion,
        upper: RangeBoundInclusion
    ) -> Bool {
        let lowerPass: Bool
        switch lower {
        case .open:
            lowerPass = value > min
        case .closed:
            lowerPass = value >= min
        }

        let upperPass: Bool
        switch upper {
        case .open:
            upperPass = value < max
        case .closed:
            upperPass = value <= max
        }

        return lowerPass && upperPass
    }

    private func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tokenize(_ normalized: String) -> [String] {
        if normalized.isEmpty {
            return []
        }

        let tokens = normalized
            .split { $0.isWhitespace || $0.isPunctuation }
            .map(String.init)
            .filter { !$0.isEmpty }

        if tokens.isEmpty {
            return [normalized]
        }
        return tokens
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

private struct BuildContext {
    let tagByID: [UUID: Tag]
    let variableByID: [UUID: Variable]
    let bundleByID: [UUID: PDFBundle]
    let normalizedQuery: String
    let tokens: [String]
    let options: GlobalSearchOptions
}

private enum CandidateVariableValue: Hashable {
    case int(Int)
    case list(String)
    case text(String)
    case date(Date)
}

private struct SearchCandidate {
    let kind: GlobalSearchResultKind
    let docID: UUID
    let docTitle: String
    let pageGroupID: UUID?
    let pageGroupTitle: String?
    let logicalPageID: UUID?
    let docPageNumber: Int?
    let pageVersionID: UUID?
    let noteID: UUID?

    let title: String
    let subtitle: String
    let snippet: String
    let sortDate: Date

    let textByField: [GlobalSearchField: [String]]
    let tagIDs: Set<UUID>
    let tagNames: [String]
    let variableValues: [UUID: [CandidateVariableValue]]

    var stableID: String {
        [
            kind.rawValue,
            docID.uuidString,
            pageGroupID?.uuidString ?? "-",
            logicalPageID?.uuidString ?? "-",
            pageVersionID?.uuidString ?? "-",
            noteID?.uuidString ?? "-",
        ].joined(separator: "|")
    }
}
