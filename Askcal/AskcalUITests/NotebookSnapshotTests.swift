//
//  NotebookSnapshotTests.swift
//  AskcalUITests
//
//  Renders the notebook so it can be looked at.
//
//  Two things in this design cannot be settled by reading the code. The ruling
//  has to line up with the writing at every Dynamic Type size, and the grain and
//  binding have to read as paper rather than as noise. Both are judgements about
//  pixels, so they need pixels.
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

        Thread.sleep(forTimeInterval: 4)
        return app
    }

    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testDayPageOnPaper() throws {
        let app = launch(theme: "day")
        snapshot(app, "10-day-page")
    }

    func testDayPageAtNight() throws {
        let app = launch(theme: "night")
        snapshot(app, "11-day-page-night")
    }

    /// Entries carry their own rule, so alignment should survive this. If the
    /// ruling ever moves back to a fixed background grid, this is the test that
    /// catches it.
    func testDayPageAtLargestAccessibilitySize() throws {
        let app = launch(theme: "day",
                         contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        snapshot(app, "12-day-page-largest-type")
    }

    /// The reported bug, through the real UI: tap +, type, tap Add, and the
    /// entry is on the page. It used to close the sheet and do nothing visible,
    /// because every failure was swallowed and nothing was shown until a round
    /// trip returned.
    func testAddingATaskPutsItOnThePage() throws {
        let app = launch(theme: "day")

        app.buttons["New task"].tap()

        let field = app.textFields["what needs doing?"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "composer field not found")
        field.tap()
        field.typeText("finish the brief")

        app.buttons["Add task"].tap()

        let entry = app.staticTexts["finish the brief"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5),
                      "the task did not appear on the page after being added")
        snapshot(app, "14-entry-added")
    }

    /// Tracks was the worst of the two-design-systems problem: six full page
    /// headers, each with its own serif title and underline stub, stacked
    /// inside a page that already had one.
    func testTracksIsOnTheSamePaper() throws {
        let app = launch(theme: "day")
        let tracks = app.buttons["Tracks"].firstMatch
        XCTAssertTrue(tracks.waitForExistence(timeout: 10), "Tracks row not found")
        tracks.tap()
        Thread.sleep(forTimeInterval: 1.5)
        snapshot(app, "15-tracks")
    }

    /// The month grid, whose dots used to draw for today and no other day.
    func testCalendarMonthGrid() throws {
        let app = launch(theme: "day")
        app.buttons["Calendar"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.5)
        app.buttons["Month"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.5)
        snapshot(app, "16-calendar-month")
    }

    /// The page turn, and the destination rows below the writing.
    func testTurningToTomorrow() throws {
        let app = launch(theme: "day")
        let next = app.buttons["Next day"]
        XCTAssertTrue(next.waitForExistence(timeout: 10), "next-day chevron not found")
        next.tap()
        Thread.sleep(forTimeInterval: 1.5)
        snapshot(app, "13-tomorrow")
    }
}
