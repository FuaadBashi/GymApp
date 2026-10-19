import XCTest

/// The workout screen against the in-memory fixture (AppStartup.uiTestFixture): one exercise,
/// all-time best 100 × 5 (116.7 kg), 12-month best 80 × 8 (101.3 kg), a planned set of 60 × 10.
final class WorkoutScreenUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTestFixture"]
        app.launch()
    }

    private func element(_ id: String) -> XCUIElement {
        let e = app.descendants(matching: .any)[id]
        XCTAssertTrue(e.waitForExistence(timeout: 10), "\(id) not on screen")
        return e
    }

    func testThisSetShowsItsLiveEstimate() {
        // 60 × 10 → 60 × (1 + 10/30) = 80 kg.
        XCTAssertTrue(element("this-set-e1rm").label.contains("80 kg"), element("this-set-e1rm").label)
    }

    func testBestTilesShowTheSetAndTheGap() {
        let allTime = element("best-all-time")
        XCTAssertTrue(allTime.label.contains("116.7 kg"), allTime.label)
        XCTAssertTrue(allTime.label.contains("100×5"), allTime.label)
        XCTAssertTrue(allTime.label.contains("36.7 kg below"), allTime.label)
        let window = element("best-window")
        XCTAssertTrue(window.label.contains("12-month best"), window.label)
        XCTAssertTrue(window.label.contains("80×8"), window.label)
    }

    /// The bug from 18 October: tapping the best did nothing on the phone.
    func testTappingABestOpensItsBeatTable() {
        element("best-all-time").tap()
        XCTAssertTrue(app.staticTexts["All-time best: est. 1RM 116.7 kg"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        element("best-window").tap()
        XCTAssertTrue(app.staticTexts["12-month best: est. 1RM 101.3 kg"].waitForExistence(timeout: 5))
    }

    func testTodaysSetLeadsAndLastTimeIsLabelled() {
        XCTAssertTrue(app.staticTexts["LAST"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["60"].exists)
    }

    /// Rulebook §13: the fixture's last session was 60 days ago, so today is a comeback.
    func testTodaysSuggestionIsShownAndFills() {
        let next = element("next-suggestion")
        XCTAssertTrue(next.label.contains("Today:"), next.label)
        XCTAssertTrue(next.label.contains("First session in 60 days"), next.label)
    }
}
