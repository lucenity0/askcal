//
//  NotebookSnapshotTests.swift
//  AskcalUITests
//
//  Drives the day the way a person does, and renders it so it can be looked at.
//
//  The checkbox test is the important one. Every check mark in the app rendered
//  perfectly and could not be tapped, because the row hung it out into the page
//  margin with negative padding and SwiftUI does not hit-test outside a
//  parent's bounds. Nothing about that is visible in a screenshot or catchable
//  by a unit test — only a real tap finds it.
//
//  Run with:
//    xcodebuild test -scheme Askcal -destination '...' \
//      -only-testing:AskcalUITests/NotebookSnapshotTests
//

import XCTest

final class NotebookSnapshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Launch in a named theme, past the permission alert and the greeting.
    private func launch(theme: String, contentSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-themeMode", theme]
        // Tests share a simulator and the signed-out store persists to
        // UserDefaults, so each one starts from nothing rather than from the
        // last test's leftovers. The app clears the keys itself — seeding them
        // as launch arguments would pin them in NSArgumentDomain, where the app
        // cannot write over them and any control bound to one stops working.
        app.launchArguments += ["-uiTestCleanSlate"]
        if let contentSize {
            // The ruling is derived from scaled font metrics, so the largest
            // accessibility size is where misalignment would show.
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        app.launch()

        // The notification permission alert belongs to SpringBoard, not to us.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow", "Don’t Allow", "Don't Allow"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 3) {
                button.tap()
                break
            }
        }

        // The greeting plays on every launch and takes a couple of seconds.
        Thread.sleep(forTimeInterval: 5)
        return app
    }

    /// Wait for an element to report a value, rather than sleeping and hoping.
    /// A fixed sleep is long enough alone and too short under a parallel run,
    /// which is exactly how these tests started passing one at a time and
    /// failing together.
    private func expect(_ element: XCUIElement, value: String, _ message: String) {
        expectation(for: NSPredicate(format: "value == %@", value),
                    evaluatedWith: element)
        waitForExpectations(timeout: 10) { error in
            XCTAssertNil(error, message)
        }
    }

    private func expectGone(_ element: XCUIElement, _ message: String) {
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        waitForExpectations(timeout: 10) { error in
            XCTAssertNil(error, message)
        }
    }

    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Write a task down and get it onto the page.
    @discardableResult
    private func addTask(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        let field = app.textFields["Add task"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "add-task row not found")
        field.tap()
        field.typeText(title)
        app.typeText("\n")

        let entry = app.staticTexts[title]
        XCTAssertTrue(entry.waitForExistence(timeout: 5),
                      "the task did not appear on the page after being added")
        return entry
    }

    // MARK: - Behaviour

    /// The originally reported bug: adding a task appeared to do nothing.
    func testAddingATaskPutsItOnThePage() throws {
        let app = launch(theme: "day")
        addTask(app, "finish the brief")
        snapshot(app, "20-entry-added")
    }

    /// The second reported bug: the check marks could not be tapped at all.
    func testTappingTheCheckMarkCompletesTheTask() throws {
        let app = launch(theme: "day")
        addTask(app, "tick me")

        let mark = app.buttons["tick me"]
        XCTAssertTrue(mark.waitForExistence(timeout: 5), "check mark not found")
        XCTAssertEqual(mark.value as? String, "Not done")

        // The value is what the row reports about itself, so this fails if the
        // tap lands nowhere as well as if the store refuses the change.
        mark.tap()
        expect(mark, value: "Done", "tapping the check mark did not complete it")
        snapshot(app, "21-checked")

        // And back, so a mistaken tick isn't permanent.
        mark.tap()
        expect(mark, value: "Not done", "unticking did not reopen the task")
    }

    /// Writing a task down must not push the rest of the app off the screen.
    /// Inbox, Calendar and More are tabs, so they stay where they are.
    func testTabsStayPutWhenTheDayFillsUp() throws {
        let app = launch(theme: "day")
        for title in ["one", "two", "three", "four", "five"] {
            addTask(app, title)
        }
        XCTAssertTrue(app.buttons["Inbox"].exists, "Inbox tab left the screen")
        XCTAssertTrue(app.buttons["Calendar"].exists, "Calendar tab left the screen")
        snapshot(app, "22-full-day")
    }

    func testMovingAroundTheWeek() throws {
        let app = launch(theme: "day")
        let nextWeek = app.buttons["Next week"]
        XCTAssertTrue(nextWeek.waitForExistence(timeout: 10), "week strip not found")
        nextWeek.tap()
        Thread.sleep(forTimeInterval: 1)
        snapshot(app, "23-next-week")
    }

    /// The strip hung at the top with nothing dividing it from the date. It
    /// folds away now, and the choice is remembered.
    func testCollapsingTheWeekStrip() throws {
        let app = launch(theme: "day")
        // By identifier, not by label: every day cell in the strip has the
        // month in its label too, so matching on that picks a date.
        let heading = app.buttons["weekStripToggle"]
        XCTAssertTrue(heading.waitForExistence(timeout: 10), "week toggle not found")

        XCTAssertTrue(app.buttons["Next week"].waitForExistence(timeout: 5),
                      "week should start expanded")

        heading.tap()
        expectGone(app.buttons["Next week"], "week did not collapse")
        snapshot(app, "27-week-collapsed")

        heading.tap()
        XCTAssertTrue(app.buttons["Next week"].waitForExistence(timeout: 5),
                      "week did not expand again")
    }

    /// The calendar is the month grid plus the selected day, in the same rows
    /// the day itself uses — not the hand-drawn timeline it used to be.
    func testCalendar() throws {
        let app = launch(theme: "day")
        addTask(app, "seminar")
        app.buttons["Calendar"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 2)
        snapshot(app, "28-calendar")
    }

    // MARK: - Appearance

    func testDayOnPaper() throws {
        snapshot(launch(theme: "day"), "24-day")
    }

    func testDayAtNight() throws {
        snapshot(launch(theme: "night"), "25-day-night")
    }

    /// Rows carry their own rule, so alignment should survive this. If the
    /// ruling ever moves to a fixed background grid, this is what catches it.
    func testDayAtLargestAccessibilitySize() throws {
        let app = launch(theme: "day",
                         contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        snapshot(app, "26-largest-type")
    }
}
