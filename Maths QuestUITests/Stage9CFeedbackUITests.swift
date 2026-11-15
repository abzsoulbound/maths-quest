//
//  Stage9CFeedbackUITests.swift
//  Maths QuestUITests
//

import XCTest

/// Stage 9C, Batch 1: what the four activities show after an answer, as a player sees it.
///
/// After a counted wrong answer, a hint card under Enter and Skip. It stays after "Incorrect. Try Again!" fades, says
/// what went wrong when the answer shows it, and never gives the answer. A second wrong answer can change it.
///
/// After a right answer, "Correct!" with the finished number sentence under it, and the hint goes. The point is scored
/// as before.
///
/// After a rewarded Skip, the question stays, worked out step by step, until Next Question. The answer boxes, the unit
/// wheel and Enter can't be used, no point is given, and leaving the app and coming back keeps it. Tapping Next
/// Question twice brings one new question, which scores as usual.
///
/// Every answer the tests give is worked out here from what the screen shows (and what VoiceOver reads), not taken
/// from the app.
///
/// The rewarded test ad is closed with its × only. Skip without an ad, after Remove Ads is bought, can't be reached
/// here without a purchase; it runs the same code as soon as Skip is tapped.
@MainActor
final class Stage9CFeedbackUITests: MathsQuestUITestCase {

    // MARK: Year 2 Multiplication

    func testMultiplicationHintThenCorrectLine() throws {
        launchApp()
        openYear(2)
        openActivity("Multiplication")
        let start = currentPoints()

        // 2 × 2 is the one question where adding gives the answer, and a question with 1 in it is a single group
        // with a hint of its own. Move past them.
        var (a, b) = operands(using: "times")
        while a + b == a * b || min(a, b) == 1 {
            answer("\(a * b)", expecting: .correct)
            waitForNextQuestion()
            (a, b) = operands(using: "times")
        }
        let scoredAlready = currentPoints() - start

        // 99 is never the product, the two numbers added or a group out (a multiple of 2, 5 or 10): the hint is a
        // way to work it out. It counts in the times table the question comes from (the larger, if both numbers
        // are in the 2, 5 and 10 times tables), turned round first when that table is written first.
        let tables = [2, 5, 10]
        let step = tables.contains(a) && tables.contains(b) ? max(a, b) : (tables.contains(a) ? a : b)
        let groups = a * b / step
        let countIn = "Count in \([2: "twos", 5: "fives", 10: "tens"][step] ?? "\(step)s")."
        let expectedFirstHint = a == groups
            ? "Hint: \(groups) groups of \(step). \(countIn)"
            : "Hint: \(a) times \(b) is the same as \(groups) times \(step). \(countIn)"
        answer("99", expecting: .incorrect)
        let firstHint = checkHintStays(withoutGiving: a * b, from: [a, b])
        XCTAssertEqual(firstHint, expectedFirstHint, "For \(a) times \(b).")
        attachScreenshot("Multiplication hint after a wrong answer")

        // Adding the numbers: the hint says so.
        answer("\(a + b)", expecting: .incorrect)
        let secondHint = checkHintStays(withoutGiving: a * b, from: [a, b])
        XCTAssertTrue(secondHint.hasPrefix("Hint: Times means groups of, not adding."),
                      "The hint after adding is \"\(secondHint)\".")
        XCTAssertNotEqual(firstHint, secondHint, "The hint didn't change after a different wrong answer.")
        XCTAssertTrue(skipButton.exists, "Skip didn't show after two wrong answers.")
        attachScreenshot("Multiplication hint after adding")
        assertPoints(start + scoredAlready)

        checkCorrectLine(answer: a * b, line: "\(a) times \(b) equals \(a * b)")
        assertPoints(start + scoredAlready + 1)
        waitForNextQuestion()
        XCTAssertFalse(hintCard.exists, "The hint stayed on the next question.")
    }

    func testMultiplicationSkipShowsWorkedSolution() throws {
        launchApp()
        openYear(2)
        openActivity("Multiplication")
        let start = currentPoints()
        let (a, b) = operands(using: "times")
        try checkSkipShowsWorkedSolution(question: "\(a) times \(b)", symbol: "times", answer: a * b, points: start) {
            let (a, b) = self.operands(using: "times")
            return a * b
        }
    }

    // MARK: Year 2 Division

    func testDivisionHintThenCorrectLine() throws {
        launchApp()
        openYear(2)
        openActivity("Division")
        let start = currentPoints()
        let (dividend, divisor) = operands(using: "÷")
        let quotient = dividend / divisor

        answer("99", expecting: .incorrect)
        let name = [2: "twos", 5: "fives", 10: "tens"][divisor] ?? "\(divisor)s"
        let firstHint = checkHintStays(withoutGiving: quotient, from: [dividend, divisor])
        XCTAssertEqual(firstHint, "Hint: How many \(name) make \(dividend)? Count in \(name).")
        attachScreenshot("Division hint after a wrong answer")

        // Multiplying the numbers: the hint says so.
        answer("\(dividend * divisor)", expecting: .incorrect)
        let secondHint = checkHintStays(withoutGiving: quotient, from: [dividend, divisor])
        XCTAssertEqual(secondHint, "Hint: Divided by means sharing or grouping, not multiplying. "
                       + "The answer is smaller than \(dividend).")
        attachScreenshot("Division hint after multiplying")
        assertPoints(start)

        checkCorrectLine(answer: quotient, line: "\(dividend) divided by \(divisor) equals \(quotient)")
        assertPoints(start + 1)
        waitForNextQuestion()
        XCTAssertFalse(hintCard.exists, "The hint stayed on the next question.")
    }

    func testDivisionSkipShowsWorkedSolution() throws {
        launchApp()
        openYear(2)
        openActivity("Division")
        let start = currentPoints()
        let (dividend, divisor) = operands(using: "÷")
        try checkSkipShowsWorkedSolution(question: "\(dividend) ÷ \(divisor)", symbol: "÷", answer: dividend / divisor,
                                         points: start) {
            let (dividend, divisor) = self.operands(using: "÷")
            return dividend / divisor
        }
    }

    // MARK: Year 4 Geometry

    /// The area typed for the perimeter, then the perimeter with no unit picked: each has its own hint.
    func testGeometryPerimeterHintsThenCorrectLine() throws {
        // A rectangle or square whose area isn't its perimeter, so typing the area is a mistake of its own.
        let shape = try findQuestion(in: "Geometry", inYear: 4) { () -> GeometryQuestion? in
            guard let shown = readGeometryQuestion(timeout: 3), shown.kind == .perimeter, let area = shown.area,
                  area != shown.perimeter else { return nil }
            return shown
        }
        attachText("Geometry question", shape.description)
        let start = currentPoints()

        answer("\(shape.area ?? 0)", expecting: .incorrect)
        let firstHint = checkHintStays(withoutGiving: [shape.perimeter], from: shape.sides)
        XCTAssertEqual(firstHint, "Hint: That is the area. Perimeter is the distance all the way round: add every side.")
        attachScreenshot("Geometry hint after the area for the perimeter")

        // The right number, with the wheel still on "Unit".
        replaceText(in: answerField, with: "\(shape.perimeter)")
        pressEnter(expectingMessage: Self.wrongUnitMessage)
        let secondHint = checkHintStays(withoutGiving: [], from: shape.sides)
        XCTAssertEqual(secondHint, "Hint: Pick a unit as well. Perimeter is a length: use the same unit as the sides.")
        XCTAssertTrue(skipButton.exists, "Skip didn't show after two wrong answers.")
        attachScreenshot("Geometry hint after no unit")
        assertPoints(start)

        checkCorrectLine(shape.correctLine) { pickUnit(shape.answerUnit) }
        assertPoints(start + 1)
        waitForNextQuestion()
        XCTAssertFalse(hintCard.exists, "The hint stayed on the next question.")
    }

    /// The perimeter typed for the area, then the area with the wrong square unit: each has its own hint.
    func testGeometryAreaHintsThenCorrectLine() throws {
        let shape = try findQuestion(in: "Geometry", inYear: 4) { () -> GeometryQuestion? in
            guard let shown = readGeometryQuestion(timeout: 3), shown.kind == .area, let area = shown.area,
                  area != shown.perimeter else { return nil }
            return shown
        }
        attachText("Geometry question", shape.description)
        let start = currentPoints()

        answer("\(shape.perimeter)", expecting: .incorrect)
        let firstHint = checkHintStays(withoutGiving: [shape.answer], from: shape.sides)
        XCTAssertEqual(firstHint, "Hint: That is the perimeter. Area is the space inside: multiply length by width.")
        attachScreenshot("Geometry hint after the perimeter for the area")

        // The right number, with a square unit that isn't the sides' unit.
        let otherUnit = (["mm", "cm", "m", "km"].first { $0 != shape.unit } ?? "mm") + "²"
        replaceText(in: answerField, with: "\(shape.answer)")
        pickUnit(otherUnit)
        pressEnter(expectingMessage: Self.wrongUnitMessage)
        let secondHint = checkHintStays(withoutGiving: [], from: shape.sides)
        XCTAssertEqual(secondHint, "Hint: Area is measured in square units. Pick the one that matches the sides.")
        XCTAssertTrue(skipButton.exists, "Skip didn't show after two wrong answers.")
        attachScreenshot("Geometry hint after the wrong unit")
        assertPoints(start)

        checkCorrectLine(shape.correctLine) { pickUnit(shape.answerUnit) }
        assertPoints(start + 1)
        waitForNextQuestion()
        XCTAssertFalse(hintCard.exists, "The hint stayed on the next question.")
    }

    /// The hint for an angle is the same whatever the angle, and names neither of the other two types.
    func testGeometryAngleHintThenCorrectLine() throws {
        let angle = try findQuestion(in: "Geometry", inYear: 4) { () -> GeometryQuestion? in
            guard let shown = readGeometryQuestion(timeout: 3), shown.kind == .angle else { return nil }
            return shown
        }
        attachText("Geometry question", angle.description)
        let start = currentPoints()

        answer(angle.angle == "acute" ? "Obtuse" : "Acute", expecting: .incorrect)
        let hint = checkHintStays(withoutGiving: [], from: [])
        XCTAssertEqual(hint, "Hint: Compare the angle with a square corner (a right angle).")
        for type in ["acute", "obtuse"] {
            XCTAssertFalse(hint.lowercased().contains(type), "The angle hint names \(type): \"\(hint)\".")
        }
        attachScreenshot("Geometry hint for an angle")
        assertPoints(start)

        checkCorrectLine(angle.correctLine) {
            replaceText(in: answerField, with: (angle.angle ?? "").capitalized)
        }
        assertPoints(start + 1)
        waitForNextQuestion()
        XCTAssertFalse(hintCard.exists, "The hint stayed on the next question.")
    }

    func testGeometrySkipShowsWorkedSolution() throws {
        // A shape, whose picture has to stay in view with its solution. 99 is the wrong answer, so not 9 × 11.
        let shape = try findQuestion(in: "Geometry", inYear: 4) { () -> GeometryQuestion? in
            guard let shown = readGeometryQuestion(timeout: 3), shown.kind != .angle, shown.answer != 99 else { return nil }
            return shown
        }
        attachText("Geometry question", shape.description)
        let start = currentPoints()
        try checkSkipShowsWorkedSolution(
            answerLabel: "The answer is \(shape.spokenAnswer).", points: start,
            readQuestion: { readGeometryQuestion()?.description ?? "No Geometry question" },
            questionParts: [("The question", text(shape.questionText)), ("The shape", geometryPicture)],
            answerNext: { answerGeometryCorrectly() })
    }

    // MARK: Year 6 Ratio

    /// One question of each sort (simplify, share and find the missing number) with a wrong answer the hint names,
    /// then its right answer and the line under "Correct!".
    func testRatiosHintsThenCorrectLines() throws {
        launchApp()
        openYear(6)
        openActivity("Ratios")
        var points = currentPoints()
        var checked: Set<String> = []
        for _ in 1...30 where checked.count < 3 {
            guard let question = readRatioQuestion() else {
                return XCTFail("No Ratio question on screen.")
            }
            if checked.contains(question.sort) {
                fillRatio(with: question.answer)
                pressEnter(expecting: .correct)
            } else {
                attachText("Ratio question", question.label)
                let (wrong, expectedHint) = question.namedMistake
                fillRatio(with: wrong)
                pressEnter(expecting: .incorrect)
                let hint = checkHintStays(withoutGiving: question.answer, from: question.numbers)
                XCTAssertEqual(hint, expectedHint, "After \(wrong) for \"\(question.label)\".")
                attachScreenshot("Ratio hint: \(question.sort)")
                assertPoints(points)
                checkCorrectLine(question.correctLine) { fillRatio(with: question.answer) }
                checked.insert(question.sort)
            }
            points += 1
            assertPoints(points)
            waitForNextQuestion()
            XCTAssertFalse(hintCard.exists, "The hint stayed on the next question.")
        }
        XCTAssertEqual(checked, ["simplify", "share", "missing number"], "Not every sort of Ratio question came up.")
    }

    func testRatiosSkipShowsWorkedSolution() throws {
        launchApp()
        openYear(6)
        openActivity("Ratios")
        var points = currentPoints()
        // A share question, the one with the most steps.
        var question = try XCTUnwrap(readRatioQuestion())
        for _ in 1...30 where question.kind != .share {
            fillRatio(with: question.answer)
            pressEnter(expecting: .correct)
            points += 1
            assertPoints(points)
            waitForNextQuestion()
            question = try XCTUnwrap(readRatioQuestion())
        }
        guard question.kind == .share else {
            return XCTFail("No share question in 30 Ratio questions.")
        }
        attachText("Ratio question", question.label)
        // 99 in both boxes is a wrong answer: no share is 99 to 99. Two wrong answers type 99 in the first box. (One
        // box left empty was a wrong answer too, until feedback batch FB-D asked for both boxes instead.)
        let secondBox = app.textFields.matching(NSPredicate(format: "label == %@", "Second part of the ratio")).firstMatch
        replaceText(in: secondBox, with: "99")
        try checkSkipShowsWorkedSolution(
            answerLabel: "The answer is \(question.answer[0]) to \(question.answer[1]).", points: points,
            readQuestion: { readRatioQuestion()?.label ?? "No Ratio question" },
            questionParts: [("The question", text(question.label))],
            answerNext: { answerRatioCorrectly() })
    }

    // MARK: Enter twice

    /// A right answer with Enter tapped twice scores once and brings one new question, with no hint, in each Batch 1
    /// activity, where Stage 9C changed how Enter's label moves when the message shows.
    func testPressingEnterTwiceScoresOnce() throws {
        for (activity, year) in [("Multiplication", 2), ("Division", 2), ("Geometry", 4), ("Ratios", 6)] {
            launchApp()
            openYear(year)
            openActivity(activity)
            let start = currentPoints()
            let question: String
            switch activity {
            case "Multiplication":
                question = self.question(using: "times")
                let (a, b) = operands(using: "times")
                replaceText(in: answerField, with: "\(a * b)")
            case "Division":
                question = self.question(using: "÷")
                let (dividend, divisor) = operands(using: "÷")
                replaceText(in: answerField, with: "\(dividend / divisor)")
            case "Geometry":
                let shown = try XCTUnwrap(readGeometryQuestion())
                question = shown.description
                if let angle = shown.angle {
                    replaceText(in: answerField, with: angle.capitalized)
                } else {
                    replaceText(in: answerField, with: "\(shown.answer)")
                    pickUnit(shown.answerUnit)
                }
            default:
                let shown = try XCTUnwrap(readRatioQuestion())
                question = shown.label
                fillRatio(with: shown.answer)
            }
            attachText("\(activity) question", question)
            tap(enterButton)
            tap(enterButton)
            waitForNextQuestion()
            assertPoints(start + 1)
            XCTAssertFalse(hintCard.exists, "\(activity): a hint showed after a right answer.")
            XCTAssertFalse(skipButton.exists, "\(activity): Skip showed after a right answer.")
            let message = shownMessage()
            XCTAssertTrue(message == nil || message == Feedback.unanswered.rawValue,
                          "\(activity): unexpected message on the new question: \(message ?? "").")
            pause(2)
            assertPoints(start + 1)
        }
    }

    // MARK: Checks

    static let wrongUnitMessage = "Correct number, but wrong unit!"

    var hintCard: XCUIElement { app.descendants(matching: .any)["HintCard"] }
    var solutionHeading: XCUIElement { app.descendants(matching: .any)["WorkedSolutionHeading"] }
    var solutionAnswer: XCUIElement { app.descendants(matching: .any)["WorkedSolutionAnswer"] }
    var nextQuestionButton: XCUIElement { app.buttons["NextQuestionButton"] }
    var correctLine: XCUIElement { app.descendants(matching: .any)["AnswerFeedbackDetail"] }

    /// Any message after Enter, including "Correct number, but wrong unit!", which `visibleFeedback()` doesn't look for.
    func shownMessage() -> String? {
        let message = app.staticTexts.matching(NSPredicate(format: "label IN %@", Self.feedbackMessages)).firstMatch
        return (try? message.snapshot())?.label
    }

    /// `pressEnter(expecting:)` for a message that isn't one of `Feedback`.
    func pressEnter(expectingMessage expected: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitQuickly(timeout: 5) { shownMessage() == nil && enterButton.isEnabled },
                      "Enter didn't become available again.", file: file, line: line)
        tap(enterButton, file: file, line: line)
        var shown: String?
        _ = waitQuickly(timeout: 3) {
            shown = shownMessage()
            return shown != nil
        }
        XCTAssertEqual(shown, expected, "Unexpected message after Enter.", file: file, line: line)
    }

    @discardableResult
    func checkHintStays(withoutGiving answer: Int, from shown: [Int],
                        file: StaticString = #filePath, line: UInt = #line) -> String {
        checkHintStays(withoutGiving: [answer], from: shown, file: file, line: line)
    }

    /// After a wrong answer's message: the hint card shows, and is still there once the message has gone and a moment
    /// after. It must not give any number of the answer, unless the question shows that number too. Returns what
    /// VoiceOver reads for it.
    @discardableResult
    func checkHintStays(withoutGiving answer: [Int], from shown: [Int],
                        file: StaticString = #filePath, line: UInt = #line) -> String {
        XCTAssertTrue(hintCard.waitForExistence(timeout: 3), "No hint after a wrong answer.", file: file, line: line)
        XCTAssertTrue(waitQuickly(timeout: 5) { shownMessage() == nil },
                      "The message after Enter didn't go.", file: file, line: line)
        pause(2)
        XCTAssertTrue(hintCard.exists, "The hint went with the message.", file: file, line: line)
        let label = hintCard.label
        XCTAssertTrue(label.hasPrefix("Hint: "), "The hint reads \"\(label)\".", file: file, line: line)
        let numbers = label.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        for number in answer where !shown.contains(number) {
            XCTAssertFalse(numbers.contains(number), "The hint gives the answer's \(number): \"\(label)\".",
                           file: file, line: line)
        }
        assertAnswerAndEnterInView("with the hint showing", file: file, line: line)
        // The hint is under Enter and Skip; with the keyboard down, it comes into view with them.
        assertFullyVisible(hintCard, "with the hint showing: the hint", within: visibleQuestionArea, tappable: false,
                           file: file, line: line)
        return label
    }

    /// Enters the right answer and checks the line under "Correct!" while it shows, and that the hint has gone.
    func checkCorrectLine(answer: Int, line expected: String, file: StaticString = #filePath, line: UInt = #line) {
        checkCorrectLine(expected, file: file, line: line) {
            replaceText(in: answerField, with: "\(answer)", file: file, line: line)
        }
    }

    /// Enters the right answer with `fill`, then Enter, and checks the line under "Correct!" while it shows, and that
    /// the hint has gone.
    func checkCorrectLine(_ expected: String, file: StaticString = #filePath, line: UInt = #line,
                          enteringTheAnswer fill: () -> Void) {
        fill()
        XCTAssertTrue(waitQuickly(timeout: 5) { shownMessage() == nil && enterButton.isEnabled },
                      "Enter didn't become available again.", file: file, line: line)
        tap(enterButton, file: file, line: line)
        var detail: String?
        var feedback: String?
        _ = waitQuickly(timeout: 3) {
            let snapshot = try? correctLine.snapshot()
            detail = snapshot?.label
            feedback = shownMessage() ?? feedback
            return detail != nil
        }
        attachScreenshot("Correct with its line")
        XCTAssertEqual(feedback ?? shownMessage(), Feedback.correct.rawValue, file: file, line: line)
        XCTAssertEqual(detail, expected, "Wrong line under \"Correct!\".", file: file, line: line)
        XCTAssertFalse(hintCard.exists, "The hint stayed after the right answer.", file: file, line: line)
    }

    /// `checkSkipShowsWorkedSolution(answerLabel:points:readQuestion:questionParts:answerNext:)` for a question
    /// such as "7 times 2", answered with one number.
    func checkSkipShowsWorkedSolution(question: String, symbol: String, answer: Int, points start: Int,
                                      nextAnswer: () -> Int,
                                      file: StaticString = #filePath, line: UInt = #line) throws {
        try checkSkipShowsWorkedSolution(
            answerLabel: "The answer is \(answer).", points: start,
            readQuestion: { self.question(using: symbol, file: file, line: line) },
            questionParts: [("The question", text(question))],
            answerNext: { self.answer("\(nextAnswer())", expecting: .correct, file: file, line: line) },
            file: file, line: line)
    }

    /// Two wrong answers, then Skip with the rewarded test ad: the worked solution shows until Next Question, and
    /// stays when the app goes to the background and back. Next Question, tapped twice, brings one new question that
    /// scores as usual. `readQuestion` reads the question on screen, `questionParts` must be in view with the
    /// solution, and `answerNext` answers the new question correctly.
    func checkSkipShowsWorkedSolution(answerLabel: String, points start: Int, readQuestion: () -> String,
                                      questionParts: [(String, XCUIElement)], answerNext: () -> Void,
                                      file: StaticString = #filePath, line: UInt = #line) throws {
        let question = readQuestion()
        answerWronglyTwice(file: file, line: line)
        XCTAssertTrue(hintCard.exists, "No hint after two wrong answers.", file: file, line: line)
        XCTAssertFalse(solutionHeading.exists, "A solution showed before Skip.", file: file, line: line)

        try tapSkipUntilAdIsOffered(file: file, line: line)
        XCTAssertFalse(solutionHeading.exists, "The solution showed before the ad was watched.", file: file, line: line)
        tap(app.alerts["Skip this question?"].buttons["Watch ad"], file: file, line: line)
        closeRewardedTestAd(file: file, line: line)

        XCTAssertTrue(solutionHeading.waitForExistence(timeout: 5), "No worked solution after Skip.", file: file, line: line)
        checkSolutionShowing(answerLabel: answerLabel, question: question, readQuestion: readQuestion,
                             questionParts: questionParts, points: start, file: file, line: line)
        attachScreenshot("Worked solution after Skip")

        // It doesn't go by itself, or when the app goes to the background and comes back.
        pause(3)
        XCTAssertTrue(solutionHeading.exists, "The solution went by itself.", file: file, line: line)
        XCUIDevice.shared.press(.home)
        pause(2)
        app.activate()
        XCTAssertTrue(solutionHeading.waitForExistence(timeout: 10), "The solution went after leaving the app.",
                      file: file, line: line)
        checkSolutionShowing(answerLabel: answerLabel, question: question, readQuestion: readQuestion,
                             questionParts: questionParts, points: start, file: file, line: line)

        // Two quick taps bring one new question. A second tap can land on Enter, which then asks for an answer.
        nextQuestionButton.doubleTap()
        XCTAssertTrue(waitQuickly(timeout: 5) { !solutionHeading.exists && !nextQuestionButton.exists },
                      "The solution stayed after Next Question.", file: file, line: line)
        XCTAssertTrue(enterButton.waitForExistence(timeout: 5), "Enter didn't come back.", file: file, line: line)
        for (index, field) in app.textFields.allElementsBoundByIndex.enumerated() {
            XCTAssertTrue(field.isEnabled, "The new question's answer box \(index + 1) can't be used.", file: file, line: line)
            XCTAssertEqual(typedText(in: field), "", "The new question's answer box \(index + 1) isn't empty.",
                           file: file, line: line)
        }
        XCTAssertFalse(hintCard.exists, "The hint came back on the new question.", file: file, line: line)
        XCTAssertFalse(skipButton.exists, "Skip showed on the new question.", file: file, line: line)
        let message = shownMessage()
        XCTAssertTrue(message == nil || message == Feedback.unanswered.rawValue,
                      "Unexpected message after Next Question: \(message ?? "").", file: file, line: line)
        assertPoints(start, file: file, line: line)
        attachScreenshot("New question after Next Question")

        // The new question scores as usual.
        answerNext()
        assertPoints(start + 1, file: file, line: line)
        waitForNextQuestion(file: file, line: line)
    }

    /// While the worked solution shows: its answer is right, the question is still there, the hint has gone, the
    /// answer boxes, the unit wheel and Enter can't be used, and the question, the solution and Next Question are in
    /// view together.
    func checkSolutionShowing(answerLabel: String, question: String, readQuestion: () -> String,
                              questionParts: [(String, XCUIElement)], points: Int,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(solutionAnswer.label, answerLabel, file: file, line: line)
        XCTAssertTrue(app.descendants(matching: .any)["WorkedSolutionStep1"].exists, "No first step.",
                      file: file, line: line)
        XCTAssertEqual(readQuestion(), question, "The question changed under its solution.", file: file, line: line)
        XCTAssertFalse(hintCard.exists, "The hint showed with the solution.", file: file, line: line)
        for (index, field) in app.textFields.allElementsBoundByIndex.enumerated() {
            XCTAssertFalse(field.isEnabled, "Answer box \(index + 1) can be used under the solution.", file: file, line: line)
        }
        for (index, wheel) in app.pickerWheels.allElementsBoundByIndex.enumerated() {
            // XCUITest reads this SwiftUI wheel as enabled under the solution, so try to turn it, as a player would,
            // and record what it reports.
            let before = wheel.value as? String ?? ""
            attachText("Unit wheel \(index + 1) under the solution", "isEnabled \(wheel.isEnabled), value \"\(before)\"")
            wheel.swipeUp()
            pause(1)
            XCTAssertEqual(wheel.value as? String ?? "", before, "Unit wheel \(index + 1) turned under the solution.",
                           file: file, line: line)
        }
        XCTAssertFalse(enterButton.exists, "Enter showed with the solution.", file: file, line: line)
        XCTAssertFalse(skipButton.exists, "Skip showed with the solution.", file: file, line: line)
        XCTAssertTrue(nextQuestionButton.waitForExistence(timeout: 5), "No Next Question button.", file: file, line: line)
        XCTAssertTrue(nextQuestionButton.isHittable, "Next Question can't be tapped.", file: file, line: line)
        XCTAssertTrue(windowFrame.contains(nextQuestionButton.frame), "Next Question isn't in view.", file: file, line: line)
        // It's 44 points tall (`Metrics.minimumTapSize`), which XCUITest can read as 43.99999999999994.
        XCTAssertGreaterThanOrEqual(nextQuestionButton.frame.height, 44 - 0.001, "Next Question is too small to tap.",
                                    file: file, line: line)
        // The question, its solution and Next Question are all in view together, as a player reads them.
        let area = visibleQuestionArea
        let parts = questionParts + [("The solution's heading", solutionHeading), ("The solution's answer", solutionAnswer),
                                     ("Next Question", nextQuestionButton)]
        for (name, element) in parts {
            XCTAssertTrue(area.contains(element.frame), "\(name) at \(element.frame) isn't entirely in view in \(area).",
                          file: file, line: line)
        }
        assertPoints(points, file: file, line: line)
    }

    // MARK: Opening a question

    struct QuestionNotFound: Error, CustomStringConvertible {
        let description: String
    }

    /// When the app was last launched. The interstitial ad can show on a menu 3 minutes after launch, so the loop
    /// below launches it again well before then rather than going through the menus.
    private var lastLaunch: Date?

    /// Opens `activity` until `read` finds a question it wants, and returns what it read.
    func findQuestion<Question>(in activity: String, inYear year: Int, attempts: Int = 60,
                        file: StaticString = #filePath, line: UInt = #line,
                        until read: () -> Question?) throws -> Question {
        for _ in 1...attempts {
            if let lastLaunch, Date().timeIntervalSince(lastLaunch) < 90 {
                goHome(file: file, line: line)
            } else {
                launchApp(file: file, line: line)
                lastLaunch = Date()
            }
            openYear(year, file: file, line: line)
            openActivity(activity, file: file, line: line)
            if let found = read() {
                return found
            }
        }
        let problem = QuestionNotFound(description: "\(attempts) \(activity) questions in a row weren't the one wanted.")
        XCTFail(problem.description, file: file, line: line)
        throw problem
    }

    // MARK: Reading a Geometry question

    struct GeometryQuestion: CustomStringConvertible {
        enum Kind { case perimeter, area, angle }
        let kind: Kind
        /// "Find the perimeter of the shape below".
        let questionText: String
        /// What VoiceOver reads for the shape or angle.
        let picture: String
        let sides: [Int]
        /// "cm".
        let unit: String
        /// "centimetres".
        let unitName: String
        /// "acute", "right" or "obtuse", for an angle.
        let angle: String?

        var perimeter: Int { sides.reduce(0, +) }
        /// Length × width, for a rectangle or square.
        var area: Int? { sides.count == 4 ? sides[0] * sides[1] : nil }
        var answer: Int { kind == .area ? area ?? 0 : perimeter }
        /// On the unit wheel.
        var answerUnit: String { kind == .area ? unit + "²" : unit }

        /// "22 centimetres", "28 square centimetres" or "a right angle".
        var spokenAnswer: String {
            switch kind {
            case .perimeter: return "\(perimeter) \(unitName)"
            case .area: return "\(answer) square \(unitName)"
            case .angle: return angle == "right" ? "a right angle" : angle ?? ""
            }
        }

        /// The line under "Correct!", as VoiceOver reads it.
        var correctLine: String {
            switch kind {
            case .perimeter:
                return sides.map(String.init).joined(separator: " plus ") + " equals \(perimeter) \(unitName)"
            case .area:
                return "\(sides[0]) times \(sides[1]) equals \(answer) square \(unitName)"
            case .angle:
                return angle == "right" ? "This is a right angle." : "This angle is \(angle ?? "")."
            }
        }

        var description: String { "\(questionText) | \(picture)" }
    }

    var geometryPicture: XCUIElement {
        element(labelled: #"^(A (triangle|square|rectangle|pentagon|shape) with sides of .+ and \d+ (milli|centi|kilo)?metres?\.|An angle\. One arm points right, and the other points (up and to the right|straight up|up and to the left)\.)$"#)
    }

    /// The Geometry question on screen, from its words and what VoiceOver reads for its picture.
    func readGeometryQuestion(timeout: TimeInterval = 5) -> GeometryQuestion? {
        let questionTexts = ["Find the perimeter of the shape below", "Calculate the area of the shape below",
                             "Identify this angle type."]
        let shown = app.staticTexts.matching(NSPredicate(format: "label IN %@", questionTexts)).firstMatch
        let picture = geometryPicture
        guard shown.waitForExistence(timeout: timeout), picture.waitForExistence(timeout: timeout),
              let questionText = (try? shown.snapshot())?.label,
              let description = (try? picture.snapshot())?.label else { return nil }
        if questionText == questionTexts[2] {
            guard let match = description.firstMatch(of: #/points (up and to the right|straight up|up and to the left)\.$/#)
            else { return nil }
            let angle = ["up and to the right": "acute", "straight up": "right", "up and to the left": "obtuse"][String(match.1)]
            return GeometryQuestion(kind: .angle, questionText: questionText, picture: description, sides: [], unit: "",
                                    unitName: "", angle: angle)
        }
        let lengths = description.matches(of: #/(\d+) (milli|centi|kilo)?metres?/#)
        guard let first = lengths.first else { return nil }
        let prefix = first.output.2.map { String($0) } ?? ""
        guard let unit = ["milli": "mm", "centi": "cm", "": "m", "kilo": "km"][prefix] else { return nil }
        return GeometryQuestion(kind: questionText == questionTexts[0] ? .perimeter : .area, questionText: questionText,
                                picture: description, sides: lengths.compactMap { Int($0.output.1) }, unit: unit,
                                unitName: prefix + "metres", angle: nil)
    }

    /// Turns the unit wheel to `unit`, with the keyboard put away first, as it covers the wheel.
    func pickUnit(_ unit: String, file: StaticString = #filePath, line: UInt = #line) {
        hideKeyboardByTappingBackground(file: file, line: line)
        let wheel = app.pickerWheels.firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout: 5), "No unit wheel.", file: file, line: line)
        wheel.adjust(toPickerWheelValue: unit)
        XCTAssertTrue(waitQuickly(timeout: 3) {
            let value = wheel.value as? String ?? ""
            return value == unit || value.hasPrefix(unit + ",")
        }, "The unit wheel shows \"\(wheel.value as? String ?? "")\", not \(unit).", file: file, line: line)
    }

    func answerGeometryCorrectly(file: StaticString = #filePath, line: UInt = #line) {
        guard let question = readGeometryQuestion() else {
            return XCTFail("No Geometry question on screen.", file: file, line: line)
        }
        if let angle = question.angle {
            answer(angle.capitalized, expecting: .correct, file: file, line: line)
        } else {
            replaceText(in: answerField, with: "\(question.answer)", file: file, line: line)
            pickUnit(question.answerUnit, file: file, line: line)
            pressEnter(expecting: .correct, file: file, line: line)
        }
    }

    // MARK: Reading a Ratio question

    struct RatioQuestion {
        enum Kind { case simplify, share, missingFirst, missingSecond }
        let kind: Kind
        /// As VoiceOver reads it: "Divide 35 in the ratio 3 to 4".
        let label: String
        /// The numbers it shows, in order.
        let numbers: [Int]

        var sort: String {
            switch kind {
            case .simplify: return "simplify"
            case .share: return "share"
            case .missingFirst, .missingSecond: return "missing number"
            }
        }

        /// Worked out here: two numbers for a ratio, one for a missing number.
        var answer: [Int] {
            switch kind {
            case .simplify:
                let (first, second) = (numbers[0], numbers[1])
                var (larger, smaller) = (max(first, second), min(first, second))
                while smaller != 0 {
                    (larger, smaller) = (smaller, larger % smaller)
                }
                return [first / larger, second / larger]
            case .share:
                let (total, first, second) = (numbers[0], numbers[1], numbers[2])
                let part = total / (first + second)
                return [first * part, second * part]
            case .missingFirst:
                let (shown, first, second) = (numbers[0], numbers[1], numbers[2])
                return [first * (shown / second)]
            case .missingSecond:
                let (shown, first, second) = (numbers[0], numbers[1], numbers[2])
                return [second * (shown / first)]
            }
        }

        /// The line under "Correct!", as VoiceOver reads it.
        var correctLine: String {
            switch kind {
            case .simplify:
                return "\(numbers[0]) to \(numbers[1]) equals \(answer[0]) to \(answer[1])"
            case .share:
                return "\(numbers[0]) shared in the ratio \(numbers[1]) to \(numbers[2]) is \(answer[0]) to \(answer[1])"
            case .missingFirst:
                return "\(answer[0]) to \(numbers[0]) equals \(numbers[1]) to \(numbers[2])"
            case .missingSecond:
                return "\(numbers[0]) to \(answer[0]) equals \(numbers[1]) to \(numbers[2])"
            }
        }

        /// A wrong answer the hint names, and that hint as VoiceOver reads it: the question's own ratio typed back,
        /// the ratio given as the shares, and a missing number found by adding. Where adding happens to give the
        /// answer (the ratio's two numbers are the same), 99 and the usual hint.
        var namedMistake: (answer: [Int], hint: String) {
            switch kind {
            case .simplify:
                return ([numbers[0], numbers[1]], "Hint: That is the ratio from the question. "
                        + "Find the biggest number that divides into both \(numbers[0]) and \(numbers[1]).")
            case .share:
                return ([numbers[1], numbers[2]], "Hint: That is the ratio. Work out how much one part is worth.")
            case .missingFirst:
                let (shown, first, second) = (numbers[0], numbers[1], numbers[2])
                let question = "What do you multiply \(second) by to get \(shown)?"
                let added = first + (shown - second)
                return added == answer[0]
                    ? ([99], "Hint: \(question) Do the same to \(first).")
                    : ([added], "Hint: Ratios grow by multiplying, not adding. \(question)")
            case .missingSecond:
                let (shown, first, second) = (numbers[0], numbers[1], numbers[2])
                let question = "What do you multiply \(first) by to get \(shown)?"
                let added = second + (shown - first)
                return added == answer[0]
                    ? ([99], "Hint: \(question) Do the same to \(second).")
                    : ([added], "Hint: Ratios grow by multiplying, not adding. \(question)")
            }
        }
    }

    /// The Ratio question on screen, from what VoiceOver reads for it.
    func readRatioQuestion(file: StaticString = #filePath, line: UInt = #line) -> RatioQuestion? {
        let predicate = NSPredicate(format: "label BEGINSWITH 'Simplify the ratio ' OR label BEGINSWITH 'Divide ' "
                                    + "OR label BEGINSWITH 'Find the missing number.'")
        let element = app.staticTexts.matching(predicate).firstMatch
        guard element.waitForExistence(timeout: 5), let label = (try? element.snapshot())?.label else {
            XCTFail("No Ratio question on screen.", file: file, line: line)
            return nil
        }
        if let match = label.wholeMatch(of: #/Simplify the ratio (\d+) to (\d+)/#) {
            return RatioQuestion(kind: .simplify, label: label, numbers: [Int(match.1)!, Int(match.2)!])
        }
        if let match = label.wholeMatch(of: #/Divide (\d+) in the ratio (\d+) to (\d+)/#) {
            return RatioQuestion(kind: .share, label: label, numbers: [Int(match.1)!, Int(match.2)!, Int(match.3)!])
        }
        if let match = label.wholeMatch(of: #/Find the missing number\. missing number to (\d+) equals (\d+) to (\d+)/#) {
            return RatioQuestion(kind: .missingFirst, label: label, numbers: [Int(match.1)!, Int(match.2)!, Int(match.3)!])
        }
        if let match = label.wholeMatch(of: #/Find the missing number\. (\d+) to missing number equals (\d+) to (\d+)/#) {
            return RatioQuestion(kind: .missingSecond, label: label, numbers: [Int(match.1)!, Int(match.2)!, Int(match.3)!])
        }
        XCTFail("Couldn't read the Ratio question \"\(label)\".", file: file, line: line)
        return nil
    }

    /// Types two numbers into the ratio's two boxes, or one into the missing-number box.
    func fillRatio(with numbers: [Int], file: StaticString = #filePath, line: UInt = #line) {
        guard numbers.count == 2 else {
            return replaceText(in: answerField, with: "\(numbers[0])", file: file, line: line)
        }
        for (name, number) in zip(["First part of the ratio", "Second part of the ratio"], numbers) {
            let box = app.textFields.matching(NSPredicate(format: "label == %@", name)).firstMatch
            replaceText(in: box, with: "\(number)", file: file, line: line)
        }
    }

    func answerRatioCorrectly(file: StaticString = #filePath, line: UInt = #line) {
        guard let question = readRatioQuestion(file: file, line: line) else { return }
        fillRatio(with: question.answer, file: file, line: line)
        pressEnter(expecting: .correct, file: file, line: line)
    }

    func element(labelled pattern: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label MATCHES %@", pattern)).firstMatch
    }
}

/// Stage 9C: with a hint showing, the question meets Stage 9B's keyboard requirement as it does without one (see
/// `Stage9BKeyboardUITests`). The hint card sits under Enter and Skip, where the keyboard may cover it, so that it
/// can't push the question out of view when the keyboard comes up (an SE run found that it did when it sat between the
/// answer box and Enter). After a wrong answer the player types again with the hint still showing.
class Stage9CHintKeyboardUITests: Stage9BKeyboardChecks {
    override var questionsPerActivity: Int { 1 }

    @MainActor func testMultiplicationHintKeepsTheQuestionInView() throws { try checkWithHint(on: "Multiplication", inYear: 2) }
    @MainActor func testDivisionHintKeepsTheQuestionInView() throws { try checkWithHint(on: "Division", inYear: 2) }

    /// A shape rather than an angle: the shape and the unit wheel make it the tallest Geometry question. 999 is
    /// never a perimeter or an area.
    @MainActor func testGeometryHintKeepsTheQuestionInView() throws {
        try checkWithHint(on: "Geometry", inYear: 4, wrongAnswer: "999",
                          wanted: NSPredicate(format: "label BEGINSWITH 'Find the perimeter' OR label BEGINSWITH 'Calculate the area'"))
    }

    /// A share question, with its shares the wrong way round: the longest Ratio hint since feedback batch FB-D, which
    /// asks for both boxes rather than marking one left empty (whose hint was longer).
    @MainActor func testRatiosHintKeepsTheQuestionInView() throws {
        try checkWithHint(on: "Ratios", inYear: 6, wanted: NSPredicate(format: "label BEGINSWITH 'Divide '"),
                          fillWrongAnswer: { [unowned self] in self.fillShareTheWrongWayRound() })
    }

    /// Types the shares of "Divide 35 in the ratio 3 to 4" the wrong way round, 20 and 15, which the hint names. Where
    /// the ratio's two numbers are the same, that would be right, so 99 and 99, which no share is.
    @MainActor
    func fillShareTheWrongWayRound() {
        let question = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Divide '")).firstMatch
        guard let label = (try? question.snapshot())?.label,
              let match = label.wholeMatch(of: #/Divide (\d+) in the ratio (\d+) to (\d+)/#) else {
            return XCTFail("No share question on screen.")
        }
        let (total, first, second) = (Int(match.1)!, Int(match.2)!, Int(match.3)!)
        let part = total / (first + second)
        let wrong = first == second ? [99, 99] : [second * part, first * part]
        attachText("Ratios: wrong answer", "\(wrong[0]) and \(wrong[1]) for \"\(label)\"")
        for (name, number) in zip(["First part of the ratio", "Second part of the ratio"], wrong) {
            let box = app.textFields.matching(NSPredicate(format: "label == %@", name)).firstMatch
            replaceText(in: box, with: "\(number)")
        }
    }

    /// Gives a wrong answer, then checks the question with the hint showing, with the keyboard down, up and put away.
    /// With `wanted`, the activity is opened until a question's words match it. `fillWrongAnswer`, where given, fills
    /// in the wrong answer in place of typing `wrongAnswer` in the first box.
    @MainActor
    func checkWithHint(on activity: String, inYear year: Int, wrongAnswer: String = "99",
                       wanted: NSPredicate? = nil, fillWrongAnswer: (() -> Void)? = nil) throws {
        continueAfterFailure = true
        var launchedAt: Date?
        for attempt in 1...60 {
            // Launched again before the interstitial ad can show on a menu, 3 minutes after launch.
            if let launchedAt, Date().timeIntervalSince(launchedAt) < 90 {
                goHome()
            } else {
                launchApp()
                launchedAt = Date()
            }
            openYear(year)
            openActivity(activity)
            guard let wanted, !app.staticTexts.matching(wanted).firstMatch.waitForExistence(timeout: 2) else {
                break
            }
            if attempt == 60 {
                return XCTFail("60 \(activity) questions in a row didn't match \(wanted).")
            }
        }
        if usesAccessibilityText && UIDevice.current.userInterfaceIdiom != .pad {
            // At these sizes the answer box can be below the screen's edge until the player scrolls to it.
            scrollAnswerFieldIntoView()
        }
        if let fillWrongAnswer {
            fillWrongAnswer()
            pressEnter(expecting: .incorrect)
        } else {
            answer(wrongAnswer, expecting: .incorrect)
        }
        let hintCard = app.descendants(matching: .any)["HintCard"]
        XCTAssertTrue(hintCard.waitForExistence(timeout: 3), "No hint after a wrong answer.")
        XCTAssertTrue(waitQuickly(timeout: 5) { visibleFeedback() == nil }, "\"Incorrect. Try Again!\" didn't go.")
        attachText("\(activity) hint", hintCard.label)
        // The wrong answer stays in the box for the player to change. The check below types into an empty box, as
        // a player who starts again does, so clear it and put the keyboard away first.
        focus(answerField)
        answerField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: typedText(in: answerField).count))
        XCTAssertEqual(typedText(in: answerField), "", "Couldn't clear the wrong answer.")
        hideKeyboardByTappingBackground()
        XCTAssertTrue(hintCard.exists, "The hint went when the wrong answer was cleared.")
        if usesAccessibilityText && UIDevice.current.userInterfaceIdiom != .pad {
            // At these sizes the player scrolled down to the answer box, and the message after Enter scrolls the
            // screen down to Enter (Stage 6E) and the hint under it, so the top of the question can be above the top
            // edge with the hint showing. The player scrolls back up to read it, as the approved design allows while a card shows;
            // the check below starts from there, as it does on a new question.
            scrollQuestionToTop(activity)
        }
        guard checkOneQuestion(on: "\(activity) with a hint", number: 1) else {
            throw XCTSkip(LayoutUITests.noKeyboard(on: activity))
        }
        XCTAssertTrue(hintCard.exists, "The hint went while the player typed.")
        checkHintCanBeScrolledTo(hintCard, on: activity)
    }

    /// With the keyboard put away, scrolls up as a player would until the hint under Enter and Skip is entirely in
    /// view, and checks what VoiceOver reads for it. Where the question and the hint don't both fit, the screen shows
    /// the question first (an approved deviation), provided the hint can still be reached by scrolling.
    @MainActor
    func checkHintCanBeScrolledTo(_ hintCard: XCUIElement, on activity: String) {
        hideKeyboardByTappingBackground()
        var drags = 0
        for _ in 1...6 {
            let area = visibleArea(of: questionParts())
            let hint = hintCard.frame
            guard !area.isEmpty, !hint.isEmpty, hint.maxY > area.maxY + 0.5 else {
                break
            }
            let startY = min(area.maxY, windowFrame.maxY - 50) - 10
            let shift = min(hint.maxY - area.maxY + 20, startY - area.minY - 10)
            guard shift > 4 else {
                break
            }
            dragQuestionArea(fromY: startY, toY: startY - shift)
            _ = waitForFrameToSettle(of: hintCard, timeout: 2, steadyFor: 0.3)
            drags += 1
        }
        attachText("\(activity): drags to bring the hint into view", "\(drags)")
        attachScreenshot("\(activity): the hint scrolled into view")
        assertFullyVisible(hintCard, "\(activity): the hint after scrolling to it",
                           within: visibleArea(of: questionParts()), tappable: false)
        XCTAssertTrue(hintCard.label.hasPrefix("Hint: "), "VoiceOver reads the hint as \"\(hintCard.label)\".")
    }

    /// With the keyboard down, drags the question down until its first line is in view, and records how far above
    /// the top edge it was.
    @MainActor
    func scrollQuestionToTop(_ activity: String) {
        var hidden: [String] = []
        for _ in 1...4 {
            let parts = questionParts()
            let area = visibleArea(of: parts)
            guard !area.isEmpty, let top = parts.questionWords.map(\.frame.minY).min(), top < area.minY - 0.5 else {
                break
            }
            hidden.append(String(format: "%.0f pt", area.minY - top))
            let startY = area.minY + 10
            dragQuestionArea(fromY: startY, toY: startY + min(area.minY - top + 20, area.height - 60))
            _ = waitForFrameToSettle(of: answerField, timeout: 2, steadyFor: 0.3)
        }
        attachText("\(activity): question above the top edge with the hint showing",
                   hidden.isEmpty ? "none" : hidden.joined(separator: ", then "))
    }
}

/// The same at the largest accessibility text size, where on an iPhone the question may scroll while the keyboard is
/// up, provided every part of it can be reached.
final class Stage9CHintKeyboardLargeTextUITests: Stage9CHintKeyboardUITests {
    override func setUpWithError() throws {
        try super.setUpWithError()
        extraLaunchArguments = BlankAnswerAndLargeTextUITests.largestText
    }
}
