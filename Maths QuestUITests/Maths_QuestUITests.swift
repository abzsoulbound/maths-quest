//
//  Maths_QuestUITests.swift
//  Maths QuestUITests
//

import XCTest

/// Launching, and moving between the main menu, the year menus and the sidebar's screens.
final class Maths_QuestUITests: MathsQuestUITestCase {

    @MainActor
    func testLaunchShowsTheMainMenu() throws {
        launchApp()
        XCTAssertEqual(app.state, .runningForeground)
        assertOnMainMenu()
        XCTAssertGreaterThanOrEqual(currentPoints(), 0)
        attachScreenshot("Main menu")
    }

    @MainActor
    func testEveryYearOpensFromTheMainMenuAndHomeReturns() throws {
        launchApp()
        for year in 1...6 {
            openYear(year)
            goHome()
        }
    }

    @MainActor
    func testSidebarOpensEveryYear() throws {
        launchApp()
        for year in 1...6 {
            openFromSidebar("Year \(year)")
            assertOnYearMenu(year)
            goHome()
        }
    }

    @MainActor
    func testSidebarOpensEveryOtherScreen() throws {
        launchApp()

        openFromSidebar("Information")
        let message = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Message from the creator.'")).firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 10), "Information didn't open.")

        openFromSidebar("Shop")
        XCTAssertTrue(text("Background Colours").waitForExistence(timeout: 10), "Shop didn't open.")
        XCTAssertTrue(text("Spend Points").exists)

        openFromSidebar("Settings")
        XCTAssertTrue(text("SFX Volume").waitForExistence(timeout: 10), "Settings didn't open.")
        XCTAssertTrue(text("Name").exists)
        XCTAssertTrue(app.sliders.firstMatch.exists)

        openFromSidebar("Remove Ads")
        XCTAssertTrue(button("Restore Purchases").waitForExistence(timeout: 10), "Remove Ads didn't open.")

        openFromSidebar("Feedback")
        XCTAssertTrue(feedbackPrivacyReminder.waitForExistence(timeout: 10), "Feedback didn't open.")

        openFromSidebar("Main Menu")
        assertOnMainMenu()
    }

    @MainActor
    func testSidebarCloseButtonClosesIt() throws {
        launchApp()
        openSidebar()
        tap(sidebarCloseButton)
        XCTAssertTrue(sidebarCloseButton.waitForNonExistence(timeout: 5), "The sidebar didn't close.")
        // The main menu works again.
        openYear(2)
    }

    @MainActor
    func testTappingBesideTheSidebarClosesIt() throws {
        launchApp()
        openSidebar()
        // The dimmed area to the right of the sidebar, over the main menu's disabled Year buttons.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(sidebarCloseButton.waitForNonExistence(timeout: 5), "The sidebar didn't close.")
        assertOnMainMenu()
        openYear(5)
    }

    @MainActor
    func testSettingsButtonOpensSettings() throws {
        launchApp()
        openYear(1)
        tap(settingsButton)
        XCTAssertTrue(text("SFX Volume").waitForExistence(timeout: 10), "Settings didn't open.")
        XCTAssertTrue(text("Name").exists)
        // Settings has the sidebar, which leads back to the main menu.
        openFromSidebar("Main Menu")
        assertOnMainMenu()
    }
}
