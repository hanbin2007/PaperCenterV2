//
//  GlobalSearchServiceTests.swift
//  PaperCenterV2Tests
//
//  Structured filter behavior tests for global search.
//

import XCTest
import SwiftData
@testable import PaperCenterV2

@MainActor
final class GlobalSearchServiceTests: XCTestCase {
    private struct Fixture {
        let context: ModelContext
        let service: GlobalSearchService

        let alphaTag: Tag
        let betaTag: Tag
        let gammaTag: Tag

        let intVariable: Variable
        let dateVariable: Variable
        let listVariable: Variable
        let textVariable: Variable
        let unsetVariable: Variable
    }

    func testTagKeywordFilterMatchesTagNames() throws {
        try skipIfNeeded()
        let fixture = try makeFixture()

        var options = baseOptions(resultTypes: [.page])
        options.tagFilter = TagFilter(nameKeyword: "Alpha", selectedTagIDs: [], mode: .any)

        let results = fixture.service.search(query: "", options: options)

        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { $0.kind == .page })
    }

    func testTagSelectedAnyMode() throws {
        try skipIfNeeded()
        let fixture = try makeFixture()

        var options = baseOptions(resultTypes: [.page])
        options.tagFilter = TagFilter(
            nameKeyword: "",
            selectedTagIDs: [fixture.alphaTag.id, fixture.gammaTag.id],
            mode: .any
        )

        let results = fixture.service.search(query: "", options: options)

        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.contains(where: { $0.kind == .page }))
    }

    func testTagSelectedAllMode() throws {
        try skipIfNeeded()
        let fixture = try makeFixture()

        var matchingOptions = baseOptions(resultTypes: [.page])
        matchingOptions.tagFilter = TagFilter(
            nameKeyword: "",
            selectedTagIDs: [fixture.alphaTag.id, fixture.betaTag.id],
            mode: .all
        )

        let matchingResults = fixture.service.search(query: "", options: matchingOptions)
        XCTAssertFalse(matchingResults.isEmpty)

        var nonMatchingOptions = baseOptions(resultTypes: [.page])
        nonMatchingOptions.tagFilter = TagFilter(
            nameKeyword: "",
            selectedTagIDs: [fixture.alphaTag.id, fixture.gammaTag.id],
            mode: .all
        )

        let nonMatchingResults = fixture.service.search(query: "", options: nonMatchingOptions)
        XCTAssertTrue(nonMatchingResults.isEmpty)
    }

    func testVariableIntComparisonsGtLtGteLteEqNeq() throws {
        try skipIfNeeded()
        let fixture = try makeFixture()

        let assertions: [(VariableFilterOperator, VariableFilterValue, Bool)] = [
            (.gt, .int(9), true),
            (.lt, .int(11), true),
            (.gte, .int(10), true),
            (.lte, .int(10), true),
            (.eq, .int(10), true),
            (.neq, .int(11), true),
            (.eq, .int(11), false),
            (.neq, .int(10), false),
        ]

        for (op, value, expected) in assertions {
            let options = optionsWithSingleRule(
                variableID: fixture.intVariable.id,
                op: op,
                value: value,
                resultTypes: [.page]
            )
            let results = fixture.service.search(query: "", options: options)
            XCTAssertEqual(!results.isEmpty, expected, "operator=\(op.rawValue)")
        }
    }

    func testVariableDateComparisonsGtLtBetween() throws {
        try skipIfNeeded()
        let fixture = try makeFixture()
        let jan1 = date(2024, 1, 1)
        let feb1 = date(2024, 2, 1)

        let gtOptions = optionsWithSingleRule(
            variableID: fixture.dateVariable.id,
            op: .gt,
            value: .date(jan1),
            resultTypes: [.page]
        )
        XCTAssertFalse(fixture.service.search(query: "", options: gtOptions).isEmpty)

        let ltOptions = optionsWithSingleRule(
            variableID: fixture.dateVariable.id,
            op: .lt,
            value: .date(feb1),
            resultTypes: [.page]
        )
        XCTAssertFalse(fixture.service.search(query: "", options: ltOptions).isEmpty)

        let betweenOptions = optionsWithSingleRule(
            variableID: fixture.dateVariable.id,
            op: .between,
            value: .dateRange(
                min: date(2024, 1, 10),
                max: date(2024, 1, 20),
                lowerInclusion: .closed,
                upperInclusion: .closed
            ),
            resultTypes: [.page]
        )
        XCTAssertFalse(fixture.service.search(query: "", options: betweenOptions).isEmpty)
    }

    func testVariableBetweenOpenClosedBounds() throws {
        try skipIfNeeded()
        let fixture = try makeFixture()

        let closed = optionsWithSingleRule(
            variableID: fixture.intVariable.id,
            op: .between,
            value: .intRange(min: 10, max: 10, lowerInclusion: .closed, upperInclusion: .closed),
            resultTypes: [.page]
        )
        XCTAssertFalse(fixture.service.search(query: "", options: closed).isEmpty)

        let open = optionsWithSingleRule(
            variableID: fixture.intVariable.id,
            op: .between,
            value: .intRange(min: 10, max: 10, lowerInclusion: .open, upperInclusion: .open),
            resultTypes: [.page]
        )
        XCTAssertTrue(fixture.service.search(query: "", options: open).isEmpty)

        let mixed = optionsWithSingleRule(
            variableID: fixture.intVariable.id,
            op: .between,
            value: .intRange(min: 9, max: 10, lowerInclusion: .open, upperInclusion: .closed),
            resultTypes: [.page]
        )
        XCTAssertFalse(fixture.service.search(query: "", options: mixed).isEmpty)
    }

    func testVariableListInNotIn() throws {
        try skipIfNeeded()
        let fixture = try makeFixture()

        let inOptions = optionsWithSingleRule(
            variableID: fixture.listVariable.id,
            op: .in,
            value: .list(["A", "B"]),
            resultTypes: [.page]
        )
        XCTAssertFalse(fixture.service.search(query: "", options: inOptions).isEmpty)

        let notInOptions = optionsWithSingleRule(
            variableID: fixture.listVariable.id,
            op: .notIn,
            value: .list(["B"]),
            resultTypes: [.page]
        )
        XCTAssertFalse(fixture.service.search(query: "", options: notInOptions).isEmpty)

        let notInMissOptions = optionsWithSingleRule(
            variableID: fixture.listVariable.id,
            op: .notIn,
            value: .list(["A"]),
            resultTypes: [.page]
        )
        XCTAssertTrue(fixture.service.search(query: "", options: notInMissOptions).isEmpty)
    }

    func testVariableTextContainsEquals() throws {
        try skipIfNeeded()
        let fixture = try makeFixture()

        let containsOptions = optionsWithSingleRule(
            variableID: fixture.textVariable.id,
            op: .contains,
            value: .text("hello"),
            resultTypes: [.page]
        )
        XCTAssertFalse(fixture.service.search(query: "", options: containsOptions).isEmpty)

        let equalsOptions = optionsWithSingleRule(
            variableID: fixture.textVariable.id,
            op: .equals,
            value: .text("hello world"),
            resultTypes: [.page]
        )
        XCTAssertFalse(fixture.service.search(query: "", options: equalsOptions).isEmpty)

        let equalsMissOptions = optionsWithSingleRule(
            variableID: fixture.textVariable.id,
            op: .equals,
            value: .text("hello"),
            resultTypes: [.page]
        )
        XCTAssertTrue(fixture.service.search(query: "", options: equalsMissOptions).isEmpty)
    }

    func testVariableIsSetIsEmpty() throws {
        try skipIfNeeded()
        let fixture = try makeFixture()

        let isSetOptions = optionsWithSingleRule(
            variableID: fixture.intVariable.id,
            op: .isSet,
            value: nil,
            resultTypes: [.page]
        )
        XCTAssertFalse(fixture.service.search(query: "", options: isSetOptions).isEmpty)

        let isEmptyOptions = optionsWithSingleRule(
            variableID: fixture.unsetVariable.id,
            op: .isEmpty,
            value: nil,
            resultTypes: [.page]
        )
        XCTAssertFalse(fixture.service.search(query: "", options: isEmptyOptions).isEmpty)

        let isSetMissOptions = optionsWithSingleRule(
            variableID: fixture.unsetVariable.id,
            op: .isSet,
            value: nil,
            resultTypes: [.page]
        )
        XCTAssertTrue(fixture.service.search(query: "", options: isSetMissOptions).isEmpty)
    }

    func testVariableRulesAndMode() throws {
        try skipIfNeeded()
        let fixture = try makeFixture()

        var options = baseOptions(resultTypes: [.page])
        options.variableRulesMode = .and
        options.variableRules = [
            VariableFilterRule(variableID: fixture.intVariable.id, operator: .eq, value: .int(10)),
            VariableFilterRule(variableID: fixture.textVariable.id, operator: .contains, value: .text("hello")),
        ]

        XCTAssertFalse(fixture.service.search(query: "", options: options).isEmpty)

        options.variableRules = [
            VariableFilterRule(variableID: fixture.intVariable.id, operator: .eq, value: .int(10)),
            VariableFilterRule(variableID: fixture.textVariable.id, operator: .equals, value: .text("missing")),
        ]

        XCTAssertTrue(fixture.service.search(query: "", options: options).isEmpty)
    }

    func testVariableRulesOrMode() throws {
        try skipIfNeeded()
        let fixture = try makeFixture()

        var options = baseOptions(resultTypes: [.page])
        options.variableRulesMode = .or
        options.variableRules = [
            VariableFilterRule(variableID: fixture.intVariable.id, operator: .eq, value: .int(999)),
            VariableFilterRule(variableID: fixture.textVariable.id, operator: .contains, value: .text("hello")),
        ]

        XCTAssertFalse(fixture.service.search(query: "", options: options).isEmpty)

        options.variableRules = [
            VariableFilterRule(variableID: fixture.intVariable.id, operator: .eq, value: .int(999)),
            VariableFilterRule(variableID: fixture.textVariable.id, operator: .equals, value: .text("missing")),
        ]

        XCTAssertTrue(fixture.service.search(query: "", options: options).isEmpty)
    }

    func testVariableFiltersApplyToCurrentAssignmentsAndSnapshots() throws {
        try skipIfNeeded()
        let fixture = try makeFixture()

        var currentOnly = optionsWithSingleRule(
            variableID: fixture.intVariable.id,
            op: .eq,
            value: .int(10),
            resultTypes: [.page]
        )
        currentOnly.includeHistoricalVersions = false
        XCTAssertFalse(fixture.service.search(query: "", options: currentOnly).isEmpty)

        var snapshotWithoutHistorical = optionsWithSingleRule(
            variableID: fixture.intVariable.id,
            op: .eq,
            value: .int(20),
            resultTypes: [.page]
        )
        snapshotWithoutHistorical.includeHistoricalVersions = false
        XCTAssertTrue(fixture.service.search(query: "", options: snapshotWithoutHistorical).isEmpty)

        var snapshotWithHistorical = optionsWithSingleRule(
            variableID: fixture.intVariable.id,
            op: .eq,
            value: .int(20),
            resultTypes: [.page]
        )
        snapshotWithHistorical.includeHistoricalVersions = true
        XCTAssertFalse(fixture.service.search(query: "", options: snapshotWithHistorical).isEmpty)
    }

    func testFilterOnlySearchWithoutQuery() throws {
        try skipIfNeeded()
        let fixture = try makeFixture()

        var options = baseOptions(resultTypes: [.page])
        options.tagFilter = TagFilter(nameKeyword: "alpha", selectedTagIDs: [], mode: .any)

        let results = fixture.service.search(query: "", options: options)

        XCTAssertFalse(results.isEmpty)
    }

    func testResultTypeFilteringAfterStructuredFilters() throws {
        try skipIfNeeded()
        let fixture = try makeFixture()

        var options = baseOptions(resultTypes: [.noteHit])
        options.tagFilter = TagFilter(
            nameKeyword: "",
            selectedTagIDs: [fixture.alphaTag.id],
            mode: .any
        )

        let results = fixture.service.search(query: "", options: options)

        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { $0.kind == .noteHit })
    }

    private func makeFixture() throws -> Fixture {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let bundle = PDFBundle(name: "Fixture Bundle")
        bundle.ocrTextByPage = [
            1: "alpha historical ocr",
            2: "alpha current ocr",
        ]

        let doc = Doc(title: "Fixture Doc")
        let group = PageGroup(title: "Fixture Group", doc: doc)
        doc.addPageGroup(group)

        let page = Page(pdfBundle: bundle, pageNumber: 1, pageGroup: group)
        group.addPage(page)

        let alphaTag = Tag(name: "AlphaTag", color: "#22C55E", scope: .all, sortIndex: 0)
        let betaTag = Tag(name: "BetaTag", color: "#3B82F6", scope: .all, sortIndex: 1)
        let gammaTag = Tag(name: "GammaTag", color: "#EF4444", scope: .all, sortIndex: 2)
        page.tags = [alphaTag, betaTag]

        let intVariable = Variable(name: "Score", type: .int, scope: .all, sortIndex: 0)
        let dateVariable = Variable(name: "ExamDate", type: .date, scope: .all, sortIndex: 1)
        let listVariable = Variable(name: "Level", type: .list, scope: .all, sortIndex: 2, listOptions: ["A", "B", "C"])
        let textVariable = Variable(name: "Comment", type: .text, scope: .all, sortIndex: 3)
        let unsetVariable = Variable(name: "Unset", type: .int, scope: .all, sortIndex: 4)

        let pageAssignments = [
            PageVariableAssignment(variable: intVariable, page: page, intValue: 10),
            PageVariableAssignment(variable: dateVariable, page: page, dateValue: date(2024, 1, 15)),
            PageVariableAssignment(variable: listVariable, page: page, listValue: "A"),
            PageVariableAssignment(variable: textVariable, page: page, textValue: "hello world"),
        ]
        page.variableAssignments = pageAssignments

        _ = page.updateReference(to: bundle, pageNumber: 2)

        if let versions = page.versions {
            let historical = versions.first(where: { $0.pageNumber == 1 })
            historical?.metadataSnapshot = try? PageVersion.encodeMetadataSnapshot(
                MetadataSnapshot(
                    tagIDs: [betaTag.id],
                    variableAssignments: [
                        VariableAssignmentSnapshot(
                            variableID: intVariable.id,
                            intValue: 20,
                            listValue: nil,
                            textValue: nil,
                            dateValue: nil
                        ),
                        VariableAssignmentSnapshot(
                            variableID: dateVariable.id,
                            intValue: nil,
                            listValue: nil,
                            textValue: nil,
                            dateValue: date(2024, 1, 20)
                        ),
                        VariableAssignmentSnapshot(
                            variableID: listVariable.id,
                            intValue: nil,
                            listValue: "B",
                            textValue: nil,
                            dateValue: nil
                        ),
                        VariableAssignmentSnapshot(
                            variableID: textVariable.id,
                            intValue: nil,
                            listValue: nil,
                            textValue: "snapshot text",
                            dateValue: nil
                        ),
                    ]
                )
            )
        }

        if let latestVersion = page.latestVersion {
            let note = NoteBlock.createNormalized(
                pageVersion: latestVersion,
                absoluteRect: CGRect(x: 10, y: 10, width: 100, height: 40),
                pageSize: CGSize(width: 200, height: 300),
                title: "Fixture Note",
                body: "important note body"
            )
            note.tags = [alphaTag]
            let noteAssignment = NoteBlockVariableAssignment(
                variable: intVariable,
                noteBlock: note,
                intValue: 0
            )
            note.variableAssignments = [noteAssignment]

            context.insert(note)
            context.insert(noteAssignment)
        }

        context.insert(bundle)
        context.insert(doc)
        context.insert(group)
        context.insert(page)

        context.insert(alphaTag)
        context.insert(betaTag)
        context.insert(gammaTag)

        context.insert(intVariable)
        context.insert(dateVariable)
        context.insert(listVariable)
        context.insert(textVariable)
        context.insert(unsetVariable)

        for assignment in pageAssignments {
            context.insert(assignment)
        }

        try context.save()

        return Fixture(
            context: context,
            service: GlobalSearchService(modelContext: context),
            alphaTag: alphaTag,
            betaTag: betaTag,
            gammaTag: gammaTag,
            intVariable: intVariable,
            dateVariable: dateVariable,
            listVariable: listVariable,
            textVariable: textVariable,
            unsetVariable: unsetVariable
        )
    }

    private func baseOptions(resultTypes: Set<GlobalSearchResultKind>) -> GlobalSearchOptions {
        GlobalSearchOptions(
            fieldScope: Set(GlobalSearchField.allCases),
            resultTypes: resultTypes,
            includeHistoricalVersions: true,
            maxResults: 200,
            tagFilter: TagFilter(),
            variableRules: [],
            variableRulesMode: .and
        )
    }

    private func optionsWithSingleRule(
        variableID: UUID,
        op: VariableFilterOperator,
        value: VariableFilterValue?,
        resultTypes: Set<GlobalSearchResultKind>
    ) -> GlobalSearchOptions {
        var options = baseOptions(resultTypes: resultTypes)
        options.variableRules = [
            VariableFilterRule(variableID: variableID, operator: op, value: value),
        ]
        return options
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            PDFBundle.self,
            Page.self,
            PageVersion.self,
            PageGroup.self,
            Doc.self,
            NoteBlock.self,
            Tag.self,
            TagGroup.self,
            Variable.self,
            PDFBundleVariableAssignment.self,
            DocVariableAssignment.self,
            PageGroupVariableAssignment.self,
            PageVariableAssignment.self,
            NoteBlockVariableAssignment.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.calendar = Calendar(identifier: .gregorian)
        return components.date ?? Date(timeIntervalSince1970: 0)
    }

    private func skipIfNeeded() throws {
        let shouldSkip = ProcessInfo.processInfo.environment["SKIP_GLOBAL_SEARCH_SERVICE_TESTS"] != "0"
        if shouldSkip {
            throw XCTSkip("Skipped on Designed-for-iPad runtime due SwiftData Array materialization crashes. Set SKIP_GLOBAL_SEARCH_SERVICE_TESTS=0 to run.")
        }
    }
}
