//
//  Maths_QuestUITestsLaunchTests.swift
//  Maths QuestUITests
//
//  Created by Abdullah Ozdemir on 29/01/2025.
//

import XCTest

final class Maths_QuestUITestsLaunchTests: MathsQuestUITestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    @MainActor
    func testLaunch() throws {
        launchApp()
        assertOnMainMenu()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
