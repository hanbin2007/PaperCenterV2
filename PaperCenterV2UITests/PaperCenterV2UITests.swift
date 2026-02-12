//
//  PaperCenterV2UITests.swift
//  PaperCenterV2UITests
//
//  Focused UI smoke tests.
//

import XCTest

final class PaperCenterV2UITests: XCTestCase {
    private let alphaTagAccessibilityID = "globalSearch.tag.50000000-0000-0000-0000-000000000001"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testMainTabsAreVisibleAndNavigable() throws {
        let app = XCUIApplication()
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))

        let documentsTab = tabBar.buttons["Documents"]
        let searchTab = tabBar.buttons["Search"]
        let bundlesTab = tabBar.buttons["Bundles"]
        let propertiesTab = tabBar.buttons["Properties"]
        let ocrDebugTab = tabBar.buttons["OCR Debug"]

        XCTAssertTrue(documentsTab.exists)
        XCTAssertTrue(searchTab.exists)
        XCTAssertTrue(bundlesTab.exists)
        XCTAssertTrue(propertiesTab.exists)
        XCTAssertTrue(ocrDebugTab.exists)

        documentsTab.tap()
        XCTAssertTrue(app.navigationBars["Documents"].waitForExistence(timeout: 2))

        bundlesTab.tap()
        XCTAssertTrue(app.navigationBars["PDF Bundles"].waitForExistence(timeout: 2))

        propertiesTab.tap()
        let segmented = app.segmentedControls.firstMatch
        XCTAssertTrue(segmented.waitForExistence(timeout: 2))
        XCTAssertTrue(segmented.buttons["Tags"].exists)
        XCTAssertTrue(segmented.buttons["Variables"].exists)

        ocrDebugTab.tap()
        XCTAssertTrue(app.navigationBars["OCR Debug"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testSearchFilterSheetConfiguresTagModeAndVariableRuleAndRefreshesResults() throws {
        let app = launchSeededApp()
        openSearchTab(app)

        applyBaselineSearchFilters(app)

        let resultList = app.tables["globalSearch.resultList"]
        XCTAssertTrue(resultList.waitForExistence(timeout: 3))
        XCTAssertTrue(resultList.cells.firstMatch.waitForExistence(timeout: 3))
    }

    @MainActor
    func testSearchFilterConfigurationRestoresAfterRestart() throws {
        let app = launchSeededApp()
        openSearchTab(app)
        applyBaselineSearchFilters(app)
        app.terminate()

        let relaunched = launchSeededApp()
        openSearchTab(relaunched)

        let summary = relaunched.staticTexts["globalSearch.filterSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 3))
        XCTAssertTrue(summary.label.contains("Tag ALL"))
        XCTAssertTrue(summary.label.contains("Variable AND 1"))
    }

    @MainActor
    func testOpenFilteredResultAndBackKeepsSearchState() throws {
        let app = launchSeededApp()
        openSearchTab(app)
        applyBaselineSearchFilters(app)

        let resultList = app.tables["globalSearch.resultList"]
        XCTAssertTrue(resultList.waitForExistence(timeout: 3))
        let firstCell = resultList.cells.firstMatch
        XCTAssertTrue(firstCell.waitForExistence(timeout: 3))
        firstCell.tap()

        XCTAssertTrue(app.navigationBars["UITest Doc"].waitForExistence(timeout: 5))
        app.navigationBars["UITest Doc"].buttons.element(boundBy: 0).tap()

        XCTAssertTrue(app.navigationBars["Search"].waitForExistence(timeout: 3))
        let summary = app.staticTexts["globalSearch.filterSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 3))
        XCTAssertTrue(summary.label.contains("Tag ALL"))
        XCTAssertTrue(summary.label.contains("Variable AND 1"))
        XCTAssertTrue(resultList.cells.firstMatch.waitForExistence(timeout: 3))
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    private func launchSeededApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-uiTestSeedGlobalSearch")
        app.launch()
        return app
    }

    @MainActor
    private func openSearchTab(_ app: XCUIApplication) {
        let searchTab = app.tabBars.firstMatch.buttons["Search"]
        XCTAssertTrue(searchTab.waitForExistence(timeout: 3))
        searchTab.tap()
        XCTAssertTrue(app.navigationBars["Search"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func applyBaselineSearchFilters(_ app: XCUIApplication) {
        let filterButton = app.buttons["globalSearch.filterButton"]
        XCTAssertTrue(filterButton.waitForExistence(timeout: 3))
        filterButton.tap()
        XCTAssertTrue(app.navigationBars["Search Filters"].waitForExistence(timeout: 3))

        let allModeButton = app.segmentedControls.buttons["All"].firstMatch
        tapInSheetIfNeeded(element: allModeButton, app: app)

        let alphaTagButton = app.buttons[alphaTagAccessibilityID]
        tapInSheetIfNeeded(element: alphaTagButton, app: app)

        let addRuleButton = app.buttons["globalSearch.addVariableRule"]
        tapInSheetIfNeeded(element: addRuleButton, app: app)

        let applyButton = app.navigationBars["Search Filters"].buttons["Apply"]
        XCTAssertTrue(applyButton.exists)
        applyButton.tap()

        XCTAssertTrue(app.navigationBars["Search"].waitForExistence(timeout: 3))
        let summary = app.staticTexts["globalSearch.filterSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 3))
        XCTAssertTrue(summary.label.contains("Tag ALL"))
        XCTAssertTrue(summary.label.contains("Variable AND 1"))
    }

    @MainActor
    private func tapInSheetIfNeeded(element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<5 {
            if element.exists && element.isHittable {
                element.tap()
                return
            }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists)
        element.tap()
    }
}
