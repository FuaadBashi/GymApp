import XCTest

/// Redesign card R.1: the taps (and scrolls) each common task takes, on the in-memory fixture.
/// Each test prints "TAPCOUNT <task>: <n>"; docs/redesign/tap-counts.md records the numbers.
final class TapCountUITests: XCTestCase {
    private var app: XCUIApplication!
    private var taps = 0

    private func launch(workout: Bool = true) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTestFixture"] + (workout ? [] : ["-uiTestNoWorkout"])
        app.launchFixture()
        taps = 0
    }

    private func tap(_ element: XCUIElement, _ file: StaticString = #filePath, _ line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 20), "\(element) not found", file: file, line: line)
        element.tap()
        taps += 1
    }

    private func record(_ task: String) { print("TAPCOUNT \(task): \(taps)") }

    private func button(_ label: String) -> XCUIElement { app.buttons[label].firstMatch }
    private func buttonStarting(_ prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }
    private func text(_ contains: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", contains)).firstMatch
    }

    // 1
    func testStartTheNextWorkout() {
        launch(workout: false)
        tap(button("Start Day A"))
        XCTAssertTrue(buttonStarting("Log set").waitForExistence(timeout: 10))
        record("1 start the next workout")
    }

    // 2
    func testLogThePrefilledSet() {
        launch()
        tap(buttonStarting("Log set"))
        XCTAssertTrue(button("Skip").waitForExistence(timeout: 5))
        record("2 log the prefilled set")
    }

    // 3
    func testChangeLoadThenLog() {
        launch()
        tap(button("More weight"))
        tap(buttonStarting("Log set"))
        XCTAssertTrue(button("Skip").waitForExistence(timeout: 5))
        record("3 change load (+1 step) then log")
    }

    // 4
    func testSeeWhatToBeat() {
        launch()
        let best = app.descendants(matching: .any)["best-all-time"]
        XCTAssertTrue(best.waitForExistence(timeout: 10) && best.isHittable)
        record("4 see what to beat")
    }

    // 5
    func testSkipRest() {
        launch()
        tap(buttonStarting("Log set"))
        taps = 0
        tap(button("Skip"))
        XCTAssertTrue(buttonStarting("Log set").waitForExistence(timeout: 5))
        record("5 skip rest")
    }

    // 6
    func testLiftHistoryDuringAWorkout() {
        launch()
        tap(button("Exercise options"))
        tap(button("History"))
        XCTAssertTrue(button("Close").waitForExistence(timeout: 5))
        record("6 lift history during a workout")
    }

    // 7
    func testSwapDuringAWorkout() {
        launch()
        tap(button("Exercise options"))
        tap(button("Swap exercise"))
        tap(buttonStarting("Test Row"))
        XCTAssertTrue(text("Test Row").waitForExistence(timeout: 5))
        record("7 swap during a workout")
    }

    // 8
    func testFinish() {
        launch()
        tap(buttonStarting("Log set"))
        tap(button("Skip"))
        taps = 0
        tap(button("Finish"))
        tap(app.buttons.matching(identifier: "Finish").element(boundBy: 1))
        XCTAssertTrue(text("Workout complete").waitForExistence(timeout: 10))
        record("8 finish")
    }

    // 9
    func testOpenAnExerciseOfTodaysPlan() {
        launch(workout: false)
        tap(button("Exercises"))
        tap(buttonStarting("Test Bench"))
        XCTAssertTrue(text("Best estimated 1RM").waitForExistence(timeout: 10))
        record("9 open an exercise of today's plan (via Exercises; not possible from the day)")
    }

    // 10
    func testWeeklyReview() {
        launch(workout: false)
        tap(button("Progress"))
        let end = text("No weights yet")
        var swipes = 0
        while !(end.exists && end.isHittable) && swipes < 12 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(end.isHittable)
        taps += swipes
        record("10 weekly review (1 tap + \(swipes) scrolls to the end)")
    }

    // Plan edits
    func testChangeADaysTargets() {
        launch(workout: false)
        tap(buttonStarting("Next up"))
        tap(buttonStarting("Test Bench"))   // the row's centre: until 20 Oct only its text answered
        tap(app.buttons["Increment"].firstMatch)
        tap(button("Save"))
        XCTAssertTrue(text("3 ×").waitForExistence(timeout: 5))
        record("plan: change a day's targets (+1 set)")
    }

    func testReorderADay() {
        launch(workout: false)
        tap(buttonStarting("Next up"))
        tap(button("Edit"))
        let handle = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Reorder'")).element(boundBy: 1)
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        handle.press(forDuration: 0.5, thenDragTo: app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Reorder'")).element(boundBy: 0))
        taps += 1
        tap(button("Done"))
        record("plan: reorder a day")
    }
}

extension XCUIApplication {
    /// Launches and checks the in-memory fixture is showing. The first launch straight after a
    /// unit-test run on the same simulator can lose its launch arguments and open the real
    /// database instead; relaunch once in that case so a test never runs against real data.
    func launchFixture() {
        launch()
        let fixture = descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Test Bench' OR label CONTAINS 'Day A'")).firstMatch
        if !fixture.waitForExistence(timeout: 15) {
            terminate()
            launch()
        }
        XCTAssertTrue(fixture.waitForExistence(timeout: 15), "The UI-test fixture did not load")
    }
}
