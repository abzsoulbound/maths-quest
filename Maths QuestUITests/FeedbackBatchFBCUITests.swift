//
//  FeedbackBatchFBCUITests.swift
//  Maths QuestUITests
//
//  User feedback, batch FB-C: Enter seemed not to respond straight after a message. Enter can't be tapped while a
//  message shows, and the message stayed for its full second even once the answer had been put right, so a child who
//  corrected an answer quickly found Enter dead. Now changing the answer hides the message about the old one, and only
//  a message's own timer hides it, so a newer message isn't cut short by an older one's timer.
//
//  What these tests can and can't show: the message shows for one second in Addition and Time, and XCUITest can't
//  type a change sooner than about one and a half seconds after a tap on Enter (it waits for the app to settle after
//  each tap, and the keyboard has to come back). So by the time the change is typed, the message's own timer has
//  already hidden it, and a UI test can't tell the change and the timer apart. That sub-second behaviour is tested by
//  the unit tests (FeedbackBatchFBCTests: the message clock, each of the 18 activities' wiring, and the Stage 4A
//  timeline). These tests check what a child sees at the speed XCUITest can go: a corrected answer can be entered,
//  it scores once, Skip comes after the second wrong answer and not before, and taps during the move to the next
//  question don't score again. Each test attaches its timings, saying whether the change came before the timer.
//

import XCTest

@MainActor
final class FeedbackBatchFBCUITests: FeedbackBatchUITestCase {

    /// How long a message shows for in Addition and Time, in seconds.
    private static let messageTime: TimeInterval = 1

    // MARK: - One box: Addition

    /// "Incorrect. Try Again!", then the answer put right as fast as XCUITest can: the message goes, Enter works for
    /// the corrected answer, which scores once, no other message replaces "Correct!", and the next question comes.
    func testACorrectedAnswerCanBeEnteredAtOnce() throws {
        try checkCorrectedAddition(largestText: false)
    }

    func testACorrectedAnswerCanBeEnteredAtOnceAtTheLargestTextSize() throws {
        try checkCorrectedAddition(largestText: true)
    }

    private func checkCorrectedAddition(largestText: Bool) throws {
        if largestText {
            extraLaunchArguments = Self.largestText
        }
        let size = largestText ? ", largest text" : ""
        launchApp()
        openYear(1)
        openActivity("Addition")
        let start = currentPoints()
        let (a, b) = operands(using: "+")
        let right = "\(a + b)"

        // One digit too many, so that one delete puts it right.
        replaceText(in: answerField, with: right + "1")
        let wrong = try enterThenEdit(expecting: Feedback.incorrect.rawValue, "Addition\(size), wrong answer") {
            typeAtOnce(XCUIKeyboardKey.delete.rawValue, into: answerField)
        }
        XCTAssertEqual(typedText(in: answerField), right, "The delete didn't put the answer right.")
        checkEnterAvailable(after: wrong, "Addition\(size), the answer put right")
        assertPoints(start)
        XCTAssertFalse(skipButton.exists, "Skip appeared after one wrong answer\(size).")

        try enterAndWatchCorrect(after: wrong, "Addition\(size), the corrected answer", field: answerField)
        waitForNextQuestion()
        assertPoints(start + 1)
        XCTAssertFalse(skipButton.exists, "Skip is still showing on the next question\(size).")
    }

    /// Answers changed and entered at once still count one by one: Skip comes after the second wrong answer, not
    /// before, and once the answer is right, Enter and Return during the move to the next question don't score again.
    func testQuickAnswersCountOnceEach() throws {
        launchApp()
        openYear(1)
        openActivity("Addition")
        let start = currentPoints()
        let (a, b) = operands(using: "+")
        let right = "\(a + b)"

        // Two digits too many: each delete gives a different answer, the first wrong, the second right.
        replaceText(in: answerField, with: right + "12")
        let first = try enterThenEdit(expecting: Feedback.incorrect.rawValue, "Addition, first wrong answer") {
            typeAtOnce(XCUIKeyboardKey.delete.rawValue, into: answerField)
        }
        XCTAssertEqual(typedText(in: answerField), right + "1")
        checkEnterAvailable(after: first, "Addition, the first wrong answer changed")
        XCTAssertFalse(skipButton.exists, "Skip appeared after one wrong answer.")

        let second = try enterThenEdit(expecting: Feedback.incorrect.rawValue, "Addition, second wrong answer") {
            typeAtOnce(XCUIKeyboardKey.delete.rawValue, into: answerField)
        }
        XCTAssertEqual(typedText(in: answerField), right)
        checkEnterAvailable(after: second, "Addition, the second wrong answer put right")
        XCTAssertTrue(skipButton.waitForExistence(timeout: 3), "Skip didn't appear after two wrong answers.")
        assertPoints(start)

        // Right: Enter again, and Return where the keyboard has it, until the next question.
        XCTAssertTrue(enterButton.isEnabled, "Enter can't be tapped for the corrected answer.")
        tap(enterButton)
        var shown: String?
        _ = waitQuickly(timeout: 3) {
            shown = shownMessage()
            return shown != nil
        }
        XCTAssertEqual(shown, Feedback.correct.rawValue, "The corrected answer wasn't marked right.")
        var presses = 0
        var returns = 0
        while presses < 6, typedText(in: answerField) == right {
            enterButton.tap()
            if answerField.hasKeyboardFocus, typedText(in: answerField) == right {
                answerField.typeText("\n")
                returns += 1
            }
            presses += 1
        }
        attachText("Presses after \"Correct!\"", "Enter \(presses) times, Return \(returns) times")
        waitForNextQuestion()
        assertPoints(start + 1)
        XCTAssertFalse(skipButton.exists, "Skip is still showing on the next question.")
    }

    // MARK: - Two boxes: Time

    /// The hours typed and Enter tapped too soon gives "Fill in both boxes." (batch FB-B). Once the minutes are typed,
    /// the message has gone, Enter can be tapped, and it marks the time right, once.
    func testTheSecondTimeBoxCanBeFilledInAndEnteredAtOnce() throws {
        try checkTimeFilledInAtOnce(largestText: false)
    }

    func testTheSecondTimeBoxCanBeFilledInAndEnteredAtOnceAtTheLargestTextSize() throws {
        try checkTimeFilledInAtOnce(largestText: true)
    }

    private func checkTimeFilledInAtOnce(largestText: Bool) throws {
        if largestText {
            extraLaunchArguments = Self.largestText
        }
        let size = largestText ? ", largest text" : ""
        // The app is launched by findQuestion, so the question is looked for only once it has been.
        let (label, hours, minutes) = try findQuestion(in: "Time", inYear: 3) { () -> (String, Int, Int)? in
            let question = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'What is the time '")).firstMatch
            guard question.waitForExistence(timeout: 2), let label = (try? question.snapshot())?.label,
                  let start = label.wholeMatch(of: #/What is the time (.+) after (\d\d):(\d\d)\?/#),
                  let startHour = Int(start.2), let startMinute = Int(start.3) else { return nil }
            let duration = String(start.1)
            let addedHours = duration.firstMatch(of: #/(\d+) hours?/#).flatMap { Int($0.1) } ?? 0
            let addedMinutes = duration.firstMatch(of: #/(\d+) minutes?/#).flatMap { Int($0.1) } ?? 0
            let end = (startHour * 60 + startMinute + addedHours * 60 + addedMinutes) % (24 * 60)
            return (label, end / 60, end % 60)
        }
        let h = String(format: "%02d", hours)
        let m = String(format: "%02d", minutes)
        attachText("Time question\(size)", "\(label) Answer \(h):\(m)")
        let start = currentPoints()
        let hoursBox = box(labelled: "Hours")
        let minutesBox = box(labelled: "Minutes")

        replaceText(in: hoursBox, with: h)
        let early = try enterThenEdit(expecting: Self.fillInBothBoxes, "Time\(size), the hours alone") {
            typeAtOnce(m, into: minutesBox)
        }
        XCTAssertEqual(typedText(in: hoursBox), h)
        XCTAssertEqual(typedText(in: minutesBox), m, "The minutes weren't typed.")
        checkEnterAvailable(after: early, "Time\(size), the minutes typed")
        assertPoints(start)
        XCTAssertFalse(skipButton.exists, "Skip appeared after \"Fill in both boxes.\"\(size).")

        try enterAndWatchCorrect(after: early, "Time\(size), both boxes", field: hoursBox)
        waitForNextTimeQuestion(after: label)
        assertPoints(start + 1)
        XCTAssertFalse(skipButton.exists)
    }

    // MARK: - Typing

    /// Types `text` at the end of what's in `field`, putting the cursor there first only if the field doesn't have it,
    /// as fast as XCUITest can.
    private func typeAtOnce(_ text: String, into field: XCUIElement) {
        if !field.hasKeyboardFocus {
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        }
        field.typeText(text)
    }

    // MARK: - Timing

    /// What happened after Enter and a change to the answer.
    private struct Edit {
        /// Just before Enter was tapped.
        let enter: Date
        /// When the tap on Enter had finished, in seconds after `enter`. The message's timer can't fire later than
        /// a second after this.
        let tapped: TimeInterval
        /// When the change had been typed, in seconds after `enter`.
        let edited: TimeInterval
        /// When the message had gone and Enter could be tapped, in seconds after `enter`, or nil if not within 3.
        let available: TimeInterval?
    }

    /// Taps Enter, checks that `expected` shows, makes `edit` straight away, and times when the message goes and
    /// Enter can be tapped again.
    private func enterThenEdit(expecting expected: String, _ when: String,
                               file: StaticString = #filePath, line: UInt = #line,
                               edit: () -> Void) throws -> Edit {
        XCTAssertTrue(waitQuickly(timeout: 5) { shownMessage() == nil && enterButton.isEnabled },
                      "\(when): Enter wasn't available to start with.", file: file, line: line)
        if keyboardCoversTapPoint(of: enterButton) {
            XCTFail("\(when): the keyboard covers Enter.", file: file, line: line)
            throw QuestionNotFound(description: "Enter is covered.")
        }
        let enter = Date()
        enterButton.tap()
        let tapped = Date().timeIntervalSince(enter)
        var shown: String?
        _ = waitQuickly(timeout: 3) {
            shown = shownMessage()
            return shown != nil
        }
        XCTAssertEqual(shown, expected, "\(when): unexpected message after Enter.", file: file, line: line)
        edit()
        let edited = Date().timeIntervalSince(enter)
        var available: TimeInterval?
        if waitQuickly(timeout: 3, until: { shownMessage() == nil && enterButton.isEnabled }) {
            available = Date().timeIntervalSince(enter)
        }
        attachText("\(when): timing", String(
            format: "message \"%@\"; Enter tapped by %.2f s; change typed by %.2f s; message gone and Enter available "
                + "at %@ (the message's own timer: %.2f–%.2f s, so the change came %@ it)",
            shown ?? "none", tapped, edited, available.map { String(format: "%.2f s", $0) } ?? "not within 3 s",
            Self.messageTime, tapped + Self.messageTime,
            edited < Self.messageTime ? "before" : "after"))
        return Edit(enter: enter, tapped: tapped, edited: edited, available: available)
    }

    /// The message went, and Enter could be tapped, after the change. Whether the change or the message's own timer
    /// hid it can't be told apart at XCUITest's speed (see the top of the file); the timing is attached.
    private func checkEnterAvailable(after edit: Edit, _ when: String,
                                     file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotNil(edit.available, "\(when): the message didn't go, or Enter stayed unavailable, for 3 seconds "
                        + "after the change.", file: file, line: line)
    }

    /// Taps Enter on the corrected answer, which must be marked right at once, then reads the screen until the next
    /// question: "Correct!" shows and no other message does. Whether "Correct!" outlasts the earlier message's timer
    /// is tested by the unit tests, since that timer has fired before XCUITest can tap Enter again.
    private func enterAndWatchCorrect(after earlier: Edit, _ when: String, field: XCUIElement,
                                      file: StaticString = #filePath, line: UInt = #line) throws {
        let answer = typedText(in: field)
        XCTAssertTrue(enterButton.isEnabled, "\(when): Enter can't be tapped for the corrected answer.",
                      file: file, line: line)
        let correctTapped = Date().timeIntervalSince(earlier.enter)
        enterButton.tap()
        var samples: [(time: TimeInterval, message: String?)] = []
        while Date().timeIntervalSince(earlier.enter) < correctTapped + 4 {
            let message = shownMessage()
            let time = Date().timeIntervalSince(earlier.enter)
            guard typedTextIfPresent(in: field) == answer else {
                break // The next question.
            }
            samples.append((time, message))
        }
        attachText("\(when): after Enter", samples.map {
            String(format: "%.2f s: %@", $0.time, $0.message ?? "no message")
        }.joined(separator: "\n") + String(format: "\nEnter tapped at %.2f s after the earlier Enter; the earlier "
                                          + "message's own timer had fired by %.2f s", correctTapped,
                                          earlier.tapped + Self.messageTime))

        XCTAssertTrue(samples.contains { $0.message == Feedback.correct.rawValue },
                      "\(when): \"Correct!\" never showed.", file: file, line: line)
        XCTAssertTrue(samples.allSatisfy { $0.message == nil || $0.message == Feedback.correct.rawValue },
                      "\(when): another message showed.", file: file, line: line)
    }

    /// What's typed in `field`, read in one snapshot, or nil once it has gone. Checking `exists` and then reading the
    /// value can fail between the two when the next question replaces the box: after a Time answer the next question
    /// may be setting the clock, which has no Hours box.
    private func typedTextIfPresent(in field: XCUIElement) -> String? {
        guard let snapshot = try? field.snapshot() else { return nil }
        let value = snapshot.value as? String ?? ""
        return value == snapshot.placeholderValue ? "" : value
    }
}
