//
//  ActivityUITests.swift
//  Maths QuestUITests
//

import XCTest

/// Every activity opens from its year menu, and its home button returns to the main menu. Each year
/// is a separate test so that each one stays well inside the 180 seconds before an interstitial.
final class ActivityUITests: MathsQuestUITestCase {

    @MainActor
    func testYear1ActivitiesOpen() throws {
        openEveryActivity(inYear: 1)
    }

    @MainActor
    func testYear2ActivitiesOpen() throws {
        openEveryActivity(inYear: 2)
    }

    @MainActor
    func testYear3ActivitiesOpen() throws {
        openEveryActivity(inYear: 3)
    }

    @MainActor
    func testYear4ActivitiesOpen() throws {
        openEveryActivity(inYear: 4)
    }

    @MainActor
    func testYear5ActivitiesOpen() throws {
        openEveryActivity(inYear: 5)
    }

    @MainActor
    func testYear6ActivitiesOpen() throws {
        openEveryActivity(inYear: 6)
    }

    @MainActor
    private func openEveryActivity(inYear year: Int, file: StaticString = #filePath, line: UInt = #line) {
        launchApp(file: file, line: line)
        for activity in Self.activities[year] ?? [] {
            openYear(year, file: file, line: line)
            openActivity(activity, file: file, line: line)
            attachScreenshot("Year \(year) \(activity)")
            goHome(file: file, line: line)
        }
    }
}
