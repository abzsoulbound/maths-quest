//
//  Stage9BInteractionUITests.swift
//  Maths QuestUITests
//

import UIKit
import XCTest

/// Stage 9B: the question stays in view through a whole attempt, not only when the keyboard first comes up, which
/// Stage9BKeyboardUITests checks. On the questions most likely to be crowded:
/// 1. With the keyboard down, the question's words and pictures, the answer boxes and Enter are read from one
///    snapshot.
/// 2. A wrong answer is typed in each answer box in turn, which brings the keyboard up and moves between the boxes.
///    Each time, the question, every answer box and Enter must be entirely in view between the header and the
///    keyboard's glass.
/// 3. Enter, then straight away a tap back in the first answer box, as a player keen to try again might do while
///    "Incorrect. Try Again!" shows. While the message and the keyboard are both up, the question, the answer boxes
///    and the message's first line must be in view. XCUITest waits for the app to stop animating before and after
///    each tap, so by the time it can look, the message has a fraction of a second left at most. If it has gone, the
///    check is reported as not seen, never as passed.
/// 4. Once the message has gone, with the keyboard up, the wrong answer is still there to correct, the question, the
///    answer boxes and Enter are in view, and Skip hasn't appeared.
/// 5. A second wrong answer, sent with Return where the keyboard has one and with Enter where it doesn't. Either puts
///    the keyboard away. While the message shows, all of it, Enter and Skip must be in view, and so must the question
///    and the answer boxes. At the usual text sizes a question that only just fits can lose its top to the message for
///    that second: that fails, marked "KEYBOARD-DOWN MESSAGE". At an accessibility text size on an iPhone, where a
///    question can be taller than the screen anyway, it's reported without failing.
/// 6. After the message, with the keyboard down and then up, Skip is in view beside Enter, with the question and the
///    answer boxes, and the points haven't changed.
///
/// At an accessibility text size on an iPhone, the explicit requirement in `Stage9BKeyboardUITests` replaces "the
/// question is in view" with the keyboard up: whatever of it isn't in view while typing (step 2) and with Skip showing
/// (step 6) must be dragged into view and read with the keyboard up, the cursor and what was typed staying put, and
/// then the answer boxes, Enter and Skip dragged back into view. The answer boxes, Enter, Skip and the message must be
/// in view at every size, and an iPad must show everything at every size. The screenshots at steps 1, 2 and 6 are read
/// for text cut short with "…", which fails at every size.
///
/// `testCountingRightAnswerAndTheNextQuestion` gives a right answer instead: the question stays in view while
/// "Correct!" shows, a point is added, and the next question comes up with its answer box ready.
///
/// Skip is never tapped: it shows a rewarded test ad. Each question prints a line starting "D9I|" and attaches it,
/// with every snapshot taken while a message showed. A check made while a test ad covers the screen fails.
class Stage9BInteractionChecks: MathsQuestUITestCase {

    /// A plain wrong answer: one the activity marks "Incorrect. Try Again!" rather than asking for it to be written
    /// differently.
    enum WrongAnswer {
        /// 9999, bigger than any answer, in every box.
        case number
        /// Letters that name no angle or category.
        case word
        /// One more than the missing Counting number.
        case nextCountingNumber
        /// 98 over 99, which no probability question has as its answer.
        case fraction
    }

    /// The question with the keyboard down, before any answer: what must stay in view. Its words, pictures and the
    /// parts of its answer row are found again in later snapshots by their keys.
    struct Question {
        var words: [MathsQuestUITestCase.QuestionPart]
        var pictures: [MathsQuestUITestCase.QuestionPart]
        /// Units, unit wheels and box labels by the answer boxes.
        var answerRow: [MathsQuestUITestCase.QuestionPart]
        var boxCount: Int
    }

    /// What must be entirely in view.
    struct Check: OptionSet {
        let rawValue: Int

        static let words = Check(rawValue: 1)
        static let pictures = Check(rawValue: 2)
        /// The answer boxes and the rest of the answer row.
        static let boxes = Check(rawValue: 4)
        static let enter = Check(rawValue: 8)
        static let skip = Check(rawValue: 16)
        /// The first line of the message after Enter, which says whether the answer was right.
        static let messageFirstLine = Check(rawValue: 32)
        static let wholeMessage = Check(rawValue: 64)

        static let question: Check = [.words, .pictures]
    }

    /// The screen, read once while a message comes and goes.
    struct Sample {
        /// Seconds since the watch started, at the middle of the snapshot.
        let time: TimeInterval
        let parts: MathsQuestUITestCase.QuestionParts
    }

    /// Whether the question's words and pictures may be out of view with the keyboard up, as long as they can be
    /// dragged into view: at an accessibility text size on an iPhone. See the class's description.
    @MainActor
    var questionMayScroll: Bool { usesAccessibilityText && UIDevice.current.userInterfaceIdiom != .pad }

    @MainActor
    var device: String { ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? UIDevice.current.model }

    /// When this test last launched the app.
    var launchedAt: Date?

    // MARK: - Wrong answers

    /// Gives two wrong answers to a question of `activity` (one starting with `question` and ending with `ending`, if
    /// given) and checks what's in view at every step. See the class's description. Throws XCTSkip if the keyboard
    /// never comes up.
    @MainActor
    func checkWrongAnswers(_ name: String, on activity: String, inYear year: Int, startingWith question: String? = nil,
                           endingWith ending: String? = nil, typing kind: WrongAnswer) throws {
        continueAfterFailure = true
        guard openQuestion(activity, inYear: year, startingWith: question, endingWith: ending) else {
            return
        }
        let accessibilityText = usesAccessibilityText
        let mayScroll = questionMayScroll
        let adWarning = "\(name): a test ad covered the screen, so this check doesn't count."
        var log: [String] = []
        var ocr = ReadingTally()

        // 1. The keyboard down.
        XCTAssertFalse(text("Test mode").exists, adWarning)
        _ = waitForFrameToSettle(of: anyEnterButton, timeout: 3, steadyFor: 0.3)
        let down = questionParts()
        let asked = Question(words: down.questionWords, pictures: down.questionPictures,
                             answerRow: down.answerRow, boxCount: down.answerBoxes.count)
        let points = currentPoints()
        log += ["Keyboard down", describe(down, in: visibleArea(of: down, overhang: 0))]
        screenshotAndCheckTheText("\(name): 1 keyboard down", down, in: visibleArea(of: down, overhang: 0), tally: &ocr)
        guard asked.boxCount >= 1, !asked.words.isEmpty else {
            XCTFail("\(name): no question with an answer box was found.\n\(log.joined(separator: "\n"))")
            return
        }
        fail(hidden(accessibilityText ? .words : [.question, .boxes, .enter], in: down, overhang: 0, question: asked),
             "\(name), keyboard down")
        if accessibilityText {
            // A question taller than the screen can have its answer boxes below the bottom edge, so a player scrolls
            // down to them before typing.
            scrollAnswerFieldIntoView()
        }

        // 2. A wrong answer typed in each box in turn, with the keyboard up.
        let answers = wrongAnswers(kind, boxes: asked.boxCount)
        guard answers.count == asked.boxCount else {
            XCTFail("\(name): \(answers.count) wrong answers for \(asked.boxCount) answer boxes.")
            return
        }
        let boxes = (0..<asked.boxCount).map { app.textFields.element(boundBy: $0) }
        guard showKeyboard(typing: answers[0], into: boxes[0]) else {
            throw XCTSkip(LayoutUITests.noKeyboard(on: activity))
        }
        let overhang = keyboard.frame.minY - keyboardGlassFrame.minY
        let keyboardKind = UIDevice.current.userInterfaceIdiom == .pad
            ? "iPad keyboard"
            : (keyboardHasLetters ? "letters" : "number pad")
        var typingHidden: [String] = []
        // What of the question wasn't in view while typing, as it was with the keyboard down, to be reached.
        var typingToReach: [QuestionPart] = []
        var typedInto = 0
        for index in boxes.indices {
            if index > 0 {
                guard !keyboardCoversTapPoint(of: boxes[index]) else {
                    XCTFail("\(name): answer box \(index + 1) is under the keyboard, so it can't be tapped.")
                    typingHidden.append("answer box \(index + 1)")
                    break
                }
                focus(boxes[index])
                boxes[index].typeText(answers[index])
                waitForKeyboardToSettle()
                typedInto = index
            }
            _ = waitForFrameToSettle(of: anyEnterButton, timeout: 3, steadyFor: 0.3)
            XCTAssertFalse(text("Test mode").exists, adWarning)
            let typing = questionParts()
            let typingArea = visibleArea(of: typing, overhang: overhang)
            typingHidden += checkInView([.question, .boxes, .enter], in: typing, overhang: overhang, question: asked,
                                        questionMayScroll: mayScroll,
                                        "\(name), keyboard up, typing in answer box \(index + 1)")
            for part in hiddenQuestionParts(asked, in: typing, overhang: overhang)
            where !typingToReach.contains(where: { $0.key == part.key }) {
                typingToReach.append(part)
            }
            log += ["", "Keyboard up, typing in answer box \(index + 1)", describe(typing, in: typingArea)]
            screenshotAndCheckTheText("\(name): 2 keyboard up, answer box \(index + 1) (\(keyboardKind))", typing,
                                      in: typingArea, tally: &ocr)
        }
        // At an accessibility size on an iPhone, whatever of the question wasn't in view while typing must be within
        // reach with the keyboard up, and the player must get back to the answer with what they typed still there.
        var typingReach = "n/a"
        if mayScroll && !typingToReach.isEmpty {
            typingReach = reachEveryHiddenPart(of: name, typingToReach, typingInto: boxes[typedInto],
                                               typed: answers[typedInto], ocr: &ocr)
        }
        for (index, box) in boxes.enumerated() {
            XCTAssertEqual(typedText(in: box), answers[index], "\(name): answer box \(index + 1) doesn't show what was typed.")
        }
        XCTAssertFalse(skipButton.exists, "\(name): Skip showed before any answer was given.")

        // 3. Enter, then straight back into the first answer box while the message shows.
        tap(anyEnterButton)
        let enteredAt = Date()
        boxes[0].coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let tapBackAfter = Date().timeIntervalSince(enteredAt)
        let firstWatch = watchMessage(from: enteredAt,
                                      screenshot: ("\(name): 3 keyboard up while the message shows", true))
        let firstMessage = firstWatch.compactMap(\.parts.message).first?.label
        if let firstMessage {
            XCTAssertEqual(firstMessage, Feedback.incorrect.rawValue, "\(name): unexpected message after the first wrong answer.")
        }
        let bothUp = firstWatch.filter { $0.parts.message != nil && $0.parts.keyboardUp }
        let bothUpStill = settled(firstWatch, keyboardUp: true)
        var tapBackHidden: [String] = []
        for sample in bothUpStill {
            let when = "\(name), keyboard up while the message shows (\(seconds(sample.time)) after Enter)"
            var problems = hidden([.boxes, .messageFirstLine], in: sample.parts, overhang: overhang, question: asked)
            fail(problems, when)
            let questionProblems = hidden(.question, in: sample.parts, overhang: overhang, question: asked)
            if !mayScroll {
                fail(questionProblems, when)
            }
            problems += questionProblems
            tapBackHidden += problems
        }
        let race: String
        if let first = bothUp.first, let last = bothUp.last {
            race = "both up \(seconds(first.time))-\(seconds(last.time)) after Enter, \(bothUp.count) snapshots, "
                + "\(bothUpStill.count) still"
        } else if firstMessage == nil {
            race = "not seen: the message had gone before the first snapshot"
        } else {
            race = "not seen: the keyboard wasn't up while the message showed"
        }
        attachText("\(name): snapshots after Enter and the tap back", sampleLog(firstWatch, overhang: overhang))

        // 4. The message gone, with the keyboard up.
        let firstMessageGone = waitQuickly(timeout: 3) { visibleFeedback() == nil }
        XCTAssertTrue(firstMessageGone, "\(name): the first message didn't go.")
        guard bringKeyboardUp(for: boxes[0]) else {
            XCTFail("\(name): the keyboard didn't come up after the first message.")
            return
        }
        XCTAssertFalse(text("Test mode").exists, adWarning)
        let again = questionParts()
        let againHidden = checkInView([.question, .boxes, .enter], in: again, overhang: overhang, question: asked,
                                      questionMayScroll: mayScroll, "\(name), keyboard up after the first message")
        for (index, box) in boxes.enumerated() {
            XCTAssertEqual(typedText(in: box), answers[index],
                           "\(name): the wrong answer in answer box \(index + 1) wasn't kept to correct.")
        }
        let skipAfterOne = skipButton.exists
        XCTAssertFalse(skipAfterOne, "\(name): Skip showed after one wrong answer.")
        log += ["", "Keyboard up after the first message", describe(again, in: visibleArea(of: again, overhang: overhang))]
        attachScreenshot("\(name): 4 keyboard up after the first message")

        // 5. A second wrong answer. Return and Enter both put the keyboard away.
        for (index, box) in boxes.enumerated() {
            guard !keyboardCoversTapPoint(of: box) else {
                XCTFail("\(name): answer box \(index + 1) is under the keyboard, so it can't be tapped.")
                return
            }
            replaceText(in: box, with: answers[index])
        }
        let usesReturn = UIDevice.current.userInterfaceIdiom == .pad || keyboardHasLetters
        _ = waitForFrameToSettle(of: anyEnterButton, timeout: 3, steadyFor: 0.3)
        if usesReturn {
            boxes[boxes.count - 1].typeText(XCUIKeyboardKey.return.rawValue)
        } else {
            tap(anyEnterButton)
        }
        let secondWatch = watchMessage(from: Date(),
                                       screenshot: ("\(name): 5 keyboard down while the second message shows", false))
        let secondMessage = secondWatch.compactMap(\.parts.message).first?.label
        XCTAssertEqual(secondMessage, Feedback.incorrect.rawValue,
                       "\(name): the second wrong answer didn't bring up \"\(Feedback.incorrect.rawValue)\".")
        let downStill = settled(secondWatch, keyboardUp: false)
        if secondMessage != nil && downStill.isEmpty {
            XCTFail("UNVERIFIED: \(name): the message after the second wrong answer was never seen standing still with "
                + "the keyboard down, so what was in view then couldn't be checked.")
        }
        var messageHidden: [String] = []
        var messageQuestionHidden: [String] = []
        var hiddenBy: CGFloat = 0
        for sample in downStill {
            messageHidden += hidden([.boxes, .wholeMessage, .enter, .skip], in: sample.parts, overhang: overhang,
                                    question: asked)
            messageQuestionHidden += hidden(.question, in: sample.parts, overhang: overhang, question: asked)
            hiddenBy = max(hiddenBy, hiddenAbove(asked, in: sample.parts, overhang: overhang))
        }
        fail(messageHidden, "\(name), keyboard down while the second message shows")
        if !messageQuestionHidden.isEmpty && !mayScroll {
            XCTFail("KEYBOARD-DOWN MESSAGE: \(name): while \"\(Feedback.incorrect.rawValue)\" shows with the keyboard "
                + "down, the question isn't entirely in view: \(unique(messageQuestionHidden).joined(separator: "; ")). "
                + "Up to \(Int(hiddenBy.rounded(.up))) pt of it is above the visible area.")
        }
        attachText("\(name): snapshots after the second answer", sampleLog(secondWatch, overhang: overhang))

        // 6. After the second message: Skip beside Enter, with the keyboard down and then up.
        let secondMessageGone = waitQuickly(timeout: 3) { visibleFeedback() == nil }
        XCTAssertTrue(secondMessageGone, "\(name): the second message didn't go.")
        let skipAfterTwo = skipButton.waitForExistence(timeout: 5)
        XCTAssertTrue(skipAfterTwo, "\(name): Skip didn't appear after two wrong answers.")
        _ = waitForFrameToSettle(of: anyEnterButton, timeout: 3, steadyFor: 0.3)
        XCTAssertFalse(text("Test mode").exists, adWarning)
        let skipDown = questionParts()
        let skipDownHidden = hidden([.boxes, .enter, .skip], in: skipDown, overhang: overhang, question: asked)
        fail(skipDownHidden, "\(name), keyboard down with Skip showing")
        let skipDownQuestion = hidden(.question, in: skipDown, overhang: overhang, question: asked)
        if !mayScroll {
            fail(skipDownQuestion, "\(name), keyboard down with Skip showing")
        }
        let skipDownArea = visibleArea(of: skipDown, overhang: overhang)
        log += ["", "Keyboard down with Skip", describe(skipDown, in: skipDownArea)]
        screenshotAndCheckTheText("\(name): 6 keyboard down with Skip", skipDown, in: skipDownArea, tally: &ocr)
        guard bringKeyboardUp(for: boxes[0]) else {
            XCTFail("\(name): the keyboard didn't come up with Skip showing.")
            return
        }
        XCTAssertFalse(text("Test mode").exists, adWarning)
        let skipUp = questionParts()
        let skipUpArea = visibleArea(of: skipUp, overhang: overhang)
        let skipUpHidden = checkInView([.question, .boxes, .enter, .skip], in: skipUp, overhang: overhang,
                                       question: asked, questionMayScroll: mayScroll,
                                       "\(name), keyboard up with Skip showing")
        log += ["", "Keyboard up with Skip", describe(skipUp, in: skipUpArea)]
        screenshotAndCheckTheText("\(name): 6 keyboard up with Skip", skipUp, in: skipUpArea, tally: &ocr)
        // As in step 2, and then the answer boxes, Enter and Skip must all be back in view.
        var skipReach = "n/a"
        let skipToReach = hiddenQuestionParts(asked, in: skipUp, overhang: overhang)
        if mayScroll && !skipToReach.isEmpty {
            let typedBeforeReading = typedText(in: boxes[0])
            skipReach = reachEveryHiddenPart(of: "\(name), Skip showing", skipToReach, typingInto: boxes[0],
                                             typed: typedBeforeReading, ocr: &ocr)
            let back = questionParts()
            let backHidden = hidden([.boxes, .enter, .skip], in: back, overhang: overhang, question: asked)
            fail(backHidden, "\(name), keyboard up with Skip showing, back at the answer after reading the question")
            skipReach += backHidden.isEmpty ? ", Skip back yes" : ", back hidden " + unique(backHidden).joined(separator: " / ")
        }
        let pointsAfter = currentPoints()
        XCTAssertEqual(pointsAfter, points, "\(name): wrong answers changed the points.")

        // 7. The line for the report.
        var keyboardDownMessage = downStill.isEmpty
            ? "not checked"
            : verdict(messageHidden + messageQuestionHidden)
        if hiddenBy > 0 {
            keyboardDownMessage += " (\(Int(hiddenBy.rounded(.up)))pt above)"
        }
        let fields: [String] = [
            "D9I", device, textSizeName, name, keyboardKind,
            "typing " + verdict(typingHidden),
            "tap back after \(seconds(tapBackAfter)): \(race)",
            "message+keyboard up " + (bothUpStill.isEmpty ? "not checked" : verdict(tapBackHidden)),
            "after message kb up " + verdict(againHidden),
            "kb-down message " + keyboardDownMessage,
            "Skip kb down " + verdict(skipDownHidden) + ", question " + verdict(skipDownQuestion),
            "Skip kb up " + verdict(skipUpHidden),
            "Skip after 1 \(skipAfterOne ? "yes" : "no"), after 2 \(skipAfterTwo ? "yes" : "no")",
            "points \(points)>\(pointsAfter)",
            "second sent with \(usesReturn ? "Return" : "Enter")",
            "reach typing \(typingReach)",
            "reach Skip \(skipReach)",
            ocr.summary,
        ]
        let line = fields.joined(separator: "|")
        print(line)
        attachText("\(name): D9I", ([line, ""] + log).joined(separator: "\n"))
    }

    // MARK: - A right answer

    /// Answers a Counting question rightly, taps back in the answer box while "Correct!" shows, and checks the next
    /// question.
    @MainActor
    func checkRightAnswer() throws {
        continueAfterFailure = true
        let name = "Counting, right answer"
        guard openQuestion("Counting", inYear: 1) else {
            return
        }
        let adWarning = "\(name): a test ad covered the screen, so this check doesn't count."
        XCTAssertFalse(text("Test mode").exists, adWarning)
        _ = waitForFrameToSettle(of: anyEnterButton, timeout: 3, steadyFor: 0.3)
        let down = questionParts()
        let asked = Question(words: down.questionWords, pictures: down.questionPictures,
                             answerRow: down.answerRow, boxCount: down.answerBoxes.count)
        let points = currentPoints()
        let missing = missingCountingNumber()
        guard showKeyboard(typing: "\(missing)", into: answerField) else {
            throw XCTSkip(LayoutUITests.noKeyboard(on: "Counting"))
        }
        let overhang = keyboard.frame.minY - keyboardGlassFrame.minY
        _ = waitForFrameToSettle(of: anyEnterButton, timeout: 3, steadyFor: 0.3)
        XCTAssertFalse(text("Test mode").exists, adWarning)
        let up = questionParts()
        let upHidden = hidden([.question, .boxes, .enter], in: up, overhang: overhang, question: asked)
        fail(upHidden, "\(name), keyboard up")
        attachScreenshot("\(name): keyboard up")

        tap(anyEnterButton)
        let enteredAt = Date()
        answerField.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let tapBackAfter = Date().timeIntervalSince(enteredAt)
        let watch = watchMessage(from: enteredAt, screenshot: ("\(name): keyboard up while \"Correct!\" shows", true))
        let seen = watch.compactMap(\.parts.message).first?.label
        if let seen {
            XCTAssertEqual(seen, Feedback.correct.rawValue, "\(name): unexpected message after the right answer.")
        }
        let bothUp = watch.filter { $0.parts.message != nil && $0.parts.keyboardUp }
        let bothUpStill = settled(watch, keyboardUp: true)
        var duringHidden: [String] = []
        for sample in bothUpStill {
            // The question changes a second after "Correct!", so it's whatever is above the answer box at the time.
            let problems = hidden([.question, .boxes, .messageFirstLine], in: sample.parts, overhang: overhang, question: nil)
            fail(problems, "\(name), keyboard up while \"Correct!\" shows (\(seconds(sample.time)) after Enter)")
            duringHidden += problems
        }
        attachText("\(name): snapshots after Enter and the tap back", sampleLog(watch, overhang: overhang))

        waitForNextQuestion()
        assertPoints(points + 1)
        XCTAssertFalse(skipButton.exists, "\(name): Skip showed after a right answer.")
        guard bringKeyboardUp(for: answerField) else {
            XCTFail("\(name): the keyboard didn't come up for the next question.")
            return
        }
        XCTAssertFalse(text("Test mode").exists, adWarning)
        let next = questionParts()
        let nextHidden = hidden([.question, .boxes, .enter], in: next, overhang: overhang, question: nil)
        fail(nextHidden, "\(name), the next question with the keyboard up")
        XCTAssertEqual(typedText(in: answerField), "", "\(name): the next question's answer box isn't empty.")
        let changed = next.questionWords.map(\.label) != asked.words.map(\.label)
        attachScreenshot("\(name): the next question with the keyboard up")

        let race: String
        if let first = bothUp.first, let last = bothUp.last {
            race = "both up \(seconds(first.time))-\(seconds(last.time)) after Enter, \(bothUp.count) snapshots, "
                + "\(bothUpStill.count) still"
        } else {
            race = seen == nil ? "not seen: the message had gone before the first snapshot"
                : "not seen: the keyboard wasn't up while the message showed"
        }
        let fields: [String] = [
            "D9I", device, textSizeName, name, "number pad",
            "typing " + verdict(upHidden),
            "tap back after \(seconds(tapBackAfter)): \(race)",
            "message+keyboard up " + (bothUpStill.isEmpty ? "not checked" : verdict(duringHidden)),
            "next question kb up " + verdict(nextHidden),
            "question changed \(changed ? "yes" : "no")",
            "points \(points)>\(currentPoints())",
        ]
        let line = fields.joined(separator: "|")
        print(line)
        attachText("\(name): D9I", line)
    }

    // MARK: - Helpers

    /// Opens `activity` until it shows a question with an answer box, starting with `question` and ending with
    /// `ending` if they're given. The app is launched afresh at the start and every 75 seconds, well before the
    /// interstitial can come up at a menu, about three minutes after launch.
    @MainActor
    func openQuestion(_ activity: String, inYear year: Int, startingWith question: String? = nil,
                      endingWith ending: String? = nil, attempts: Int = 45) -> Bool {
        for _ in 1...attempts {
            if launchedAt.map({ Date().timeIntervalSince($0) > 75 }) ?? true {
                launchApp()
                launchedAt = Date()
            }
            openYear(year)
            openActivity(activity)
            var isWanted = true
            if let question {
                let wanted = ending.map {
                    NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@", question, $0)
                } ?? NSPredicate(format: "label BEGINSWITH %@", question)
                isWanted = app.staticTexts.matching(wanted).firstMatch.waitForExistence(timeout: 2)
            }
            if isWanted && answerField.waitForExistence(timeout: 2) {
                return true
            }
            goHome()
        }
        let start = question.map { " starting \"\($0)\"" } ?? ""
        let end = ending.map { " and ending \"\($0)\"" } ?? ""
        XCTFail("No \(activity) question\(start)\(end) with an answer box came up in \(attempts) tries.")
        return false
    }

    @MainActor
    func wrongAnswers(_ kind: WrongAnswer, boxes: Int) -> [String] {
        switch kind {
        case .number:
            return Array(repeating: "9999", count: boxes)
        case .word:
            return Array(repeating: "zz", count: boxes)
        case .nextCountingNumber:
            return ["\(missingCountingNumber() + 1)"]
        case .fraction:
            return ["98", "99"]
        }
    }

    /// Brings the keyboard up for `field` by tapping it, as a player would, unless it's up already, and waits for it
    /// to settle. Returns false if it doesn't come up.
    @MainActor
    func bringKeyboardUp(for field: XCUIElement) -> Bool {
        if !(keyboardIsOnScreen && field.hasKeyboardFocus) {
            guard !keyboardCoversTapPoint(of: field) else {
                XCTFail("The answer box at \(field.frame) is under the keyboard, so it can't be tapped.")
                return false
            }
            focus(field)
        }
        if !waitQuickly(timeout: 2, until: { keyboardIsOnScreen }) {
            // Focusing can leave the keyboard parked below the screen, and typing brings it up. The character is
            // deleted straight away, so the answer is as it was.
            field.typeText("1")
            field.typeText(XCUIKeyboardKey.delete.rawValue)
        }
        guard waitQuickly(timeout: 5, until: { keyboardIsOnScreen }) else {
            return false
        }
        waitForKeyboardToSettle()
        _ = waitForFrameToSettle(of: anyEnterButton, timeout: 3, steadyFor: 0.3)
        return true
    }

    /// Reads the screen as often as snapshots allow from `start`, until a message has come and gone or `duration`
    /// seconds have passed. Given `screenshot`, takes one screenshot the first time two snapshots in a row agree with
    /// the message showing and the keyboard up or down as asked.
    @MainActor
    func watchMessage(from start: Date, for duration: TimeInterval = 4,
                      screenshot: (name: String, keyboardUp: Bool)? = nil) -> [Sample] {
        var samples: [Sample] = []
        var sawMessage = false
        var tookScreenshot = false
        let deadline = start.addingTimeInterval(duration)
        while Date() < deadline {
            let before = Date()
            let parts = questionParts()
            guard !parts.area.isNull else {
                continue // The snapshot failed.
            }
            let sample = Sample(time: (before.timeIntervalSince(start) + Date().timeIntervalSince(start)) / 2,
                                parts: parts)
            if let screenshot, !tookScreenshot, let previous = samples.last,
               previous.parts.message != nil, parts.message != nil,
               previous.parts.keyboardUp == screenshot.keyboardUp, parts.keyboardUp == screenshot.keyboardUp,
               agree(previous.parts, parts) {
                attachScreenshot(screenshot.name)
                tookScreenshot = true
            }
            samples.append(sample)
            if parts.message != nil {
                sawMessage = true
            } else if sawMessage {
                break
            }
        }
        return samples
    }

    /// How long the keyboard, the message, Enter and the answer boxes must have stayed where they are for a snapshot to
    /// count as taken while nothing was moving. Two snapshots in a row can agree while the question is still scrolling:
    /// near the end of a scroll it moves a pixel at a time and stays on each pixel for a few snapshots. On the iPhone SE
    /// at the first accessibility size, the message's first line was 1.5 points under the keyboard's glass in two
    /// snapshots in a row, and then rose a pixel at a time to rest in view 0.2 seconds later.
    static let stillFor: TimeInterval = 0.15

    /// The samples taken while nothing was moving: each that agrees with every sample in the `stillFor` seconds before
    /// it, all with the message showing and the keyboard up or down as given.
    func settled(_ samples: [Sample], keyboardUp: Bool) -> [Sample] {
        func showing(_ sample: Sample) -> Bool {
            sample.parts.message != nil && sample.parts.keyboardUp == keyboardUp
        }
        return samples.indices.compactMap { index in
            let sample = samples[index]
            guard showing(sample) else {
                return nil
            }
            var earlier = index - 1
            while earlier >= 0, showing(samples[earlier]), agree(samples[earlier].parts, sample.parts) {
                if sample.time - samples[earlier].time >= Self.stillFor {
                    return sample
                }
                earlier -= 1
            }
            return nil
        }
    }

    /// Whether the keyboard, the message, Enter and the answer boxes are where they were.
    func agree(_ a: QuestionParts, _ b: QuestionParts) -> Bool {
        func same(_ x: CGRect?, _ y: CGRect?) -> Bool {
            switch (x, y) {
            case (nil, nil):
                return true
            case let (x?, y?):
                if x.isNull || y.isNull {
                    return x.isNull && y.isNull
                }
                return abs(x.minX - y.minX) <= 0.5 && abs(x.minY - y.minY) <= 0.5
                    && abs(x.width - y.width) <= 0.5 && abs(x.height - y.height) <= 0.5
            default:
                return false
            }
        }
        return same(a.keyboard, b.keyboard) && same(a.message?.frame, b.message?.frame) && same(a.enter, b.enter)
            && a.answerBoxes.count == b.answerBoxes.count
            && zip(a.answerBoxes, b.answerBoxes).allSatisfy { same($0, $1) }
    }

    /// What `checks` finds not entirely in view in `parts`, with the keyboard's glass `overhang` points above the
    /// keyboard: empty if everything is in view. Given `question`, its words, pictures and answer row are found again
    /// by key, and one that has gone counts as hidden. Without it, the question is whatever is above the answer boxes.
    func hidden(_ checks: Check, in parts: QuestionParts, overhang: CGFloat, question: Question?) -> [String] {
        let area = visibleArea(of: parts, overhang: overhang)
        let shown = parts.byKey
        var found: [String] = []
        func check(_ name: String, _ frame: CGRect?) {
            guard let frame, !frame.isNull else {
                found.append("\(name) (gone)")
                return
            }
            if !isInView(frame, area) {
                found.append("\(name) (\(percentInView(frame, area))% in view)")
            }
        }
        if let question {
            if checks.contains(.words) {
                for part in question.words {
                    check("\"\(part.shortLabel)\"", shown[part.key]?.frame)
                }
            }
            if checks.contains(.pictures) {
                for part in question.pictures {
                    check("picture \(part.shortLabel)", shown[part.key]?.frame)
                }
            }
        } else {
            if checks.contains(.words) {
                for part in parts.questionWords {
                    check("\"\(part.shortLabel)\"", part.frame)
                }
            }
            if checks.contains(.pictures) {
                for part in parts.questionPictures {
                    check("picture \(part.shortLabel)", part.frame)
                }
            }
        }
        if checks.contains(.boxes) {
            let expected = question?.boxCount ?? parts.answerBoxes.count
            if parts.answerBoxes.count != expected || expected == 0 {
                found.append("answer boxes (\(parts.answerBoxes.count) of \(expected) found)")
            }
            for (index, box) in parts.answerBoxes.enumerated() {
                check("answer box \(index + 1)", box)
            }
            for part in question?.answerRow ?? [] {
                check(part.shortLabel, shown[part.key]?.frame)
            }
        }
        if checks.contains(.enter) {
            check("Enter", parts.enter)
        }
        if checks.contains(.skip) {
            check("Skip", parts.skip)
        }
        if checks.contains(.wholeMessage) {
            check("the message", parts.message?.frame)
        } else if checks.contains(.messageFirstLine) {
            let firstLine = parts.message.map {
                CGRect(x: $0.frame.minX, y: $0.frame.minY, width: $0.frame.width,
                       height: min($0.frame.height, messageLineHeight(in: parts)))
            }
            check("the message's first line", firstLine)
        }
        return found
    }

    /// What `checks` finds not entirely in view in `parts`, failing on all of it, unless `questionMayScroll`: then the
    /// question's words and pictures out of view are only returned, for `reachEveryHiddenPart` to drag into view, and
    /// the rest must be in view. A picture that has gone altogether still fails: unlike rows of numbers far off screen,
    /// a picture doesn't drop out of what XCUITest sees.
    func checkInView(_ checks: Check, in parts: QuestionParts, overhang: CGFloat, question: Question,
                     questionMayScroll: Bool, _ when: String,
                     file: StaticString = #filePath, line: UInt = #line) -> [String] {
        let questionHidden = hidden(checks.intersection(.question), in: parts, overhang: overhang, question: question)
        let otherHidden = hidden(checks.subtracting(.question), in: parts, overhang: overhang, question: question)
        if questionMayScroll {
            let shown = parts.byKey
            let gonePictures = checks.contains(.pictures)
                ? question.pictures.filter { shown[$0.key].map(\.frame.isNull) ?? true }
                    .map { "picture \($0.shortLabel) (gone)" }
                : []
            fail(gonePictures + otherHidden, when, file: file, line: line)
        } else {
            fail(questionHidden + otherHidden, when, file: file, line: line)
        }
        return questionHidden + otherHidden
    }

    /// The question's words and pictures not entirely in view in `parts`, as they were with the keyboard down, for
    /// `reachEveryHiddenPart`.
    func hiddenQuestionParts(_ question: Question, in parts: QuestionParts, overhang: CGFloat) -> [QuestionPart] {
        let area = visibleArea(of: parts, overhang: overhang)
        let shown = parts.byKey
        return (question.words + question.pictures).filter { part in
            shown[part.key].map { !isInView($0.frame, area) } ?? true
        }
    }

    /// How far the top of `question` is above the visible area, or 0.
    func hiddenAbove(_ question: Question, in parts: QuestionParts, overhang: CGFloat) -> CGFloat {
        let area = visibleArea(of: parts, overhang: overhang)
        let shown = parts.byKey
        guard let top = (question.words + question.pictures).compactMap({ shown[$0.key]?.frame.minY }).min() else {
            return 0
        }
        return max(0, area.minY - top)
    }

    /// The height of the message's first line. Like `AnswerFeedbackText`, which keeps that line in view while the
    /// keyboard is up: bold, at 7.5% of the content's width, which is the screen's up to 600 points.
    func messageLineHeight(in parts: QuestionParts) -> CGFloat {
        let width = min(parts.window.isNull ? parts.area.width : parts.window.width, 600)
        return UIFont.systemFont(ofSize: width * 0.075, weight: .bold).lineHeight
    }

    /// Every snapshot taken while watching a message, for the attachments.
    func sampleLog(_ samples: [Sample], overhang: CGFloat) -> String {
        let lines = samples.map { sample -> String in
            let parts = sample.parts
            let top = parts.questionWords.map(\.frame.minY).min()
            let fields: [String] = [
                seconds(sample.time),
                parts.keyboardUp ? "keyboard \(parts.keyboard)" : "keyboard down",
                "message " + (parts.message.map { "\"\($0.label)\" \($0.frame)" } ?? "none"),
                "boxes \(parts.answerBoxes)",
                "Enter " + (parts.enter.map { "\($0)" } ?? "none"),
                "Skip " + (parts.skip.map { "\($0)" } ?? "none"),
                "visible \(visibleArea(of: parts, overhang: overhang))",
                "top of the words " + (top.map { "\($0)" } ?? "none"),
            ]
            return fields.joined(separator: " | ")
        }
        return (["Keyboard glass \(overhang) pt above the keyboard XCUITest reports. Times are from Enter or Return."]
                + lines).joined(separator: "\n")
    }

    /// Fails once, listing everything `hidden` names, if it names anything.
    func fail(_ hidden: [String], _ when: String, file: StaticString = #filePath, line: UInt = #line) {
        guard !hidden.isEmpty else {
            return
        }
        XCTFail("\(when): not entirely in view: \(unique(hidden).joined(separator: "; ")).", file: file, line: line)
    }

    func verdict(_ hidden: [String]) -> String {
        hidden.isEmpty ? "in view" : "hidden " + unique(hidden).joined(separator: " / ")
    }

    func unique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }

    func seconds(_ time: TimeInterval) -> String {
        String(format: "%.2f s", time)
    }
}

extension MathsQuestUITestCase.QuestionParts {
    /// The message after Enter, if one shows.
    var message: MathsQuestUITestCase.QuestionPart? {
        words.first { MathsQuestUITestCase.feedbackMessages.contains($0.label) }
    }

    var skip: CGRect? { controls.first { $0.label == "Skip Question" }?.frame }

    var keyboardUp: Bool { !keyboard.isNull }
}

/// Two wrong answers, and a right one, on the questions most likely to be crowded, at the usual text size.
final class Stage9BInteractionUITests: Stage9BInteractionChecks {
    @MainActor
    func testCountingWrongAnswers() throws {
        try checkWrongAnswers("Counting", on: "Counting", inYear: 1, typing: .nextCountingNumber)
    }

    @MainActor
    func testReadingTheClockWrongAnswers() throws {
        try checkWrongAnswers("Reading the clock", on: "Time", inYear: 3,
                              startingWith: "What time is shown on this clock?", typing: .number)
    }

    @MainActor
    func testConvertingMinutesToHoursWrongAnswers() throws {
        try checkWrongAnswers("Minutes to hours", on: "Time", inYear: 3, startingWith: "Convert ",
                              endingWith: "into hours and minutes.", typing: .number)
    }

    @MainActor
    func testPerimeterWrongAnswers() throws {
        try checkWrongAnswers("Perimeter", on: "Geometry", inYear: 4, startingWith: "Find the perimeter", typing: .number)
    }

    @MainActor
    func testAreaWrongAnswers() throws {
        try checkWrongAnswers("Area", on: "Geometry", inYear: 4, startingWith: "Calculate the area", typing: .number)
    }

    @MainActor
    func testNamingAnAngleWrongAnswers() throws {
        try checkWrongAnswers("Naming an angle", on: "Geometry", inYear: 4,
                              startingWith: "Is this angle: Acute, Right or Obtuse?", typing: .word)
    }

    @MainActor
    func testHighestBarWrongAnswers() throws {
        try checkWrongAnswers("Highest bar", on: "Statistics", inYear: 5,
                              startingWith: "Which category has the highest value?", typing: .word)
    }

    @MainActor
    func testCubeOrCuboidWrongAnswers() throws {
        try checkWrongAnswers("Cube or cuboid", on: "Volume", inYear: 5, startingWith: "What is the volume of this",
                              typing: .number)
    }

    @MainActor
    func testRulerWrongAnswers() throws {
        try checkWrongAnswers("Ruler", on: "Measurement", inYear: 3, startingWith: "Measure the object below:",
                              typing: .number)
    }

    @MainActor
    func testProbabilityWrongAnswers() throws {
        try checkWrongAnswers("Probability", on: "Probability", inYear: 6, typing: .fraction)
    }

    @MainActor
    func testCountingRightAnswerAndTheNextQuestion() throws {
        try checkRightAnswer()
    }
}

/// The same at the largest accessibility text size, on four of the questions.
final class Stage9BInteractionLargeTextUITests: Stage9BInteractionChecks {
    override func setUpWithError() throws {
        try super.setUpWithError()
        extraLaunchArguments = BlankAnswerAndLargeTextUITests.largestText
    }

    @MainActor
    func testCountingWrongAnswers() throws {
        try checkWrongAnswers("Counting", on: "Counting", inYear: 1, typing: .nextCountingNumber)
    }

    @MainActor
    func testConvertingMinutesToHoursWrongAnswers() throws {
        try checkWrongAnswers("Minutes to hours", on: "Time", inYear: 3, startingWith: "Convert ",
                              endingWith: "into hours and minutes.", typing: .number)
    }

    @MainActor
    func testPerimeterWrongAnswers() throws {
        try checkWrongAnswers("Perimeter", on: "Geometry", inYear: 4, startingWith: "Find the perimeter", typing: .number)
    }

    @MainActor
    func testProbabilityWrongAnswers() throws {
        try checkWrongAnswers("Probability", on: "Probability", inYear: 6, typing: .fraction)
    }
}

/// The same at the first accessibility text size, on the two questions that didn't fit above the keyboard at the
/// largest.
final class Stage9BInteractionMediumAccessibilityTextUITests: Stage9BInteractionChecks {
    override func setUpWithError() throws {
        try super.setUpWithError()
        extraLaunchArguments = Self.mediumAccessibilityText
    }

    @MainActor
    func testCountingWrongAnswers() throws {
        try checkWrongAnswers("Counting", on: "Counting", inYear: 1, typing: .nextCountingNumber)
    }

    @MainActor
    func testProbabilityWrongAnswers() throws {
        try checkWrongAnswers("Probability", on: "Probability", inYear: 6, typing: .fraction)
    }
}
