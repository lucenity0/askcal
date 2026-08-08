//
//  DarkModeSnapshotTests.swift
//  AskcalUITests
//
//  Captures the dark theme on screens that use the shared filled-pill and
//  toggle styles.
//
//  These exist because `PillButtonStyle` and `MonoToggleStyle` read
//  `@Environment(\.mono)` from a `ButtonStyle`/`ToggleStyle` struct. Those are
//  not Views, and if SwiftUI does not inject into them the palette silently
//  falls back to `MonoPaletteKey.defaultValue` — which is `.light`, whose
//  `fill` is #000000. On the dark theme's #000000 background that makes every
//  filled pill disappear. Reading the code cannot settle it; rendering can.
//

import XCTest

final class DarkModeSnapshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Launch in dark mode. `-themeMode dark` lands in UserDefaults, which is
    /// where @AppStorage("themeMode") reads from.
    private func launchDark() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-themeMode", "dark"]
        app.launch()

        // The notification permission alert belongs to SpringBoard, not us.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Don’t Allow", "Don't Allow", "Allow"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 3) {
                button.tap()
                break
            }
        }

        // The cold-launch greeting animation runs ~2.5s before content appears.
        Thread.sleep(forTimeInterval: 4)
        return app
    }

    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The launch scene is on screen for about two and a half seconds, so this
    /// deliberately does not use `launchDark()` — that waits the greeting out.
    func testLaunchSceneInDarkMode() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-themeMode", "slate"]
        app.launch()
        Thread.sleep(forTimeInterval: 0.9)
        snapshot(app, "05-launch-scene-slate")
    }

    func testLaunchSceneInPaperMode() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-themeMode", "paper"]
        app.launch()
        Thread.sleep(forTimeInterval: 0.9)
        snapshot(app, "06-launch-scene-paper")
    }

    func testMoreScreenInDarkMode() throws {
        let app = launchDark()
        snapshot(app, "01-today-dark")

        // More carries the densest set of shared styles: two filled pills
        // (Connect, Delete everything), the theme segmented control, and two
        // MonoToggleStyle switches.
        let more = app.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 10), "rail tab 'More' not found")
        more.tap()
        Thread.sleep(forTimeInterval: 2)
        snapshot(app, "02-more-dark")
    }

    /// The global tint leaks in through the text caret, not through any Swift
    /// source: `AccentColor.colorset` is empty while the build sets
    /// ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME, so anything reading the
    /// tint without an override falls back to system blue. Only visible while a
    /// field has focus, which is why this test exists separately.
    func testFocusedTextFieldCaretInDarkMode() throws {
        let app = launchDark()
        let more = app.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 10), "rail tab 'More' not found")
        more.tap()
        Thread.sleep(forTimeInterval: 2)

        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "name field not found")
        field.tap()
        field.typeText("Nafees")
        Thread.sleep(forTimeInterval: 1)
        snapshot(app, "04-caret-dark")
    }

    func testReviewScreenInDarkMode() throws {
        let app = launchDark()
        let review = app.buttons["Review"]
        XCTAssertTrue(review.waitForExistence(timeout: 10), "rail tab 'Review' not found")
        review.tap()
        Thread.sleep(forTimeInterval: 2)
        snapshot(app, "03-review-dark")
    }
}
