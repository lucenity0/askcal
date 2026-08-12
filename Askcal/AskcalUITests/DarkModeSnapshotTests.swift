//
//  DarkModeSnapshotTests.swift
//  AskcalUITests
//
//  Captures the night theme on the screens that use the shared styles.
//
//  These exist because `PillButtonStyle`, `PaperToggleStyle` and `ChipPicker`
//  read `@Environment(\.book)` from inside a `ButtonStyle`/`ToggleStyle`
//  struct. Those are not Views, and if SwiftUI does not inject into them the
//  palette silently falls back to `PaperPaletteKey.defaultValue` — the day
//  theme, whose `fill` is near-black. On the night theme's near-black page that
//  makes every filled pill disappear. Reading the code cannot settle it;
//  rendering can.
//
//  The launch arguments deliberately use the older theme names. They are the
//  live check that `ThemeMode.stored` still maps every spelling these themes
//  have had — light/dark, paper/slate, day/night — because an unmapped one
//  silently returns that person to the light theme with no way to tell.
//

import XCTest

final class DarkModeSnapshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchDark(themeName: String = "dark") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-themeMode", themeName, "-uiTestCleanSlate"]
        app.launch()

        // The notification permission alert belongs to SpringBoard, not us.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow", "Don’t Allow", "Don't Allow"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 3) {
                button.tap()
                break
            }
        }

        Thread.sleep(forTimeInterval: 5)   // the launch greeting
        return app
    }

    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The launch scene is on screen for about two and a half seconds, so this
    /// deliberately does not wait the greeting out.
    func testLaunchSceneAtNight() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-themeMode", "slate"]   // pre-rename name
        app.launch()
        Thread.sleep(forTimeInterval: 1.2)
        snapshot(app, "30-launch-scene-night")
    }

    func testLaunchSceneOnPaper() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-themeMode", "paper"]   // pre-rename name
        app.launch()
        Thread.sleep(forTimeInterval: 1.2)
        snapshot(app, "31-launch-scene-day")
    }

    /// More carries the densest set of shared styles: filled and outlined
    /// pills, the theme chip picker, and two toggles.
    func testMoreScreenAtNight() throws {
        let app = launchDark()
        snapshot(app, "32-day-night")

        let more = app.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 10), "More tab not found")
        more.tap()
        Thread.sleep(forTimeInterval: 2)
        snapshot(app, "33-more-night")
    }

    /// The global tint leaks in through the text caret rather than through any
    /// Swift source, so it is only visible while a field has focus — which is
    /// why this is its own test.
    func testFocusedTextFieldCaretAtNight() throws {
        let app = launchDark()
        let more = app.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 10), "More tab not found")
        more.tap()
        Thread.sleep(forTimeInterval: 2)

        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "name field not found")
        field.tap()
        field.typeText("Nafees")
        Thread.sleep(forTimeInterval: 1)
        snapshot(app, "34-caret-night")
    }

    /// Review is reached from the day's end-of-day card rather than the tab
    /// bar, so this also covers that route still working.
    func testReviewScreenAtNight() throws {
        let app = launchDark()
        let review = app.buttons["Review day"].firstMatch
        XCTAssertTrue(review.waitForExistence(timeout: 10), "review-day button not found")
        review.tap()
        Thread.sleep(forTimeInterval: 2)
        snapshot(app, "35-review-night")
    }
}
