//
//  PaperCenterV2UITestsLaunchTests.swift
//  PaperCenterV2UITests
//
//  Launch-level sanity checks.
//

import XCTest

final class PaperCenterV2UITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
    }
}
