//
//  SkipQuestionUITests.swift
//  Maths QuestUITests
//

import XCTest

/// Skip Question appears after two wrong answers and needs a rewarded ad, which in these Debug builds
/// is always Google's test ad.
final class SkipQuestionUITests: MathsQuestUITestCase {

    @MainActor
    func testSkipAppearsOnlyAfterTwoWrongAnswers() throws {
        launchApp()
        openYear(1)
        openActivity("Addition")
        let start = currentPoints()
        XCTAssertFalse(skipButton.exists, "Skip showed before any wrong answers.")

        answerWronglyTwice()
        assertPoints(start)
    }

    @MainActor
    func testDecliningTheAdKeepsTheQuestion() throws {
        launchApp()
        openYear(1)
        openActivity("Addition")
        let start = currentPoints()
        let shownQuestion = question(using: "+")
        let (a, b) = operands(using: "+")
        answerWronglyTwice()

        try tapSkipUntilAdIsOffered()
        let offer = app.alerts["Skip this question?"]
        tap(offer.buttons["No thanks"])
        XCTAssertTrue(offer.waitForNonExistence(timeout: 5), "The offer to watch an ad didn't close.")
        XCTAssertFalse(text("Test mode").exists, "An ad played after No thanks.")

        XCTAssertEqual(question(using: "+"), shownQuestion, "No thanks changed the question.")
        XCTAssertTrue(skipButton.exists, "Skip went away after No thanks.")
        assertPoints(start)

        // The question can still be answered for a point.
        answer("\(a + b)", expecting: .correct)
        assertPoints(start + 1)
        waitForNextQuestion()
        XCTAssertFalse(skipButton.exists, "Skip carried over to the next question.")
    }

    @MainActor
    func testWatchingTheTestAdSkipsTheQuestionWithoutAPoint() throws {
        launchApp()
        openYear(1)
        openActivity("Addition")
        let start = currentPoints()
        answerWronglyTwice()

        try tapSkipUntilAdIsOffered()
        tap(app.alerts["Skip this question?"].buttons["Watch ad"])
        closeRewardedTestAd()

        waitForNextQuestion()
        XCTAssertTrue(skipButton.waitForNonExistence(timeout: 5), "Skip still showed on the next question.")
        assertPoints(start)

        // The new question scores as usual.
        let (a, b) = operands(using: "+")
        answer("\(a + b)", expecting: .correct)
        assertPoints(start + 1)
    }
}
