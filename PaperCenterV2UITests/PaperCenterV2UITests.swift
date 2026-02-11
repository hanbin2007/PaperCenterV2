//
//  PaperCenterV2UITests.swift
//  PaperCenterV2UITests
//
//  Focused UI smoke tests.
//

import XCTest

final class PaperCenterV2UITests: XCTestCase {

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
        let bundlesTab = tabBar.buttons["Bundles"]
        let propertiesTab = tabBar.buttons["Properties"]
        let ocrDebugTab = tabBar.buttons["OCR Debug"]

        XCTAssertTrue(documentsTab.exists)
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
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
