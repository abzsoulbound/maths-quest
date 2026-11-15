//
//  FeedbackBatchFBDUITests.swift
//  Maths QuestUITests
//

import XCTest

/// User feedback, batch FB-D, as a player sees it: the two changes the owner approved after batches FB-B and FB-C.
///
/// - Shapes: "diamond" or "rhombus" for the square, which is drawn standing on a corner, is still asked for again
///   rather than marked, now with "Turning it doesn't change what shape it is." and a hint card that says what a square
///   is without naming it. The card stays while the player tries again and goes with the right answer. "diamond" for
///   any other shape is wrong, with no card.
/// - Ratio: one of the ratio's two boxes left empty is asked for again with "Fill in both boxes.", as Time, Fractions
///   and Probability are. It scores nothing, doesn't count towards Skip and brings no hint. A hint from an earlier wrong
///   answer stays as it was.
///
/// The message can be read in full and the answer stays in its box, at the default and the largest text size. The hint
/// card can be scrolled to, and VoiceOver reads it as "Hint: " and the hint; what VoiceOver reads out as the message
/// appears is an announcement XCUITest can't hear, so `FBDShapeTests` checks it. The square is also answered with the
/// keyboard's Return key, which the Shapes name box has; the Ratio boxes have a number pad, which has no Return key on
/// an iPhone, so the iPad answers with Return there too. Every answer is worked out here from what the screen shows.
@MainActor
final class FeedbackBatchFBDUITests: FeedbackBatchUITestCase {

    // MARK: - Shapes: the square on its corner

    func testTheTurnedSquareBringsAHintAboutItsSidesAndCorners() throws {
        try checkTheTurnedSquare(largestText: false)
    }

    func testTheTurnedSquareBringsAHintAboutItsSidesAndCornersAtTheLargestTextSize() throws {
        try checkTheTurnedSquare(largestText: true)
    }

    /// Finds "What is this shape called?" for the square, which is drawn with 4 corners, standing on one. On the way, the
    /// first other shape to name is called "diamond": wrong, with no hint. A square that comes up before that is passed
    /// over, unanswered. Then, for the square: "diamond" with Return,
    /// and "Rhombus" with Enter, are asked for again with the hint; "triangle" is wrong and leaves the hint as it was;
    /// "a square" is right, scores once, and the hint goes.
    private func checkTheTurnedSquare(largestText: Bool) throws {
        if largestText {
            extraLaunchArguments = Self.largestText
        }
        let size = largestText ? ", largest text" : ""
        var checkedAnotherShape = false
        // One question in 18 names the square.
        try findQuestion(in: "Shapes", inYear: 2, attempts: 150) { () -> Bool? in
            guard text("What is this shape called?").waitForExistence(timeout: 2) else { return nil }
            let corners = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Corner'"))
            if corners.count == 4 {
                // Another shape is checked first, so a square that comes up before one is passed over: the next
                // attempt opens Shapes again on a new question.
                return checkedAnotherShape ? true : nil
            }
            if !checkedAnotherShape {
                checkedAnotherShape = true
                checkDiamondForAnotherShape(corners: corners.count, size)
            }
            return nil
        }
        XCTAssertTrue(checkedAnotherShape, "No other shape to name came up before the square.")
        let start = currentPoints()
        XCTAssertFalse(hintCard.exists, "Shapes\(size): a hint showed before any answer.")

        // "diamond", with the keyboard's Return key.
        replaceText(in: answerField, with: "diamond")
        XCTAssertTrue(answerField.hasKeyboardFocus, "Shapes\(size): the answer box lost its focus after typing.")
        answerField.typeText("\n")
        // The message shows for a second; typing waits for the app to settle, so it may have gone by now. The hint
        // stays, which shows that Return checked the answer.
        let afterReturn = shownMessage()
        attachText("Shapes\(size): message once Return had been typed", afterReturn ?? "already gone")
        XCTAssertTrue(afterReturn == nil || afterReturn == Self.turnedSquare,
                      "Shapes\(size): \"\(afterReturn ?? "")\" after \"diamond\" and Return.")
        XCTAssertTrue(hintCard.waitForExistence(timeout: 3), "Shapes\(size): no hint after \"diamond\" and Return.")
        XCTAssertEqual(hintCard.label, "Hint: \(Self.turnedSquareHint)", "Shapes\(size): VoiceOver reads the hint card differently.")
        XCTAssertTrue(waitQuickly(timeout: 3) { !answerField.hasKeyboardFocus }, "Shapes\(size): Return didn't put the keyboard away.")
        assertPoints(start)
        XCTAssertFalse(skipButton.exists, "Shapes\(size): Skip appeared, so \"diamond\" counted as wrong.")
        XCTAssertEqual(typedText(in: answerField), "diamond", "Shapes\(size): \"diamond\" went from the box.")
        attachScreenshot("Shapes\(size): the hint after \"diamond\"")

        // The hint stays once the message has gone, and while the player types.
        XCTAssertTrue(waitQuickly(timeout: 5) { shownMessage() == nil }, "Shapes\(size): the message didn't go.")
        pause(1)
        XCTAssertTrue(hintCard.exists, "Shapes\(size): the hint went with the message.")
        replaceText(in: answerField, with: "Rhombus")
        XCTAssertTrue(hintCard.exists, "Shapes\(size): the hint went while the player typed.")

        // "Rhombus", with Enter: the message can be read, with the hint showing. Two in a row with no Skip: neither counted.
        checkAskedAgain(Self.turnedSquare, "Shapes\(size), \"Rhombus\"", points: start,
                        boxes: [(answerField, "Rhombus")], checkReadable: true, hint: Self.turnedSquareHint)
        checkHintCanBeScrolledTo("Shapes\(size)")

        // "triangle": wrong, and the hint stays as it was.
        answer("triangle", expecting: .incorrect)
        assertPoints(start)
        XCTAssertFalse(skipButton.exists, "Shapes\(size): Skip appeared after one wrong answer.")
        XCTAssertTrue(hintCard.exists, "Shapes\(size): the hint went after a wrong answer.")
        XCTAssertEqual(hintCard.label, "Hint: \(Self.turnedSquareHint)", "Shapes\(size): the hint changed after a wrong answer.")

        // "a square": right, once, and the hint goes, and doesn't come back on the next question.
        replaceText(in: answerField, with: "a square")
        pressEnter(expectingMessage: "Correct!")
        XCTAssertTrue(hintCard.waitForNonExistence(timeout: 3), "Shapes\(size): the hint stayed after the right answer.")
        assertPoints(start + 1)
        waitForNextQuestion()
        assertPoints(start + 1)
        XCTAssertFalse(hintCard.exists, "Shapes\(size): the hint came back on the next question.")
    }

    /// "diamond" for a shape to name that isn't the square (a circle, a triangle, or a shape with 5, 6 or 8 corners):
    /// wrong, and no hint.
    private func checkDiamondForAnotherShape(corners: Int, _ size: String) {
        let when = "Shapes\(size), \"diamond\" for a shape with \(corners) corners"
        let start = currentPoints()
        answer("diamond", expecting: .incorrect)
        XCTAssertTrue(waitQuickly(timeout: 5) { shownMessage() == nil }, "\(when): the message didn't go.")
        XCTAssertFalse(hintCard.exists, "\(when): a hint showed.")
        assertPoints(start)
        attachText("Shapes\(size): \"diamond\" for another shape", "\(corners) corners: Incorrect, no hint")
    }

    /// With the keyboard put away, scrolls up as a player would until the hint card is entirely in view, then checks
    /// what VoiceOver reads for it. It sits under Enter, where at the largest text size it can be below the bottom edge.
    private func checkHintCanBeScrolledTo(_ when: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitQuickly(timeout: 5) { shownMessage() == nil }, "\(when): the message didn't go.",
                      file: file, line: line)
        hideKeyboardByTappingBackground(file: file, line: line)
        var drags = 0
        for _ in 1...6 {
            let area = visibleArea(of: questionParts())
            let card = hintCard.frame
            guard !area.isEmpty, !card.isEmpty, card.maxY > area.maxY + 0.5 else {
                break
            }
            let startY = min(area.maxY, windowFrame.maxY - 50) - 10
            let shift = min(card.maxY - area.maxY + 20, startY - area.minY - 10)
            guard shift > 4 else {
                break
            }
            dragQuestionArea(fromY: startY, toY: startY - shift)
            _ = waitForFrameToSettle(of: hintCard, timeout: 2, steadyFor: 0.3)
            drags += 1
        }
        attachText("\(when): drags to bring the hint into view", "\(drags)")
        attachScreenshot("\(when): the hint in view")
        assertFullyVisible(hintCard, "\(when): the hint card", within: visibleArea(of: questionParts()), tappable: false,
                           file: file, line: line)
        XCTAssertTrue(hintCard.label.hasPrefix("Hint: "), "\(when): VoiceOver reads the hint as \"\(hintCard.label)\".",
                      file: file, line: line)
    }

    // MARK: - Ratio: one box left empty

    func testRatioAsksForBothBoxes() throws {
        try checkRatioWithOneBoxEmpty(largestText: false)
    }

    func testRatioAsksForBothBoxesAtTheLargestTextSize() throws {
        try checkRatioWithOneBoxEmpty(largestText: true)
    }

    /// "Simplify the ratio 6 to 9" or "Divide 35 in the ratio 3 to 4". The first number alone, then the second alone,
    /// are asked for again with no hint; then the right answer scores once. On an iPad, the second is entered with
    /// Return.
    private func checkRatioWithOneBoxEmpty(largestText: Bool) throws {
        if largestText {
            extraLaunchArguments = Self.largestText
        }
        let size = largestText ? ", largest text" : ""
        let (label, answer) = try findQuestion(in: "Ratios", inYear: 6) { () -> (String, [Int])? in
            readTwoBoxRatio()
        }
        attachText("Ratio question\(size)", "\(label) Answer \(answer[0]) to \(answer[1])")
        let start = currentPoints()
        let first = box(labelled: "First part of the ratio")
        let second = box(labelled: "Second part of the ratio")

        replaceText(in: first, with: "\(answer[0])")
        checkAskedAgain(Self.fillInBothBoxes, "Ratio\(size), the second box empty", points: start,
                        boxes: [(first, "\(answer[0])"), (second, "")], checkReadable: true)

        clear(first)
        replaceText(in: second, with: "\(answer[1])")
        let when = "Ratio\(size), the first box empty"
        if UIDevice.current.userInterfaceIdiom == .pad {
            // The message shows for a second and a half, which typing Return leaves time to see.
            XCTAssertTrue(waitQuickly(timeout: 5) { shownMessage() == nil }, "\(when): the last message didn't go.")
            XCTAssertTrue(second.hasKeyboardFocus, "\(when): the second box lost its focus after typing.")
            second.typeText("\n")
            var shown: String?
            _ = waitQuickly(timeout: 2) {
                shown = shownMessage()
                return shown != nil
            }
            XCTAssertEqual(shown, Self.fillInBothBoxes, "\(when), with Return: unexpected message.")
            assertPoints(start)
            XCTAssertFalse(skipButton.exists, "\(when): Skip appeared, so the answer counted as wrong.")
            XCTAssertFalse(hintCard.exists, "\(when): a hint appeared, so the answer was marked.")
            XCTAssertEqual(typedText(in: first), "", "\(when): the first box changed.")
            XCTAssertEqual(typedText(in: second), "\(answer[1])", "\(when): the second box changed.")
        } else {
            checkAskedAgain(Self.fillInBothBoxes, when, points: start,
                            boxes: [(first, ""), (second, "\(answer[1])")])
        }

        replaceText(in: first, with: "\(answer[0])")
        pressEnter(expectingMessage: "Correct!")
        assertPoints(start + 1)
        waitForNextQuestion()
        assertPoints(start + 1)
        XCTAssertFalse(hintCard.exists, "Ratio\(size): a hint showed on the next question.")
    }

    /// A wrong answer brings a hint and counts once. One box then left empty is asked for again: the hint stays as it
    /// was, and Skip doesn't appear, so the empty box didn't count as a second wrong answer. The right answer then
    /// scores once and the hint goes.
    func testRatioKeepsAnEarlierHintWhenABoxIsLeftEmpty() throws {
        let (label, answer) = try findQuestion(in: "Ratios", inYear: 6) { () -> (String, [Int])? in
            readTwoBoxRatio()
        }
        attachText("Ratio question", "\(label) Answer \(answer[0]) to \(answer[1])")
        let start = currentPoints()
        let first = box(labelled: "First part of the ratio")
        let second = box(labelled: "Second part of the ratio")

        // 99 to 99 is never the answer: no simplest ratio or share here is 99 to 99.
        replaceText(in: first, with: "99")
        replaceText(in: second, with: "99")
        pressEnter(expectingMessage: Feedback.incorrect.rawValue)
        XCTAssertTrue(hintCard.waitForExistence(timeout: 3), "No hint after a wrong answer.")
        let hint = hintCard.label
        attachText("Ratio hint after 99 to 99", hint)
        XCTAssertTrue(hint.hasPrefix("Hint: "), "VoiceOver reads the hint as \"\(hint)\".")
        XCTAssertFalse(skipButton.exists, "Skip appeared after one wrong answer.")
        assertPoints(start)

        clear(second)
        checkAskedAgain(Self.fillInBothBoxes, "Ratio, the second box emptied after a wrong answer", points: start,
                        boxes: [(first, "99"), (second, "")], checkReadable: true, hint: String(hint.dropFirst(6)))
        XCTAssertTrue(waitQuickly(timeout: 5) { shownMessage() == nil }, "\"Fill in both boxes.\" didn't go.")
        pause(1)
        XCTAssertEqual(hintCard.label, hint, "The hint changed after one box was left empty.")
        XCTAssertFalse(skipButton.exists, "Skip appeared, so the empty box counted as a second wrong answer.")

        replaceText(in: first, with: "\(answer[0])")
        replaceText(in: second, with: "\(answer[1])")
        pressEnter(expectingMessage: "Correct!")
        XCTAssertTrue(hintCard.waitForNonExistence(timeout: 3), "The hint stayed after the right answer.")
        assertPoints(start + 1)
        waitForNextQuestion()
        assertPoints(start + 1)
        XCTAssertFalse(hintCard.exists, "The hint came back on the next question.")
    }

    // MARK: - Reading questions

    /// A Ratio question answered in two boxes, and its answer worked out here, as in FeedbackBatchFBBUITests.
    private func readTwoBoxRatio() -> (String, [Int])? {
        let predicate = NSPredicate(format: "label BEGINSWITH 'Simplify the ratio ' OR label BEGINSWITH 'Divide '")
        let element = app.staticTexts.matching(predicate).firstMatch
        guard element.waitForExistence(timeout: 3), let label = (try? element.snapshot())?.label else { return nil }
        if let match = label.wholeMatch(of: #/Simplify the ratio (\d+) to (\d+)/#), let a = Int(match.1), let b = Int(match.2) {
            var (larger, smaller) = (max(a, b), min(a, b))
            while smaller != 0 {
                (larger, smaller) = (smaller, larger % smaller)
            }
            return (label, [a / larger, b / larger])
        }
        if let match = label.wholeMatch(of: #/Divide (\d+) in the ratio (\d+) to (\d+)/#),
           let total = Int(match.1), let a = Int(match.2), let b = Int(match.3) {
            let part = total / (a + b)
            return (label, [a * part, b * part])
        }
        return nil
    }
}
