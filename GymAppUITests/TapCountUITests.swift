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

    private func waitUntil(_ timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end { if condition() { return true }; RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
        return condition()
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
    /// Rulebook §19: the lock-screen widget's link starts the next day with no tap in the app.
    func testTheStartLinkStartsTheNextWorkout() {
        launch(workout: false)
        app.open(URL(string: "bashigym://start")!)
        XCTAssertTrue(buttonStarting("Log set").waitForExistence(timeout: 10), "the workout screen is up")
        record("start from the lock-screen widget")
    }

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

    // 6, R.4: the exercise name opens its page, history included
    func testExercisePageFromTheWorkout() {
        launch()
        tap(buttonStarting("Test Bench"))
        XCTAssertTrue(button("Close").waitForExistence(timeout: 10))
        XCTAssertTrue(text("Best estimated 1RM").waitForExistence(timeout: 5))
        record("6 lift page and history during a workout (R.4: tap the name)")
    }

    // 7
    func testSwapDuringAWorkout() {
        launch()
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
        XCTAssertTrue(text("workout complete").waitForExistence(timeout: 10))
        record("8 finish")
    }

    // 9 (R.3: straight from Train)
    func testOpenAnExerciseOfTodaysPlan() {
        launch(workout: false)
        tap(buttonStarting("Test Bench"))
        XCTAssertTrue(text("In Day A").waitForExistence(timeout: 10))
        record("9 open an exercise of today's plan")
    }

    // 10 (R.6: one screen of summaries)
    func testWeeklyReview() {
        launch(workout: false)
        tap(button("Progress"))
        let end = button("Recaps")
        var swipes = 0
        while !(end.exists && end.isHittable) && swipes < 12 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(end.isHittable)
        taps += swipes
        record("10 weekly review (1 tap + \(swipes) scrolls to the end)")
    }

    /// R.6 proof: every old Progress section is two taps or fewer from the tab.
    func testEveryProgressDetailWithinTwoTaps() {
        launch(workout: false)
        tap(button("Progress"))
        tap(buttonStarting("This week"))
        XCTAssertTrue(text("No weights yet").waitForExistence(timeout: 10))   // body weight, in the week's detail
        XCTAssertTrue(text("Volume").exists)
        app.navigationBars.buttons.firstMatch.tap()
        tap(buttonStarting("Recovery"))
        XCTAssertTrue(app.navigationBars["Recovery"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        tap(buttonStarting("Lifts"))
        XCTAssertTrue(app.navigationBars["Lifts"].waitForExistence(timeout: 5))
    }

    // Plan edits
    func testChangeADaysTargets() {
        launch(workout: false)
        tap(buttonStarting("Test Bench"))
        tap(app.buttons["Increment"].firstMatch)   // saves at once
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Sets: 3")).firstMatch.waitForExistence(timeout: 5))
        record("plan: change a day's targets (+1 set)")
    }

    func testSwapAnExerciseInThePlan() {
        launch(workout: false)
        tap(buttonStarting("Test Bench"))
        tap(button("Swap"))
        tap(buttonStarting("Test Row"))
        XCTAssertTrue(button("Start Day A").waitForExistence(timeout: 10))
        record("plan: swap an exercise")
    }

    func testReorderADay() {
        launch(workout: false)
        tap(buttonStarting("Next up"))
        // No Edit mode: press and hold the second row, then drag it above the first.
        let first = buttonStarting("Test Bench"), second = buttonStarting("Test Row")
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        XCTAssertLessThan(first.frame.minY, second.frame.minY)
        // A slow drag that holds at the end: a quick one is sometimes read as a scroll.
        second.press(forDuration: 1.2, thenDragTo: first, withVelocity: .slow, thenHoldForDuration: 0.6)
        taps += 1
        XCTAssertTrue(waitUntil { second.frame.minY < first.frame.minY }, "the drag reordered the day")
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
