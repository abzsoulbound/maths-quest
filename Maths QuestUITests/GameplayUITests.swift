//
//  GameplayUITests.swift
//  Maths QuestUITests
//

import XCTest

/// Answering questions: marking, scoring and moving on to the next question. Points are kept between
/// launches, so the tests check how much they change rather than their value.
final class GameplayUITests: MathsQuestUITestCase {

    @MainActor
    func testCorrectAdditionScoresAndMovesOnToTheNextQuestion() throws {
        launchApp()
        openYear(1)
        openActivity("Addition")
        let start = currentPoints()

        let (a, b) = operands(using: "+")
        answer("\(a + b)", expecting: .correct)
        assertPoints(start + 1)
        waitForNextQuestion()
        XCTAssertFalse(skipButton.exists)

        // The next question is marked against its own numbers.
        let (c, d) = operands(using: "+")
        answer("\(c + d)", expecting: .correct)
        assertPoints(start + 2)
        waitForNextQuestion()
    }

    @MainActor
    func testPressingEnterAgainDoesNotScoreTwice() throws {
        launchApp()
        openYear(1)
        openActivity("Addition")
        let start = currentPoints()

        let (a, b) = operands(using: "+")
        replaceText(in: answerField, with: "\(a + b)")
        tap(enterButton)
        tap(enterButton)
        waitForNextQuestion()
        assertPoints(start + 1)
    }

    @MainActor
    func testWrongAnswerDoesNotScoreAndKeepsTheQuestion() throws {
        launchApp()
        openYear(1)
        openActivity("Addition")
        let start = currentPoints()
        let shownQuestion = question(using: "+")
        let (a, b) = operands(using: "+")

        answer("\(a + b + 1)", expecting: .incorrect)
        assertPoints(start)
        XCTAssertEqual(question(using: "+"), shownQuestion)
        XCTAssertEqual(typedText(in: answerField), "\(a + b + 1)", "The wrong answer should stay to be corrected.")
        XCTAssertFalse(skipButton.exists, "Skip appeared after one wrong answer.")

        answer("\(a + b)", expecting: .correct)
        assertPoints(start + 1)
        waitForNextQuestion()
    }

    @MainActor
    func testCorrectSubtractionScores() throws {
        launchApp()
        openYear(1)
        openActivity("Subtraction")
        let start = currentPoints()

        let (a, b) = operands(using: "minus")
        XCTAssertGreaterThanOrEqual(a, b, "Subtraction asked for a negative answer.")
        answer("\(a - b)", expecting: .correct)
        assertPoints(start + 1)
        waitForNextQuestion()
    }

    @MainActor
    func testCorrectCountingAnswerScores() throws {
        launchApp()
        openYear(1)
        openActivity("Counting")
        let start = currentPoints()

        answer("\(missingCountingNumber())", expecting: .correct)
        assertPoints(start + 1)
        waitForNextQuestion()
    }

    @MainActor
    func testBlankCountingAnswerAsksForOneWithoutCountingAsWrong() throws {
        launchApp()
        openYear(1)
        openActivity("Counting")
        let start = currentPoints()

        for _ in 0..<3 {
            pressEnter(expecting: .unanswered)
        }
        assertPoints(start)
        XCTAssertFalse(skipButton.exists, "A blank answer counted as a wrong one.")
    }

    @MainActor
    func testCorrectMultiplicationScores() throws {
        launchApp()
        openYear(2)
        openActivity("Multiplication")
        let start = currentPoints()

        let (a, b) = operands(using: "times")
        answer("\(a * b)", expecting: .correct)
        assertPoints(start + 1)
        waitForNextQuestion()
    }

    @MainActor
    func testCorrectDivisionScores() throws {
        launchApp()
        openYear(2)
        openActivity("Division")
        let start = currentPoints()

        let (dividend, divisor) = operands(using: "÷")
        XCTAssertGreaterThan(divisor, 0)
        XCTAssertEqual(dividend % divisor, 0, "\(dividend) ÷ \(divisor) doesn't have a whole-number answer.")
        answer("\(dividend / divisor)", expecting: .correct)
        assertPoints(start + 1)
        waitForNextQuestion()
    }
}
