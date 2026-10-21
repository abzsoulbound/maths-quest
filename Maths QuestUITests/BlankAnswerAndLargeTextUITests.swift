//
//  BlankAnswerAndLargeTextUITests.swift
//  Maths QuestUITests
//

import UIKit
import XCTest

/// Stage 6E's fixes as a player meets them. Run on a small iPhone, a large iPhone and an iPad.
///
/// - Enter with nothing typed asks for an answer in every activity. It scores nothing, leaves the question as it was
///   and isn't a wrong answer, so it never brings up Skip.
/// - The clock to set starts at 12:00 on every visit. It used to keep the time from the last visit.
/// - At the largest text size the bar chart, the cube or cuboid and the probability question start below the header,
///   and the answer boxes, Enter, the messages and Skip all come into view and can be tapped.
///
/// Questions are random, so a test opens the activity again until a suitable one comes up.
final class BlankAnswerAndLargeTextUITests: MathsQuestUITestCase {
    static let largestText = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
    static let clockAt12 = "The short hour hand points at the 12. The long minute hand points at the 12."
    static let clockAt1205 = "The short hour hand is between the 12 and the 1. The long minute hand points at the 1."

    /// When the app was last launched. An interstitial can come up at a menu 180 seconds after launch.
    private var launchedAt = Date()

    private struct QuestionNeverCameUp: Error, CustomStringConvertible {
        let description: String
    }

    // MARK: Enter with nothing typed

    @MainActor
    func testBlankEnterInYear1() { checkBlankEnter(inYear: 1) }

    @MainActor
    func testBlankEnterInYear2() { checkBlankEnter(inYear: 2) }

    @MainActor
    func testBlankEnterInYear3() { checkBlankEnter(inYear: 3) }

    @MainActor
    func testBlankEnterInYear4() { checkBlankEnter(inYear: 4) }

    @MainActor
    func testBlankEnterInYear5() { checkBlankEnter(inYear: 5) }

    @MainActor
    func testBlankEnterInYear6() { checkBlankEnter(inYear: 6) }

    /// Blank Enters in among wrong answers: Skip comes up with the second wrong answer and not before.
    @MainActor
    func testBlankAnswersDoNotCountTowardsSkip() throws {
        launch()
        openYear(1)
        openActivity("Addition")
        let start = currentPoints()

        pressEnter(expecting: .unanswered)
        pressEnter(expecting: .unanswered)
        XCTAssertFalse(skipButton.exists, "Skip came up after two blank answers.")

        answer("99", expecting: .incorrect)
        XCTAssertFalse(skipButton.exists, "Skip came up after one wrong answer and two blank ones.")

        clear(answerField)
        pressEnter(expecting: .unanswered)
        XCTAssertFalse(skipButton.exists, "Skip came up after one wrong answer and three blank ones.")

        answer("99", expecting: .incorrect)
        XCTAssertTrue(skipButton.waitForExistence(timeout: 5), "Skip didn't come up after the second wrong answer.")
        assertPoints(start)
    }

    // MARK: The clock to set

    /// The clock to set starts at 12:00, and still does on the next visit after its hands were moved.
    @MainActor
    func testClockToSetStartsAt12OnEveryVisit() throws {
        launch()
        let clock = element(labelled: "^Clock to set$")
        try openUntil(clock, showing: "the clock to set", in: "Time", inYear: 3)
        let start = currentPoints()
        XCTAssertEqual(clock.value as? String, Self.clockAt12, "The clock to set didn't start at 12:00.")
        XCTAssertEqual(tapEnterAndReadMessage(), Feedback.unanswered.rawValue,
                       "Enter with the clock still at 12:00 didn't ask for an answer.")
        XCTAssertFalse(skipButton.exists, "Skip came up without a wrong answer.")

        // The message moves the clock while it shows.
        XCTAssertTrue(waitQuickly(timeout: 3) { !feedbackMessage.exists }, "The message didn't go.")
        scrollIntoView(clock)
        dragMinuteHandFrom12To1(on: clock)
        XCTAssertTrue(waitQuickly(timeout: 3) { clock.value as? String == Self.clockAt1205 },
                      "Dragging the minute hand from the 12 to the 1 left the clock at \"\(clock.value ?? "nothing")\".")
        attachScreenshot("Clock to set at 12:05")

        goHome()
        try openUntil(clock, showing: "the clock to set", in: "Time", inYear: 3, relaunching: false)
        XCTAssertEqual(clock.value as? String, Self.clockAt12, "The clock to set kept the time from the last visit.")
        attachScreenshot("Clock to set on the next visit")
        assertPoints(start)
    }

    // MARK: The largest text size

    /// The question, the bars, the answer box and Enter don't overlap, the whole chart can be seen at once, and the
    /// messages and Skip come up in view.
    @MainActor
    func testBarChartFitsAtTheLargestTextSize() throws {
        continueAfterFailure = true
        extraLaunchArguments = Self.largestText
        launch()
        let question = text("Which category has the highest value?")
        try openUntil(question, showing: "a bar chart", in: "Statistics", inYear: 5)
        _ = waitForFrameToSettle(of: anyEnterButton, timeout: 3, steadyFor: 0.3)
        let start = currentPoints()
        assertHeaderClearOfTheQuestion("Bar chart")

        let bars = elements(labelled: "^Category [A-D]$").allElementsBoundByIndex
        XCTAssertEqual(bars.count, 4, "The bar chart doesn't have four bars.")
        let window = windowFrame
        for bar in bars {
            XCTAssertTrue(bar.frame.minX >= window.minX - 0.5 && bar.frame.maxX <= window.maxX + 0.5,
                          "\(bar.label) at \(bar.frame) runs off the side of the screen \(window).")
        }
        let frames: [(name: String, frame: CGRect)] = bars.map { (name: $0.label, frame: $0.frame) } + [
            ("The question", question.frame), ("The answer box", answerField.frame), ("Enter", anyEnterButton.frame),
        ]
        attachText("Bar chart frames", describe(frames))
        assertNoOverlap(frames)
        attachScreenshot("Bar chart at the top")

        let chart = element(labelled: "^Bar chart$")
        scrollIntoView(chart)
        assertFullyVisible(chart, "The bar chart", within: visibleQuestionArea, tappable: false)
        attachScreenshot("Bar chart in view")

        scrollIntoView(anyEnterButton)
        assertAnswerAndEnterInView("Bar chart")
        attachScreenshot("Bar chart, answer box and Enter")

        replaceText(in: answerField, with: "Z")
        checkWithTheKeyboardUp("Bar chart")

        XCTAssertEqual(tapEnterAndCheckMessageInView("Bar chart, first wrong answer"), Feedback.incorrect.rawValue)
        XCTAssertFalse(skipButton.exists, "Skip came up after one wrong answer.")
        XCTAssertEqual(tapEnterAndCheckMessageInView("Bar chart, second wrong answer"), Feedback.incorrect.rawValue)
        assertSkipAndEnterInView("Bar chart")
        assertPoints(start)
    }

    /// The whole cube or cuboid shows below the header, clear of the question, the answer box and Enter, and the
    /// messages and Skip come up in view.
    @MainActor
    func testCubeAndCuboidFitAtTheLargestTextSize() throws {
        continueAfterFailure = true
        extraLaunchArguments = Self.largestText
        launch()
        let picture = element(
            labelled: #"^A (cube|cuboid)\. Width \d+ centimetres, length \d+ centimetres, height \d+ centimetres\.$"#)
        try openUntil(picture, showing: "a cube or cuboid", in: "Volume", inYear: 5)
        _ = waitForFrameToSettle(of: anyEnterButton, timeout: 3, steadyFor: 0.3)
        let start = currentPoints()
        assertHeaderClearOfTheQuestion("Volume")

        let question = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'What is the volume of this'"))
            .firstMatch
        XCTAssertTrue(question.waitForExistence(timeout: 5), "No Volume question on screen.")
        assertFullyVisible(picture, "The picture", within: questionAreaFrame.intersection(windowFrame), tappable: false)
        let frames: [(name: String, frame: CGRect)] = [
            ("The picture", picture.frame), ("The question", question.frame),
            ("The answer box", answerField.frame), ("Enter", anyEnterButton.frame),
        ]
        attachText("Volume frames", describe(frames))
        assertNoOverlap(frames)
        attachScreenshot("Volume at the top")

        scrollIntoView(anyEnterButton)
        assertAnswerAndEnterInView("Volume")
        attachScreenshot("Volume, answer box and Enter")

        // Every edge is at least 2 centimetres, so 1 is always wrong.
        replaceText(in: answerField, with: "1")
        checkWithTheKeyboardUp("Volume")

        XCTAssertEqual(tapEnterAndCheckMessageInView("Volume, first wrong answer"), Feedback.incorrect.rawValue)
        XCTAssertFalse(skipButton.exists, "Skip came up after one wrong answer.")
        XCTAssertEqual(tapEnterAndCheckMessageInView("Volume, second wrong answer"), Feedback.incorrect.rawValue)
        assertSkipAndEnterInView("Volume")
        assertPoints(start)
    }

    /// The probability question starts below the header, the fraction boxes and Enter come into view together, and
    /// the messages and Skip come up in view.
    @MainActor
    func testProbabilityFitsAtTheLargestTextSize() throws {
        continueAfterFailure = true
        extraLaunchArguments = Self.largestText
        launch()
        openYear(6)
        openActivity("Probability")
        let question = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'What is the probability'"))
            .firstMatch
        XCTAssertTrue(question.waitForExistence(timeout: 10), "No Probability question on screen.")
        _ = waitForFrameToSettle(of: anyEnterButton, timeout: 3, steadyFor: 0.3)
        let start = currentPoints()
        assertHeaderClearOfTheQuestion("Probability")
        XCTAssertGreaterThanOrEqual(question.frame.minY, questionAreaFrame.minY - 0.5,
                                    "The question at \(question.frame) starts under the header.")
        attachScreenshot("Probability at the top")

        scrollIntoView(anyEnterButton)
        assertAnswerAndEnterInView("Probability")
        attachScreenshot("Probability, fraction boxes and Enter")
        XCTAssertEqual(tapEnterAndCheckMessageInView("Probability, nothing typed"), Feedback.unanswered.rawValue)
        XCTAssertFalse(skipButton.exists, "Skip came up without a wrong answer.")

        // No probability here has more than 20 outcomes, so 99/100 is always wrong.
        replaceText(in: box("Numerator"), with: "99")
        if waitQuickly(timeout: 3, until: { keyboardIsOnScreen }) {
            waitForKeyboardToSettle()
            assertFullyVisible(box("Denominator"), "Probability, keyboard up: the denominator box",
                               within: visibleQuestionArea)
        }
        replaceText(in: box("Denominator"), with: "100")
        checkWithTheKeyboardUp("Probability")

        XCTAssertEqual(tapEnterAndCheckMessageInView("Probability, first wrong answer"), Feedback.incorrect.rawValue)
        XCTAssertFalse(skipButton.exists, "Skip came up after one wrong answer.")
        XCTAssertEqual(tapEnterAndCheckMessageInView("Probability, second wrong answer"), Feedback.incorrect.rawValue)
        assertSkipAndEnterInView("Probability")

        scrollIntoView(question)
        XCTAssertGreaterThanOrEqual(question.frame.minY, questionAreaFrame.minY - 0.5,
                                    "The start of the question at \(question.frame) can't be brought out from under "
                                    + "the header.")
        attachScreenshot("Probability, back at the question")
        assertPoints(start)
    }

    // MARK: - Helpers

    @MainActor
    private func launch() {
        launchedAt = Date()
        launchApp()
    }

    /// In each of the year's activities, Enter with nothing typed asks for an answer, twice over, and leaves the
    /// points, the question and the answer boxes as they were, with no Skip.
    @MainActor
    private func checkBlankEnter(inYear year: Int) {
        continueAfterFailure = true
        launch()
        for activity in Self.activities[year] ?? [] {
            openYear(year)
            openActivity(activity)
            let start = currentPoints()
            let question = questionTexts()
            for attempt in ["first", "second"] {
                XCTAssertEqual(tapEnterAndReadMessage(), Feedback.unanswered.rawValue,
                               "\(activity): the \(attempt) Enter with nothing typed didn't ask for an answer.")
            }
            XCTAssertTrue(waitQuickly(timeout: 3) { !feedbackMessage.exists }, "\(activity): the message didn't go.")
            assertPoints(start)
            XCTAssertFalse(skipButton.exists, "\(activity): Skip came up without a wrong answer.")
            XCTAssertEqual(questionTexts(), question, "\(activity): the question changed.")
            for (index, field) in app.textFields.allElementsBoundByIndex.enumerated() {
                XCTAssertEqual(typedText(in: field), "", "\(activity): answer box \(index + 1) isn't empty.")
            }
            goHome()
        }
    }

    /// Opens `activity` until its question shows `element`. With `relaunching`, the app is launched afresh once 30
    /// seconds have gone, so the rest of the test has time before the first interstitial, 180 seconds after launch.
    /// Without it, the test is skipped as unverified if the question hasn't come up after 150 seconds.
    @MainActor
    private func openUntil(_ element: XCUIElement, showing what: String, in activity: String, inYear year: Int,
                           relaunching: Bool = true, file: StaticString = #filePath, line: UInt = #line) throws {
        let attempts = 40
        for attempt in 1...attempts {
            if attempt > 1 {
                let elapsed = Date().timeIntervalSince(launchedAt)
                if relaunching && elapsed > 30 {
                    launch()
                } else if elapsed > 150 {
                    throw XCTSkip("Unverified this run: \(attempt - 1) \(activity) questions in a row didn't show "
                                  + "\(what), and there's no time left before the first interstitial.")
                } else {
                    goHome(file: file, line: line)
                }
            }
            openYear(year, file: file, line: line)
            openActivity(activity, file: file, line: line)
            if element.waitForExistence(timeout: 1) {
                return
            }
        }
        throw QuestionNeverCameUp(description: "\(attempts) \(activity) questions in a row didn't show \(what).")
    }

    /// The message after Enter. It's drawn many times over as an outline, so this is the first copy.
    @MainActor
    private var feedbackMessage: XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label IN %@", Self.feedbackMessages)).firstMatch
    }

    /// Taps Enter once the last message has gone, and returns the message it brings up.
    @MainActor
    private func tapEnterAndReadMessage(file: StaticString = #filePath, line: UInt = #line) -> String? {
        XCTAssertTrue(waitQuickly(timeout: 5) { !feedbackMessage.exists && anyEnterButton.isEnabled },
                      "Enter didn't become available again.", file: file, line: line)
        tap(anyEnterButton, file: file, line: line)
        var shown: String?
        _ = waitQuickly(timeout: 3) {
            // A snapshot rather than `label`, because the message can go between the two calls.
            shown = (try? feedbackMessage.snapshot())?.label
            return shown != nil
        }
        return shown
    }

    /// Taps Enter, checks the message it brings up, Enter and, once it's there, Skip stay entirely in view, below the
    /// header and above the keyboard or the bottom of the screen, for as long as the message is up, and returns the
    /// message. The message goes in just above Enter, so on a question that only just fits it pushes Enter down as it
    /// comes in: checking the message alone, or only the moment it comes up, isn't enough.
    @MainActor
    private func tapEnterAndCheckMessageInView(_ when: String, file: StaticString = #filePath,
                                               line: UInt = #line) -> String? {
        XCTAssertTrue(waitQuickly(timeout: 5) { !feedbackMessage.exists && anyEnterButton.isEnabled },
                      "\(when): Enter didn't become available again.", file: file, line: line)
        tap(anyEnterButton, file: file, line: line)
        let tapped = Date()
        var shown: String?
        var looks = 0
        var outOfView: [String] = []
        var screenshotTaken = false
        let gone = waitQuickly(timeout: 4) {
            // `exists` first, as a snapshot of something that isn't there takes about 2 seconds to fail, then
            // snapshots rather than `frame`, because the message can go between two calls.
            guard feedbackMessage.exists else {
                return shown != nil
            }
            guard let message = try? feedbackMessage.snapshot(), let enter = try? anyEnterButton.snapshot() else {
                return false
            }
            shown = message.label
            looks += 1
            let seconds = Date().timeIntervalSince(tapped)
            var frames = [("the message", message.frame), ("Enter", enter.frame)]
            if skipButton.exists, let skip = try? skipButton.snapshot() {
                frames.append(("Skip", skip.frame))
            }
            let inView = visibleQuestionArea.insetBy(dx: -0.5, dy: -0.5)
            for (name, frame) in frames where !inView.contains(frame) {
                outOfView.append("\(String(format: "%.2f", seconds))s: \(name) at \(frame)")
            }
            // Once the question has had time to make room for the message.
            if !screenshotTaken && seconds > 0.6 {
                attachScreenshot("\(when): \(message.label)")
                screenshotTaken = true
            }
            return false
        }
        guard let shown else {
            XCTFail("\(when): no message came up after Enter.", file: file, line: line)
            return nil
        }
        XCTAssertTrue(gone, "\(when): the message didn't go.", file: file, line: line)
        XCTAssertTrue(outOfView.isEmpty, "\(when): while the message was up, not everything was entirely in view "
                      + "within \(visibleQuestionArea), in \(outOfView.count) of \(looks) looks: "
                      + outOfView.prefix(4).joined(separator: "; "), file: file, line: line)
        return shown
    }

    /// After the second wrong answer, Skip is beside Enter, and both are entirely in view and can be tapped.
    @MainActor
    private func assertSkipAndEnterInView(_ when: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(skipButton.waitForExistence(timeout: 5), "\(when): Skip didn't come up after two wrong answers.",
                      file: file, line: line)
        _ = waitQuickly(timeout: 3) { !feedbackMessage.exists }
        _ = waitForFrameToSettle(of: skipButton, timeout: 3, steadyFor: 0.3)
        let area = visibleQuestionArea
        assertFullyVisible(skipButton, "\(when): Skip", within: area, file: file, line: line)
        assertFullyVisible(anyEnterButton, "\(when): Enter", within: area, file: file, line: line)
        assertNoOverlap([("Enter", anyEnterButton.frame), ("Skip", skipButton.frame)], file: file, line: line)
        attachScreenshot("\(when): Skip beside Enter")
    }

    /// With the keyboard up after typing, every answer box and Enter are in view above it. The iPad simulator doesn't
    /// bring up the number and decimal pads while the Mac's keyboard is connected, so there it's noted as unverified.
    @MainActor
    private func checkWithTheKeyboardUp(_ when: String, file: StaticString = #filePath, line: UInt = #line) {
        guard waitQuickly(timeout: 3, until: { keyboardIsOnScreen }) else {
            attachText("\(when): keyboard up unverified",
                       "The on-screen keyboard didn't come up, so the layout with it up wasn't checked on this device.")
            return
        }
        waitForKeyboardToSettle(file: file, line: line)
        assertAnswerAndEnterInView("\(when), keyboard up", file: file, line: line)
        attachScreenshot("\(when), keyboard up")
    }

    /// Drags the question area until `element` is in view, or its top is when it's too tall to fit. The drag is down
    /// the very left of the screen, beside the drawing pad, so it scrolls rather than draws, and it holds at the end
    /// so the question doesn't run on. Only with the keyboard down, as a drag can put the keyboard away.
    @MainActor
    private func scrollIntoView(_ element: XCUIElement) {
        guard element.waitForExistence(timeout: 5) else {
            return
        }
        for _ in 0..<4 {
            let area = visibleQuestionArea
            let frame = element.frame
            guard !area.isNull, area.height > 100, !area.insetBy(dx: -0.5, dy: -0.5).contains(frame) else {
                return
            }
            // The question area runs down under the home indicator, which takes a drag that starts there, so the
            // drag stays 50 points clear of the bottom of the screen.
            var dragArea = area
            dragArea.size.height = max(0, min(area.maxY, windowFrame.maxY - 50) - area.minY)
            // Centre it, or line its top up with the top of the area if it's too tall.
            let wantedMinY = frame.height <= area.height ? area.midY - frame.height / 2 : area.minY + 4
            let room = dragArea.height - 60
            let shift = min(max(wantedMinY - frame.minY, -room), room)
            guard abs(shift) >= 2 else {
                return
            }
            let x = windowFrame.minX + 2
            let startY = shift < 0 ? dragArea.maxY - 30 : dragArea.minY + 30
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: x, dy: startY))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: x, dy: startY + shift)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
            _ = waitForFrameToSettle(of: element, timeout: 2, steadyFor: 0.3)
        }
    }

    /// Drags the clock's minute hand from the 12 round to the 1, and holds it there before letting go.
    @MainActor
    private func dragMinuteHandFrom12To1(on clock: XCUIElement) {
        // 0.35 of the clock's width is 0.7 of its radius, well clear of the dead zone in the middle.
        let reach = 0.35
        let angle = Double.pi / 6
        let twelve = clock.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5 - reach))
        let one = clock.coordinate(withNormalizedOffset: CGVector(dx: 0.5 + reach * sin(angle),
                                                                  dy: 0.5 - reach * cos(angle)))
        twelve.press(forDuration: 0.2, thenDragTo: one, withVelocity: .slow, thenHoldForDuration: 0.2)
    }

    /// Deletes whatever is typed in `field`.
    @MainActor
    private func clear(_ field: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        focus(field, file: file, line: line)
        let count = typedText(in: field).count
        if count > 0 {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count))
        }
        XCTAssertEqual(typedText(in: field), "", "Couldn't clear the answer box.", file: file, line: line)
    }

    /// Every piece of text on the question screen apart from the points and the messages, in a fixed order.
    @MainActor
    private func questionTexts() -> [String] {
        staticTextSnapshots().map(\.label)
            .filter { !$0.isEmpty && !$0.hasPrefix("Points: ") && !Self.feedbackMessages.contains($0) }
            .sorted()
    }

    @MainActor
    private func elements(labelled pattern: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "label MATCHES %@", pattern))
    }

    @MainActor
    private func element(labelled pattern: String) -> XCUIElement {
        elements(labelled: pattern).firstMatch
    }

    /// A fraction box, found by its spoken name.
    @MainActor
    private func box(_ name: String) -> XCUIElement {
        app.textFields.matching(NSPredicate(format: "placeholderValue == %@ OR label == %@", name, name)).firstMatch
    }

    private func describe(_ frames: [(name: String, frame: CGRect)]) -> String {
        frames.map { "\($0.name): \($0.frame)" }.joined(separator: "\n")
    }
}
