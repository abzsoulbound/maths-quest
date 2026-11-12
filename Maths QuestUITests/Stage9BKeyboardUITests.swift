//
//  Stage9BKeyboardUITests.swift
//  Maths QuestUITests
//

import CoreML
import UIKit
import Vision
import XCTest

/// Stage 9B, D9: with the keyboard up, the question stays in view, along with the answer boxes, the rest of the
/// answer row (units and unit wheels) and Enter. Run on an iPhone SE, an iPhone 17 Pro, an iPhone 17 Pro Max and an
/// iPad, at the usual text size here, at the largest accessibility size in Stage9BKeyboardLargeTextUITests, and at
/// the first accessibility size and the largest usual size on the questions most likely to overflow.
///
/// For each question:
/// 1. With the keyboard down, the question's parts are read from one snapshot: its words (every line of text above
///    the answer boxes), its pictures (the clock, ruler, shape, angle, chart or solid), the answer boxes, the rest
///    of the answer row and Enter.
/// 2. Typing "1" in the first answer box brings the keyboard up.
/// 3. Every word and every picture of the question must still be entirely in view, between the header and the
///    keyboard's glass, and so must the answer boxes, the rest of the answer row and Enter. A picture partly under
///    the keyboard or the header fails, however little of it is hidden. Pictures must keep their size, except the
///    clock to read: while the player types it can be drawn smaller beside its instructions, but never less than 150
///    points across, where its numbers can still be 15 points tall.
/// 4. Tapping the background puts the keyboard away. The question is checked again, and every picture must be back
///    at its size.
///
/// Every screenshot is also read with the same text recognition Live Text uses, and a word or button entirely in view
/// that the screen shows cut short with "…" fails, at every text size. XCUITest reports a label's whole text even when
/// it's drawn cut short, which is how "Answer in 12-hour HH:MM format." came to be cut short unnoticed.
///
/// The working-out pad isn't part of the question: it's for the player's own working and can go under the keyboard.
///
/// At the accessibility text sizes on an iPhone, a question can be taller than the room above the keyboard, and
/// scrolling is the accommodation rather than smaller text or pictures. There the requirement is explicit instead:
/// - With the keyboard down, the question's words must be in view; the test then scrolls down to the answer box
///   before typing, as a player would.
/// - With the keyboard up, the answer boxes, the rest of the answer row and Enter must be in view and tappable, and
///   pictures keep their size, exactly as at the usual size.
/// - Every word and picture of the question that isn't in view must come entirely into view, and readable, not cut
///   short, when the question is dragged down with the keyboard staying up, one part at a time ("reach").
/// - Dragging doesn't take the keyboard down, move the cursor out of the answer box or change what's typed, and
///   dragging back up brings the answer boxes, Enter and Skip back into view, where typing carries on.
/// The same requirement holds, while the keyboard is up only, at the largest usual text size on an iPhone as small
/// as the SE (under 700 points tall). There the clock to read, already at its smallest beside its instructions, is
/// too tall to fit above the keyboard unless it or its words are drawn smaller than they can be read. With the
/// keyboard down and put away, everything must still be in view there, as at the usual size.
/// What wasn't in view is still listed ("hidden" in the D9 line). On an iPad everything must fit at every size.
///
/// Each check prints a line starting "D9|" with the device, text size, activity, keyboard and what was in view, so
/// the run's log gives the table for the Stage 9B report. A check made while a test ad covers the screen fails.
class Stage9BKeyboardUITests: Stage9BKeyboardChecks {

    // MARK: Every activity

    @MainActor func testCountingKeepsTheQuestionInView() throws { try checkQuestionStaysInView(on: "Counting", inYear: 1) }
    @MainActor func testAdditionKeepsTheQuestionInView() throws { try checkQuestionStaysInView(on: "Addition", inYear: 1) }
    @MainActor func testSubtractionKeepsTheQuestionInView() throws { try checkQuestionStaysInView(on: "Subtraction", inYear: 1) }
    @MainActor func testMultiplicationKeepsTheQuestionInView() throws { try checkQuestionStaysInView(on: "Multiplication", inYear: 2) }
    @MainActor func testDivisionKeepsTheQuestionInView() throws { try checkQuestionStaysInView(on: "Division", inYear: 2) }
    @MainActor func testShapesKeepsTheQuestionInView() throws { try checkQuestionStaysInView(on: "Shapes", inYear: 2) }
    @MainActor func testFractionsKeepsTheQuestionInView() throws { try checkQuestionStaysInView(on: "Fractions", inYear: 3) }
    @MainActor func testMeasurementKeepsTheQuestionInView() throws { try checkQuestionStaysInView(on: "Measurement", inYear: 3) }
    @MainActor func testTimeKeepsTheQuestionInView() throws { try checkQuestionStaysInView(on: "Time", inYear: 3) }
    @MainActor func testDecimalsKeepsTheQuestionInView() throws { try checkQuestionStaysInView(on: "Decimals", inYear: 4) }
    @MainActor func testGeometryKeepsTheQuestionInView() throws { try checkQuestionStaysInView(on: "Geometry", inYear: 4) }
    @MainActor func testMoneyKeepsTheQuestionInView() throws { try checkQuestionStaysInView(on: "Money", inYear: 4) }
    @MainActor func testPercentagesKeepsTheQuestionInView() throws { try checkQuestionStaysInView(on: "Percentages", inYear: 5) }
    @MainActor func testStatisticsKeepsTheQuestionInView() throws { try checkQuestionStaysInView(on: "Statistics", inYear: 5) }
    @MainActor func testVolumeKeepsTheQuestionInView() throws { try checkQuestionStaysInView(on: "Volume", inYear: 5) }
    @MainActor func testAlgebraKeepsTheQuestionInView() throws { try checkQuestionStaysInView(on: "Algebra", inYear: 6) }
    @MainActor func testProbabilityKeepsTheQuestionInView() throws { try checkQuestionStaysInView(on: "Probability", inYear: 6) }
    @MainActor func testRatiosKeepsTheQuestionInView() throws { try checkQuestionStaysInView(on: "Ratios", inYear: 6) }

    // MARK: The tallest questions, which the activity tests might not come across

    @MainActor
    func testReadingTheClockKeepsTheQuestionInView() throws {
        try checkQuestionStaysInView(on: "Time", inYear: 3, startingWith: "What time is shown on this clock?")
    }

    @MainActor
    func testCubeOrCuboidKeepsTheQuestionInView() throws {
        try checkQuestionStaysInView(on: "Volume", inYear: 5, startingWith: "What is the volume of this")
    }

    @MainActor
    func testComparingGlassesKeepsTheQuestionInView() throws {
        try checkQuestionStaysInView(on: "Volume", inYear: 5, startingWith: "Glass A has")
    }

    @MainActor
    func testHighestBarKeepsTheQuestionInView() throws {
        try checkQuestionStaysInView(on: "Statistics", inYear: 5, startingWith: "Which category has the highest value?")
    }

    @MainActor
    func testMeasuringWithTheRulerKeepsTheQuestionInView() throws {
        try checkQuestionStaysInView(on: "Measurement", inYear: 3, startingWith: "Measure the object below:")
    }

    @MainActor
    func testNamingAnAngleKeepsTheQuestionInView() throws {
        try checkQuestionStaysInView(on: "Geometry", inYear: 4, startingWith: "Is this angle: Acute, Right or Obtuse?")
    }

    @MainActor
    func testNamingAShapeKeepsTheQuestionInView() throws {
        try checkQuestionStaysInView(on: "Shapes", inYear: 2, startingWith: "What is this shape called?")
    }

    /// The mean and the mode, which have the working-out pad where the bar chart question has its chart.
    @MainActor
    func testStatisticsWithTheWorkingOutPadKeepsTheQuestionInView() throws {
        try checkQuestionStaysInView(on: "Statistics", inYear: 5, startingWith: "Find the ")
    }

    /// The time question with two answer boxes, hours and minutes.
    @MainActor
    func testConvertingMinutesToHoursKeepsTheQuestionInView() throws {
        try checkQuestionStaysInView(
            on: "Time", inYear: 3, startingWith: "Convert ", endingWith: "into hours and minutes."
        )
    }

    /// The time question with one answer box, minutes: about 1 Time question in 6.
    @MainActor
    func testConvertingToMinutesKeepsTheQuestionInView() throws {
        try checkQuestionStaysInView(on: "Time", inYear: 3, startingWith: "Convert ", endingWith: " into minutes")
    }

    /// The time question with the most words: the question, then a line saying how to answer it.
    @MainActor
    func testTimeAfterKeepsTheQuestionInView() throws {
        try checkQuestionStaysInView(on: "Time", inYear: 3, startingWith: "What is the time ")
    }

    /// The perimeter question: a shape, and the unit wheel beside the answer box.
    @MainActor
    func testPerimeterKeepsTheQuestionInView() throws {
        try checkQuestionStaysInView(on: "Geometry", inYear: 4, startingWith: "Find the perimeter of the shape below")
    }

    /// The area question, which only rectangles have: about 1 Geometry question in 9.
    @MainActor
    func testAreaKeepsTheQuestionInView() throws {
        try checkQuestionStaysInView(on: "Geometry", inYear: 4, startingWith: "Calculate the area of the shape below")
    }

    /// The die question, the longest Probability question.
    @MainActor
    func testRollingADieKeepsTheQuestionInView() throws {
        try checkQuestionStaysInView(on: "Probability", inYear: 6, startingWith: "A fair die has")
    }
}

/// The same at the largest accessibility text size, one question an activity.
final class Stage9BKeyboardLargeTextUITests: Stage9BKeyboardUITests {
    override var questionsPerActivity: Int { 1 }

    override func setUpWithError() throws {
        try super.setUpWithError()
        extraLaunchArguments = BlankAnswerAndLargeTextUITests.largestText
    }
}

/// The first accessibility text size, between the usual sizes and the largest: the questions that were too tall at the
/// largest, and the others with a picture.
final class Stage9BKeyboardMediumAccessibilityTextUITests: Stage9BKeyboardChecks {
    override var questionsPerActivity: Int { 1 }

    override func setUpWithError() throws {
        try super.setUpWithError()
        extraLaunchArguments = Self.mediumAccessibilityText
    }

    @MainActor func testCountingKeepsTheQuestionInView() throws { try checkQuestionStaysInView(on: "Counting", inYear: 1) }
    @MainActor func testProbabilityKeepsTheQuestionInView() throws { try checkQuestionStaysInView(on: "Probability", inYear: 6) }

    @MainActor
    func testReadingTheClockKeepsTheQuestionInView() throws {
        try checkQuestionStaysInView(on: "Time", inYear: 3, startingWith: "What time is shown on this clock?")
    }

    @MainActor
    func testTimeAfterKeepsTheQuestionInView() throws {
        try checkQuestionStaysInView(on: "Time", inYear: 3, startingWith: "What is the time ")
    }

    @MainActor
    func testRollingADieKeepsTheQuestionInView() throws {
        try checkQuestionStaysInView(on: "Probability", inYear: 6, startingWith: "A fair die has")
    }

    @MainActor
    func testMeasuringWithTheRulerKeepsTheQuestionInView() throws {
        try checkQuestionStaysInView(on: "Measurement", inYear: 3, startingWith: "Measure the object below:")
    }

    @MainActor
    func testComparingGlassesKeepsTheQuestionInView() throws {
        try checkQuestionStaysInView(on: "Volume", inYear: 5, startingWith: "Glass A has")
    }

    @MainActor
    func testCubeOrCuboidKeepsTheQuestionInView() throws {
        try checkQuestionStaysInView(on: "Volume", inYear: 5, startingWith: "What is the volume of this")
    }

    @MainActor
    func testHighestBarKeepsTheQuestionInView() throws {
        try checkQuestionStaysInView(on: "Statistics", inYear: 5, startingWith: "Which category has the highest value?")
    }

    @MainActor
    func testNamingAnAngleKeepsTheQuestionInView() throws {
        try checkQuestionStaysInView(on: "Geometry", inYear: 4, startingWith: "Is this angle: Acute, Right or Obtuse?")
    }
}

/// The largest of the usual text sizes, which aren't accessibility sizes, so the question must fit above the keyboard
/// as at the standard size: the clock beside its instructions, and the numbers to count. The exception is an iPhone as
/// small as the SE, where the question may scroll while the keyboard is up, if every part of it can be reached as at
/// the accessibility sizes (see `Stage9BKeyboardUITests`).
final class Stage9BKeyboardLargestUsualTextUITests: Stage9BKeyboardChecks {
    override var questionsPerActivity: Int { 1 }

    override func setUpWithError() throws {
        try super.setUpWithError()
        extraLaunchArguments = Self.largestUsualText
    }

    @MainActor func testCountingKeepsTheQuestionInView() throws { try checkQuestionStaysInView(on: "Counting", inYear: 1) }

    @MainActor
    func testReadingTheClockKeepsTheQuestionInView() throws {
        try checkQuestionStaysInView(on: "Time", inYear: 3, startingWith: "What time is shown on this clock?")
    }
}

/// The checks the Stage 9B keyboard tests share. See `Stage9BKeyboardUITests`.
class Stage9BKeyboardChecks: MathsQuestUITestCase {

    /// How many different questions each activity test checks.
    var questionsPerActivity: Int { 2 }

    /// What VoiceOver calls the clock to read.
    static let clockLabel = "Clock"
    /// The least the clock to read may be across while the player types. Its numbers are at most a tenth of its width,
    /// so 15 points at this size, as big as the usual text size makes them.
    static let smallestClock: CGFloat = 150

    // MARK: - Checking

    /// Opens `activity` until it shows a question with an answer box (and, given `question`, one starting with it and
    /// ending with `ending`), and checks it. Without `question`, checks `questionsPerActivity` questions. Throws
    /// XCTSkip if the keyboard never comes up, and fails if no answer box or wanted question does.
    @MainActor
    func checkQuestionStaysInView(
        on activity: String, inYear year: Int, startingWith question: String? = nil, endingWith ending: String? = nil
    ) throws {
        continueAfterFailure = true
        let wanted = question == nil ? questionsPerActivity : 1
        let attempts = question == nil ? 12 : 45
        let retryForLetters = UIDevice.current.userInterfaceIdiom == .pad
            && LayoutUITests.letterKeyboardOnSomeQuestions.contains(activity)
        var checked = 0
        var sawQuestion = question == nil
        var sawAnswerBox = false
        var keyboardFailed = false
        var launchedAt = Date()
        launchApp()
        for _ in 1...attempts {
            // The interstitial can come up at a menu about three minutes after launch, and one question takes up to
            // a minute to check, so start afresh well before then.
            if Date().timeIntervalSince(launchedAt) > 100 {
                launchApp()
                launchedAt = Date()
            }
            openYear(year)
            openActivity(activity)
            var isWanted = true
            if let question {
                let wantedLabel = ending.map {
                    NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@", question, $0)
                } ?? NSPredicate(format: "label BEGINSWITH %@", question)
                isWanted = app.staticTexts.matching(wantedLabel).firstMatch.waitForExistence(timeout: 2)
                sawQuestion = sawQuestion || isWanted
            }
            if isWanted && answerField.waitForExistence(timeout: 2) {
                sawAnswerBox = true
                if checkOneQuestion(on: activity, number: checked + 1) {
                    checked += 1
                    if checked == wanted {
                        return
                    }
                } else {
                    keyboardFailed = true
                    guard retryForLetters else {
                        break
                    }
                }
            }
            goHome()
        }
        if !sawQuestion {
            let end = ending.map { " and end \"\($0)\"" } ?? ""
            XCTFail("\(attempts) \(activity) questions in a row didn't start \"\(question ?? "")\"\(end).")
        } else if !sawAnswerBox {
            XCTFail("\(attempts) \(activity) questions in a row had no answer box.")
        } else if checked == 0 && keyboardFailed {
            throw XCTSkip(LayoutUITests.noKeyboard(on: activity))
        } else {
            XCTFail("Only \(checked) of \(wanted) \(activity) questions could be checked in \(attempts) tries.")
        }
    }

    /// Checks the question on screen with the keyboard down, up and put away again, and prints its "D9|" line.
    /// Returns false if the keyboard doesn't come up.
    @MainActor
    func checkOneQuestion(on activity: String, number: Int) -> Bool {
        let name = "\(activity) \(number)"
        let accessibilityText = usesAccessibilityText
        // See the explicit requirement in `Stage9BKeyboardUITests`. An iPad has room for everything at every size.
        let scrollingAllowed = UIDevice.current.userInterfaceIdiom != .pad
            && (accessibilityText || (textSizeName == "XXXL" && isSmallIPhone))
        let adWarning = "\(name): a test ad covered the screen, so this check doesn't count."
        var ocr = ReadingTally()

        // 1. The keyboard down.
        XCTAssertFalse(text("Test mode").exists, adWarning)
        _ = waitForFrameToSettle(of: anyEnterButton, timeout: 3, steadyFor: 0.3)
        let down = questionParts()
        let downArea = visibleArea(of: down)
        let downFrames = describe(down, in: downArea)
        screenshotAndCheckTheText("\(name): keyboard down", down, in: downArea, tally: &ocr)
        let words = down.questionWords
        XCTAssertFalse(words.isEmpty, "\(name): no question was found above the answer boxes.")
        for word in words where !isInView(word.frame, downArea) {
            XCTFail("\(name), keyboard down: \(word.name) at \(word.frame) isn't entirely in view in \(downArea).")
        }
        if !accessibilityText {
            for picture in down.questionPictures where !isInView(picture.frame, downArea) {
                XCTFail("\(name), keyboard down: the picture \(picture.name) at \(picture.frame) isn't entirely in view in \(downArea).")
            }
        }
        let enterInViewDown = down.enter.map { isInView($0, downArea) } ?? false
        if !accessibilityText {
            assertAnswerAndEnterInView("\(name), keyboard down")
        } else {
            // At an accessibility size a question can be taller than the screen, with its answer boxes below the
            // bottom edge (the clock to read on an iPhone SE), so a player scrolls down to them before typing.
            // Everything checked above has been read already, and with the keyboard up the screen scrolls to the
            // answer anyway.
            scrollAnswerFieldIntoView()
        }

        // 2. The keyboard up.
        guard showKeyboard(typing: "1", into: answerField) else {
            return false
        }
        _ = waitForFrameToSettle(of: anyEnterButton, timeout: 3, steadyFor: 0.3)
        XCTAssertFalse(text("Test mode").exists, adWarning)
        let up = questionParts()
        let upArea = visibleArea(of: up)
        let upFrames = describe(up, in: upArea)
        let keyboardKind = UIDevice.current.userInterfaceIdiom == .pad
            ? "iPad keyboard"
            : (keyboardHasLetters ? "letters" : "number pad")
        let shownUp = up.byKey

        var wordsInView = 0
        var hidden: [String] = []
        // What isn't in view, as it was with the keyboard down, for checking it can be scrolled to.
        var hiddenParts: [QuestionPart] = []
        var topOfWords = CGFloat.infinity
        for word in words {
            guard let shown = shownUp[word.key] else {
                // A grid drops what's far off screen from what XCUITest sees, as the numbers to count can be.
                if !scrollingAllowed {
                    XCTFail("\(name), keyboard up: \(word.name) has gone.")
                }
                hidden.append(word.shortLabel)
                hiddenParts.append(word)
                continue
            }
            topOfWords = min(topOfWords, shown.frame.minY)
            if isInView(shown.frame, upArea) {
                wordsInView += 1
            } else {
                if !scrollingAllowed {
                    XCTFail("\(name), keyboard up: \(word.name) at \(shown.frame) isn't entirely in view in \(upArea).")
                }
                hidden.append(word.shortLabel)
                hiddenParts.append(word)
            }
        }

        var pictureNotes: [String] = []
        for picture in down.questionPictures {
            guard let shown = shownUp[picture.key] else {
                XCTFail("\(name), keyboard up: the picture \(picture.name) has gone.")
                hidden.append("picture \(picture.shortLabel)")
                hiddenParts.append(picture)
                pictureNotes.append("\(picture.label.prefix(20))=gone")
                continue
            }
            var note = "\(picture.label.prefix(20))=\(percentInView(shown.frame, upArea))%"
            if picture.label == Self.clockLabel {
                // The clock to read can be drawn smaller beside its instructions while the player types, but stays
                // round, no bigger than it was and big enough to read.
                XCTAssertGreaterThanOrEqual(shown.frame.width, Self.smallestClock - 0.5,
                                            "\(name): the clock is too small to read with the keyboard up.")
                XCTAssertLessThanOrEqual(shown.frame.width, picture.frame.width + 1,
                                         "\(name): the clock grew when the keyboard came up.")
                XCTAssertEqual(shown.frame.height, shown.frame.width, accuracy: 1,
                               "\(name): the clock isn't round with the keyboard up.")
                if abs(shown.frame.width - picture.frame.width) > 1 {
                    note += " \(Int(picture.frame.width.rounded()))>\(Int(shown.frame.width.rounded()))pt"
                }
            } else {
                XCTAssertEqual(shown.frame.width, picture.frame.width, accuracy: 1,
                               "\(name): the keyboard changed the width of the picture \(picture.name).")
                XCTAssertEqual(shown.frame.height, picture.frame.height, accuracy: 1,
                               "\(name): the keyboard changed the height of the picture \(picture.name).")
            }
            if !isInView(shown.frame, upArea) {
                if !scrollingAllowed {
                    XCTFail("\(name), keyboard up: the picture \(picture.name) at \(shown.frame) isn't entirely in view in \(upArea); \(percentInView(shown.frame, upArea))% of it is.")
                }
                hidden.append("picture \(picture.shortLabel)")
                hiddenParts.append(picture)
            }
            pictureNotes.append(note)
        }

        var answersInView = !up.answerBoxes.isEmpty && up.answerBoxes.allSatisfy { isInView($0, upArea) }
            && (up.enter.map { isInView($0, upArea) } ?? false)
        for item in down.answerRow {
            guard let shown = shownUp[item.key] else {
                XCTFail("\(name), keyboard up: \(item.name) by the answer has gone.")
                answersInView = false
                continue
            }
            if !isInView(shown.frame, upArea) {
                answersInView = false
                XCTFail("\(name), keyboard up: \(item.name) by the answer, at \(shown.frame), isn't entirely in view in \(upArea).")
            }
        }
        assertAnswerAndEnterInView("\(name), keyboard up")
        screenshotAndCheckTheText("\(name): keyboard up (\(keyboardKind))", up, in: upArea, tally: &ocr)
        // The sizes XCUITest gives: an answer box's is the field inside its margin, and Enter's is inside the margin
        // that's part of what can be tapped, so both can be tapped over a bigger area than this.
        let sizes = "Enter \(Self.size(of: up.enter)), box \(Self.size(of: up.answerBoxes.first))"

        // Where the question may scroll (`scrollingAllowed`), everything not in view must be within reach with the
        // keyboard up, and typing carries on once the player is back at the answer.
        var reach = "n/a"
        if scrollingAllowed && !hiddenParts.isEmpty {
            reach = reachEveryHiddenPart(of: name, hiddenParts, typingInto: answerField, typed: "1", ocr: &ocr)
            if answerField.hasKeyboardFocus {
                answerField.typeText("2")
                let typed = typedText(in: answerField)
                XCTAssertEqual(typed, "12", "\(name), keyboard up: typing after reading the question and coming back to the answer didn't add to what was typed.")
                reach += ", typing \(typed == "12" ? "yes" : "no")"
            }
        }

        // 3. The keyboard put away.
        hideKeyboardByTappingBackground()
        _ = waitForFrameToSettle(of: anyEnterButton, timeout: 3, steadyFor: 0.3)
        let after = questionParts()
        let afterArea = visibleArea(of: after)
        let afterFrames = describe(after, in: afterArea)
        let shownAfter = after.byKey
        var wordsInViewAfter = 0
        for word in words {
            let shown = shownAfter[word.key]
            if let shown, isInView(shown.frame, afterArea) {
                wordsInViewAfter += 1
            } else if !accessibilityText {
                XCTFail("\(name), keyboard put away: \(word.name) at \(shown?.frame ?? .null) isn't entirely in view in \(afterArea).")
            }
        }
        for picture in down.questionPictures {
            guard let shown = shownAfter[picture.key] else {
                XCTFail("\(name), keyboard put away: the picture \(picture.name) has gone.")
                continue
            }
            XCTAssertEqual(shown.frame.width, picture.frame.width, accuracy: 1,
                           "\(name): the picture \(picture.name) didn't get its width back when the keyboard went.")
            XCTAssertEqual(shown.frame.height, picture.frame.height, accuracy: 1,
                           "\(name): the picture \(picture.name) didn't get its height back when the keyboard went.")
            if !accessibilityText && !isInView(shown.frame, afterArea) {
                XCTFail("\(name), keyboard put away: the picture \(picture.name) at \(shown.frame) isn't entirely in view in \(afterArea).")
            }
        }
        if !accessibilityText {
            assertAnswerAndEnterInView("\(name), keyboard put away")
        }
        screenshotAndCheckTheText("\(name): keyboard put away", after, in: afterArea, tally: &ocr)

        let device = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? UIDevice.current.model
        let top = topOfWords.isFinite ? Int((topOfWords - upArea.minY).rounded(.down)) : 0
        let line = [
            "D9", device, textSizeName, activity, String((words.first?.shortLabel ?? "?").prefix(40)),
            keyboardKind,
            "words \(wordsInView)/\(words.count)",
            "top \(top)pt",
            "answer+Enter \(answersInView ? "yes" : "no")",
            "pictures " + (pictureNotes.isEmpty ? "none" : pictureNotes.joined(separator: ", ")),
            "room \(Int(upArea.height))pt",
            "hidden " + (hidden.isEmpty ? "none" : hidden.joined(separator: " / ")),
            "down Enter \(enterInViewDown ? "yes" : "no")",
            "after words \(wordsInViewAfter)/\(words.count)",
            "reach \(reach)",
            sizes,
            ocr.summary,
        ].joined(separator: "|")
        print(line)
        attachText("\(name): D9", [line, "", "Keyboard down", downFrames, "", "Keyboard up", upFrames, "",
                                   "Keyboard put away", afterFrames].joined(separator: "\n"))
        return true
    }

    /// A frame's size in whole points, for the D9 line.
    static func size(of frame: CGRect?) -> String {
        frame.map { "\(Int($0.width.rounded()))x\(Int($0.height.rounded()))" } ?? "none"
    }
}

// MARK: - Reading the screen

/// Reading a question screen, shared by the Stage 9B keyboard and interaction tests.
extension MathsQuestUITestCase {
    /// One thing on a question screen. `key` is its kind and label, numbered when the same label comes up more than
    /// once, which finds it again in a later snapshot.
    struct QuestionPart {
        let key: String
        let label: String
        let frame: CGRect

        var name: String { label.isEmpty ? key : "\"\(label.replacingOccurrences(of: "\n", with: " "))\"" }
        var shortLabel: String { String(label.replacingOccurrences(of: "\n", with: " ").prefix(30)) }
    }

    struct QuestionParts {
        /// The window.
        var window = CGRect.null
        /// The scrolling space below the header.
        var area = CGRect.null
        /// The keyboard as XCUITest reports it, without the glass above it (see `keyboardGlassFrame`), or null if it
        /// isn't on screen.
        var keyboard = CGRect.null
        /// Every line of text, in reading order.
        var words: [QuestionPart] = []
        /// Labelled pictures: the clock, ruler, red bar, shape, angle, chart or solid.
        var pictures: [QuestionPart] = []
        var answerBoxes: [CGRect] = []
        /// Buttons, unit wheels and other controls.
        var controls: [QuestionPart] = []

        var enter: CGRect? { controls.first { $0.label.hasPrefix("Enter") }?.frame }
        var topOfAnswers: CGFloat { answerBoxes.map(\.minY).min() ?? .infinity }
        /// The question: the words and pictures above the answer boxes.
        var questionWords: [QuestionPart] { words.filter { $0.frame.maxY <= topOfAnswers + 1 } }
        var questionPictures: [QuestionPart] { pictures.filter { $0.frame.maxY <= topOfAnswers + 1 } }
        /// The rest of the answer row: units, unit wheels and box labels level with or below the boxes, above Enter.
        var answerRow: [QuestionPart] {
            guard let enter else {
                return []
            }
            return (words + controls).filter {
                !$0.label.hasPrefix("Enter") && $0.label != "Skip Question"
                    && $0.frame.midY >= topOfAnswers && $0.frame.midY < enter.minY
            }
        }
        /// Everything with a key, by key.
        var byKey: [String: QuestionPart] {
            Dictionary(uniqueKeysWithValues: (words + pictures + controls).map { ($0.key, $0) })
        }
    }

    /// Reads the question screen from a single snapshot, so every frame belongs to the same moment.
    @MainActor
    func questionParts() -> QuestionParts {
        var parts = QuestionParts()
        guard let root = try? app.snapshot() else {
            return parts
        }
        // The question area is the biggest scroll view outside the keyboard. The working-out pad is a scroll view
        // too, inside it.
        parts.window = root.children.first { $0.elementType == .window }?.frame ?? root.frame
        var scrollViews: [XCUIElementSnapshot] = []
        func findScrollViews(_ element: XCUIElementSnapshot) {
            guard element.elementType != .keyboard else {
                // Parked below the screen when it isn't up.
                if element.frame.height > 0 && element.frame.minY < parts.window.maxY && parts.keyboard.isNull {
                    parts.keyboard = element.frame
                }
                return
            }
            if element.elementType == .scrollView {
                scrollViews.append(element)
            }
            for child in element.children {
                findScrollViews(child)
            }
        }
        findScrollViews(root)
        guard let questionArea = scrollViews.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
            return parts
        }
        parts.area = questionArea.frame

        var counts: [String: Int] = [:]
        func part(_ kind: String, _ element: XCUIElementSnapshot) -> QuestionPart {
            let label = element.label.trimmingCharacters(in: .whitespacesAndNewlines)
            let base = "\(kind) \(label)"
            let number = counts[base, default: 0] + 1
            counts[base] = number
            return QuestionPart(key: "\(base) #\(number)", label: label, frame: element.frame)
        }
        func containsTextField(_ element: XCUIElementSnapshot) -> Bool {
            element.children.contains { $0.elementType == .textField || containsTextField($0) }
        }
        // UIKit's scroll bar, which XCUITest lists only while it shows (as the question scrolls, and for a moment
        // after), labelled like "Vertical scroll bar, 2 pages" and as tall as the question area. It belongs to the
        // scroll view, not to the question, so it isn't a picture that has to stay in view.
        func isScrollBar(_ element: XCUIElementSnapshot) -> Bool {
            element.label.range(of: "^(Vertical|Horizontal) scroll bar, [0-9]+ pages?$",
                                options: .regularExpression) != nil
        }
        var candidates: [(part: QuestionPart, isImage: Bool)] = []
        func visit(_ element: XCUIElementSnapshot) {
            let label = element.label.trimmingCharacters(in: .whitespacesAndNewlines)
            switch element.elementType {
            case .textField, .secureTextField:
                parts.answerBoxes.append(element.frame)
            case .button, .picker, .pickerWheel, .segmentedControl, .switch, .stepper:
                parts.controls.append(part("control", element))
            case .scrollView:
                break // the working-out pad
            case .other where isScrollBar(element):
                break
            case .staticText:
                if !label.isEmpty {
                    parts.words.append(part("words", element))
                }
            default:
                // A labelled element big enough to see, with no answer box inside, is a picture. XCUITest lists the
                // parts VoiceOver reads as one (a chart's bars, a clock's numbers) inside it, so they aren't taken
                // separately. The red bar to measure is adjustable, which XCUITest calls a slider: a picture here.
                if !label.isEmpty && element.frame.width * element.frame.height >= 300 && !containsTextField(element) {
                    candidates.append((part("picture", element), element.elementType == .image))
                } else {
                    for child in element.children {
                        visit(child)
                    }
                }
            }
        }
        for child in questionArea.children {
            visit(child)
        }
        // A shape's corners and sides are small labelled spots on its outline, and a circle's is the whole circle:
        // parts of the picture, not pictures of their own. Their middles lie on the picture. A circle's spot is exactly
        // the size of the circle, and XCUITest can list the two in either order from one snapshot to the next, so of
        // two the same size, the picture itself (an image) is taken, then the first label, the same one every time.
        let biggestFirst = candidates.sorted { a, b in
            let areaA = (a.part.frame.width * a.part.frame.height).rounded()
            let areaB = (b.part.frame.width * b.part.frame.height).rounded()
            if areaA != areaB {
                return areaA > areaB
            }
            if a.isImage != b.isImage {
                return a.isImage
            }
            return a.part.label < b.part.label
        }
        for candidate in biggestFirst.map(\.part) {
            let middle = CGPoint(x: candidate.frame.midX, y: candidate.frame.midY)
            if !parts.pictures.contains(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(middle) }) {
                parts.pictures.append(candidate)
            }
        }
        parts.pictures.sort { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
        return parts
    }

    /// The part of the question area a player can see: below the header and above the keyboard's glass.
    @MainActor
    func visibleArea(of parts: QuestionParts) -> CGRect {
        guard !parts.area.isNull else {
            return .zero
        }
        var area = parts.area.intersection(windowFrame)
        guard !area.isNull else {
            return .zero
        }
        if keyboardIsOnScreen {
            area.size.height = max(0, min(area.maxY, keyboardGlassFrame.minY) - area.minY)
        }
        return area
    }

    /// The part of the question area a player could see when `parts` was read, with the keyboard's glass starting
    /// `overhang` points above the keyboard XCUITest reports (see `keyboardGlassFrame`). It reads nothing more from the
    /// app, so it's quick enough to call many times while a message shows, and it matches the snapshot even while the
    /// keyboard moves.
    func visibleArea(of parts: QuestionParts, overhang: CGFloat) -> CGRect {
        guard !parts.area.isNull else {
            return .zero
        }
        var area = parts.area.intersection(parts.window.isNull ? parts.area : parts.window)
        guard !area.isNull else {
            return .zero
        }
        if !parts.keyboard.isNull {
            area.size.height = max(0, min(area.maxY, parts.keyboard.minY - overhang) - area.minY)
        }
        return area
    }

    func isInView(_ frame: CGRect, _ area: CGRect) -> Bool {
        !frame.isNull && area.insetBy(dx: -0.5, dy: -0.5).contains(frame)
    }

    func percentInView(_ frame: CGRect, _ area: CGRect) -> Int {
        let whole = frame.width * frame.height
        guard whole > 0 else {
            return 100
        }
        let shown = frame.intersection(area)
        guard !shown.isNull else {
            return 0
        }
        return Int((shown.width * shown.height / whole * 100).rounded(.down))
    }

    // MARK: Scrolling as a player would

    /// Drags the question area along the left edge of the screen, clear of the answer boxes and buttons, from
    /// `startY` to `endY`: slowly, and holding at the end so it doesn't keep scrolling.
    @MainActor
    func dragQuestionArea(fromY startY: CGFloat, toY endY: CGFloat) {
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let x = windowFrame.minX + 2
        origin.withOffset(CGVector(dx: x, dy: startY))
            .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: x, dy: endY)),
                   withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    /// With the keyboard down, scrolls the question up until the answer box the tests type into is in view, as a
    /// player would when it's below the bottom of the screen; a tap there would miss it. Keeps 40 points clear of the
    /// bottom of the screen. Does nothing if the box is in view already.
    @MainActor
    func scrollAnswerFieldIntoView() {
        for _ in 1...4 {
            let area = visibleArea(of: questionParts())
            let box = answerField.frame
            let lowest = min(area.maxY, windowFrame.maxY - 40)
            guard !area.isEmpty, !box.isEmpty, box.maxY > lowest else {
                return
            }
            let startY = min(area.maxY, windowFrame.maxY - 50) - 10
            let shift = min(box.maxY - lowest + 20, startY - area.minY - 10)
            guard shift > 4 else {
                return
            }
            dragQuestionArea(fromY: startY, toY: startY - shift)
            _ = waitForFrameToSettle(of: answerField, timeout: 2, steadyFor: 0.3)
        }
    }

    /// With the keyboard up, drags the question down until the part with `key` is entirely in view, as a player would
    /// to read what doesn't fit above the keyboard. Every drag ends 30 points above the keyboard's glass, so the
    /// keyboard, which follows a drag into it, stays up. Returns whether the part came into view with the keyboard up,
    /// and how many drags it took.
    @MainActor
    func dragDownUntilInView(_ key: String) -> (reached: Bool, drags: Int) {
        var drags = 0
        for attempt in 0...6 {
            let parts = questionParts()
            let area = visibleArea(of: parts)
            guard keyboardIsOnScreen, !area.isEmpty else {
                return (false, drags)
            }
            let shown = parts.byKey[key]
            if let shown, isInView(shown.frame, area) {
                return (true, drags)
            }
            let startY = area.minY + 10
            let endY = keyboardGlassFrame.minY - 30
            guard attempt < 6, endY - startY >= 40 else {
                return (false, drags)
            }
            if let shown, shown.frame.height > area.height + 0.5 {
                // Taller than the room above the keyboard, so it can never be entirely in view.
                return (false, drags)
            }
            if let shown, shown.frame.minY >= area.minY - 0.5 {
                // Below the room above the keyboard, after a drag went too far: back up just enough.
                let needed = shown.frame.maxY - (area.maxY - 10)
                dragQuestionArea(fromY: endY, toY: endY - min(max(needed, 40), endY - startY))
            } else {
                // Far enough to bring the part's top 20 points below the header, or as far as one drag goes. A part
                // that has dropped out of the accessibility tree, as rows of numbers far off screen do, takes a full
                // drag.
                let needed = shown.map { area.minY + 20 - $0.frame.minY } ?? .infinity
                dragQuestionArea(fromY: startY, toY: startY + min(max(needed, 40), endY - startY))
            }
            drags += 1
            _ = waitForFrameToSettle(of: anyEnterButton, timeout: 2, steadyFor: 0.3)
        }
        return (false, drags)
    }

    /// With the keyboard up, drags the question back up until every answer box, Enter and Skip (when it shows) are
    /// entirely in view, as a player would after reading the question. Every drag starts 30 points above the
    /// keyboard's glass. Returns whether they all came into view with the keyboard up.
    @MainActor
    func dragBackToTheAnswerWithTheKeyboardUp() -> Bool {
        for attempt in 0...6 {
            let parts = questionParts()
            let area = visibleArea(of: parts)
            guard keyboardIsOnScreen, !area.isEmpty else {
                return false
            }
            let skip = parts.controls.first { $0.label == "Skip Question" }?.frame
            let targets = parts.answerBoxes + [parts.enter, skip].compactMap { $0 }
            if parts.enter != nil && !parts.answerBoxes.isEmpty && targets.allSatisfy({ isInView($0, area) }) {
                return true
            }
            let glassTop = keyboardGlassFrame.minY
            let startY = glassTop - 30
            let endY = area.minY + 10
            guard attempt < 6, startY - endY >= 40 else {
                return false
            }
            // Far enough to bring the lowest of them 10 points above the glass, or as far as one drag goes.
            let needed = parts.enter == nil ? .infinity : (targets.map(\.maxY).max() ?? glassTop) - (glassTop - 10)
            dragQuestionArea(fromY: startY, toY: startY - min(max(needed, 40), startY - endY))
            _ = waitForFrameToSettle(of: anyEnterButton, timeout: 2, steadyFor: 0.3)
        }
        return false
    }

    /// The explicit requirement at the accessibility sizes on an iPhone (see `Stage9BKeyboardUITests`): with the
    /// keyboard up, drags the question down to each of `hiddenParts` in turn, nearest the answer first, and checks each
    /// comes entirely into view and is read in full; then drags back to the answer. The keyboard must stay up
    /// throughout, with the cursor still in `field` and `typed` still in it. Fails for each part that can't be read,
    /// and returns the note for the "reach" column of the D9 lines.
    @MainActor
    func reachEveryHiddenPart(of name: String, _ hiddenParts: [QuestionPart], typingInto field: XCUIElement,
                              typed: String, ocr: inout ReadingTally,
                              file: StaticString = #filePath, line: UInt = #line) -> String {
        var reached = 0
        var unreachable: [String] = []
        for part in hiddenParts.sorted(by: { $0.frame.minY > $1.frame.minY }) {
            let (inView, drags) = dragDownUntilInView(part.key)
            if inView {
                reached += 1
                if drags > 0 {
                    let parts = questionParts()
                    screenshotAndCheckTheText("\(name): keyboard up, dragged down to \(part.shortLabel)", parts,
                                              in: visibleArea(of: parts), tally: &ocr, file: file, line: line)
                }
            } else {
                let parts = questionParts()
                let area = visibleArea(of: parts)
                let why: String
                if !keyboardIsOnScreen {
                    why = "the keyboard went down"
                } else if let shown = parts.byKey[part.key], shown.frame.height > area.height + 0.5 {
                    why = "it's \(Int(shown.frame.height)) points tall, more than the \(Int(area.height)) above the keyboard"
                } else {
                    why = "dragging the question down \(drags) times didn't bring it entirely into view"
                }
                unreachable.append(part.shortLabel)
                XCTFail("\(name), keyboard up: \(part.name) can't be read with the keyboard up: \(why).",
                        file: file, line: line)
                attachScreenshot("\(name): keyboard up, couldn't reach \(part.shortLabel)")
            }
            if !keyboardIsOnScreen {
                break
            }
        }

        let keyboardStayed = keyboardIsOnScreen
        XCTAssertTrue(keyboardStayed, "\(name): dragging the question to read it took the keyboard down.",
                      file: file, line: line)
        let focusKept = field.hasKeyboardFocus
        XCTAssertTrue(focusKept, "\(name): dragging the question to read it moved the cursor out of the answer box.",
                      file: file, line: line)
        let typedNow = typedText(in: field)
        XCTAssertEqual(typedNow, typed, "\(name): dragging the question to read it changed what was typed.",
                       file: file, line: line)
        var back = false
        if keyboardStayed {
            back = dragBackToTheAnswerWithTheKeyboardUp()
            XCTAssertTrue(back, "\(name): dragging back up didn't bring the answer boxes, Enter and Skip back into view with the keyboard up.",
                          file: file, line: line)
            assertAnswerAndEnterInView("\(name), keyboard up, back at the answer after reading the question",
                                       file: file, line: line)
            let parts = questionParts()
            screenshotAndCheckTheText("\(name): keyboard up, back at the answer", parts, in: visibleArea(of: parts),
                                      tally: &ocr, file: file, line: line)
            XCTAssertTrue(field.hasKeyboardFocus, "\(name): the cursor left the answer box on the way back to it.",
                          file: file, line: line)
        }
        func yesNo(_ value: Bool) -> String { value ? "yes" : "no" }
        var note = "\(reached)/\(hiddenParts.count), kb stayed \(yesNo(keyboardStayed)), focus \(yesNo(focusKept)), "
            + "typed kept \(yesNo(typedNow == typed)), back \(yesNo(back))"
        if !unreachable.isEmpty {
            note += ", unreachable: " + unreachable.joined(separator: " / ")
        }
        return note
    }

    // MARK: Text sizes

    static var mediumAccessibilityText: [String] {
        ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
    }
    static var largestUsualText: [String] { ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"] }

    /// The text size the app is launched with, or nil for the simulator's own, the standard size.
    var launchTextSize: String? {
        guard let index = extraLaunchArguments.firstIndex(of: "-UIPreferredContentSizeCategoryName"),
              extraLaunchArguments.indices.contains(index + 1) else {
            return nil
        }
        return extraLaunchArguments[index + 1]
    }

    /// Whether the app is launched at one of the accessibility text sizes, beyond the usual ones.
    var usesAccessibilityText: Bool { launchTextSize?.contains("Accessibility") ?? false }

    /// Whether this is an iPhone as small as the SE, under 700 points tall. The next smallest iPhones the app runs on
    /// are 812 points tall.
    var isSmallIPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone && app.frame.height < 700 }

    /// The text size, as the D9 lines and the report name it.
    var textSizeName: String {
        switch launchTextSize {
        case nil: return "default"
        case "UICTContentSizeCategoryXXXL": return "XXXL"
        case "UICTContentSizeCategoryAccessibilityM": return "AX1"
        case "UICTContentSizeCategoryAccessibilityL": return "AX2"
        case "UICTContentSizeCategoryAccessibilityXL": return "AX3"
        case "UICTContentSizeCategoryAccessibilityXXL": return "AX4"
        case "UICTContentSizeCategoryAccessibilityXXXL": return "AX XXXL"
        case let other?: return other
        }
    }

    // MARK: Reading the text on screen

    /// A line of text read from a screenshot, and where it is on screen, in points.
    struct ReadLine {
        let text: String
        let frame: CGRect
    }

    struct ScreenReading {
        var lines: [ReadLine] = []
        /// Why nothing could be read, if it couldn't.
        var error: String?
    }

    /// What one check read from its screenshots, for the D9 lines.
    struct ReadingTally {
        var screenshots = 0
        /// How many words and buttons in view were read.
        var read = 0
        var truncated: [String] = []
        /// How many numbers on their own (the Counting tiles) were in view and checked from the pixels, how many of
        /// those text recognition also read back exactly, and the ones not shown in full.
        var numbers = 0
        var numbersReadExactly = 0
        var cutNumbers: [String] = []
        var errors: [String] = []

        var summary: String {
            "ocr \(screenshots) shots, \(read) read, truncated "
                + (truncated.isEmpty ? "none" : truncated.joined(separator: " / "))
                + (numbers == 0 ? "" : ", numbers \(numbers) checked (\(numbersReadExactly) read exactly), cut "
                    + (cutNumbers.isEmpty ? "none" : cutNumbers.joined(separator: " / ")))
                + (errors.first.map { ", unavailable \(errors.count)x: \($0)" } ?? "")
        }
    }

    /// Whether `text` shows the "…" a cut-short line ends with, however text recognition reads it.
    static func hasEllipsis(_ text: String) -> Bool {
        text.contains("…") || text.replacingOccurrences(of: " ", with: "").contains("..")
    }

    /// Takes a screenshot of the whole screen, keyboard and all, attaches it as `name` and reads the text in `area`.
    /// Returns the screenshot too, for the pixels.
    @MainActor
    func screenshotAndRead(_ name: String, in area: CGRect) -> (reading: ScreenReading, image: UIImage) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let image = screenshot.image
        return (read(image, in: area), image)
    }

    /// Reads the text in `area` of a screenshot with Vision's text recognition, the same Live Text uses. On the
    /// simulator the accurate recogniser can fail on its default device, so a failure is tried again on the CPU.
    @MainActor
    func read(_ image: UIImage, in area: CGRect) -> ScreenReading {
        guard let whole = image.cgImage, image.size.width > 0 else {
            return ScreenReading(error: "the screenshot has no pixels")
        }
        let scale = CGFloat(whole.width) / image.size.width
        let crop = CGRect(x: area.minX * scale, y: area.minY * scale, width: area.width * scale,
                          height: area.height * scale).integral
            .intersection(CGRect(x: 0, y: 0, width: whole.width, height: whole.height))
        guard !crop.isNull, crop.width >= 1, crop.height >= 1, let pixels = whole.cropping(to: crop) else {
            return ScreenReading(error: "nothing to read in \(area)")
        }
        func recognise(onTheCPU: Bool) throws -> [VNRecognizedTextObservation] {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US"]
            if onTheCPU, let cpu = try request.supportedComputeStageDevices[.main]?.first(where: {
                if case .cpu = $0 { return true } else { return false }
            }) {
                request.setComputeDevice(cpu, for: .main)
            }
            try VNImageRequestHandler(cgImage: pixels, options: [:]).perform([request])
            return request.results ?? []
        }
        let observations: [VNRecognizedTextObservation]
        do {
            observations = try recognise(onTheCPU: false)
        } catch {
            do {
                observations = try recognise(onTheCPU: true)
            } catch let cpuError {
                return ScreenReading(error: "\(error.localizedDescription); on the CPU: \(cpuError.localizedDescription)")
            }
        }
        let origin = CGPoint(x: crop.minX / scale, y: crop.minY / scale)
        let width = crop.width / scale
        let height = crop.height / scale
        let lines = observations.compactMap { observation -> ReadLine? in
            guard let text = observation.topCandidates(1).first?.string else {
                return nil
            }
            let box = observation.boundingBox
            return ReadLine(text: text, frame: CGRect(x: origin.x + box.minX * width,
                                                      y: origin.y + (1 - box.maxY) * height,
                                                      width: box.width * width, height: box.height * height))
        }
        return ScreenReading(lines: lines)
    }

    /// The words and buttons entirely in view in `area` that the screen shows cut short with "…" where their whole
    /// text has none, and how many were read at all.
    func truncatedText(in parts: QuestionParts, area: CGRect, reading: ScreenReading) -> (read: Int, truncated: [String]) {
        var read = 0
        var truncated: [String] = []
        for part in parts.words + parts.controls where !part.label.isEmpty && isInView(part.frame, area) {
            let box = part.frame.insetBy(dx: -4, dy: -4)
            let shown = reading.lines
                .filter { box.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
                .map(\.text)
                .joined(separator: " ")
            guard !shown.isEmpty else {
                continue
            }
            read += 1
            if Self.hasEllipsis(shown) && !Self.hasEllipsis(part.label) {
                truncated.append("\(part.name) reads \"\(shown)\"")
            }
        }
        return (read, truncated)
    }

    // MARK: Numbers on their own

    /// Whether `label` is a number on its own, as on the Counting tiles. (The ruler, clock and bar chart numbers are
    /// each inside one labelled picture, so they aren't words.)
    static func isANumber(_ label: String) -> Bool {
        !label.isEmpty && label.allSatisfy { ("0"..."9").contains($0) }
    }

    /// What's drawn inside a frame of a screenshot.
    struct DrawnMarks {
        /// Whether anything stands out from the background at all.
        var inked = false
        /// Separate marks: groups of touching ink pixels.
        var marks = 0
        /// Whether three small marks sit side by side on one line, as "…" is drawn.
        var ellipsis = false
    }

    /// Looks at the pixels of `frame` (in points) in `screenshot`, which is `pointsWide` points wide, for the "…" a
    /// line cut short ends with. Text recognition can't be relied on for this: it reads a "…" drawn on its own as
    /// nothing at all, and sometimes reads a digit on its own as nothing too. An ellipsis is three small marks side by
    /// side; no digit has a separate small mark (a digit is about 60% of the line's height), so three small marks on
    /// one line inside a number's frame mean the number was cut short.
    static func marks(in frame: CGRect, of screenshot: CGImage, pointsWide: CGFloat) -> DrawnMarks {
        guard pointsWide > 0, !frame.isNull, frame.width > 0, frame.height > 0 else {
            return DrawnMarks()
        }
        let scale = CGFloat(screenshot.width) / pointsWide
        // A little room round the frame, so nothing drawn in it is sliced by the edge.
        let margin: CGFloat = 2
        let box = CGRect(x: (frame.minX - margin) * scale, y: (frame.minY - margin) * scale,
                         width: (frame.width + 2 * margin) * scale, height: (frame.height + 2 * margin) * scale)
            .integral
            .intersection(CGRect(x: 0, y: 0, width: screenshot.width, height: screenshot.height))
        guard !box.isNull, box.width > 2, box.height > 2, let part = screenshot.cropping(to: box) else {
            return DrawnMarks()
        }
        let width = part.width
        let height = part.height
        // The pixels as 8-bit sRGB, whatever the screenshot's own format.
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return false
            }
            context.draw(part, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else {
            return DrawnMarks()
        }
        func colour(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let index = (y * width + x) * 4
            return (Int(rgba[index]), Int(rgba[index + 1]), Int(rgba[index + 2]))
        }
        // The background is the commonest colour round the edge.
        var edgeCounts: [Int: Int] = [:]
        var edgeColours: [Int: (Int, Int, Int)] = [:]
        func countEdge(_ x: Int, _ y: Int) {
            let pixel = colour(x, y)
            let key = (pixel.0 / 8) << 10 | (pixel.1 / 8) << 5 | (pixel.2 / 8)
            edgeCounts[key, default: 0] += 1
            edgeColours[key] = pixel
        }
        for x in 0..<width {
            countEdge(x, 0)
            countEdge(x, height - 1)
        }
        for y in 0..<height {
            countEdge(0, y)
            countEdge(width - 1, y)
        }
        guard let backgroundKey = edgeCounts.max(by: { $0.value < $1.value })?.key,
              let background = edgeColours[backgroundKey] else {
            return DrawnMarks()
        }
        var difference = [Int](repeating: 0, count: width * height)
        var strongest = 0
        for y in 0..<height {
            for x in 0..<width {
                let pixel = colour(x, y)
                let value = max(abs(pixel.0 - background.0), abs(pixel.1 - background.1), abs(pixel.2 - background.2))
                difference[y * width + x] = value
                strongest = max(strongest, value)
            }
        }
        guard strongest >= 64 else {
            return DrawnMarks()
        }
        // Ink: at least half as different from the background as the most different pixel.
        let ink = difference.map { $0 * 2 >= strongest }
        struct Mark {
            var minX: Int, maxX: Int, minY: Int, maxY: Int, pixels: Int
        }
        var marks: [Mark] = []
        var seen = [Bool](repeating: false, count: width * height)
        for start in ink.indices where ink[start] && !seen[start] {
            var stack = [start]
            seen[start] = true
            var mark = Mark(minX: width, maxX: 0, minY: height, maxY: 0, pixels: 0)
            while let index = stack.popLast() {
                let x = index % width
                let y = index / width
                mark.minX = min(mark.minX, x)
                mark.maxX = max(mark.maxX, x)
                mark.minY = min(mark.minY, y)
                mark.maxY = max(mark.maxY, y)
                mark.pixels += 1
                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let nx = x + dx
                        let ny = y + dy
                        guard nx >= 0, ny >= 0, nx < width, ny < height else {
                            continue
                        }
                        let next = ny * width + nx
                        if ink[next] && !seen[next] {
                            seen[next] = true
                            stack.append(next)
                        }
                    }
                }
            }
            marks.append(mark)
        }
        // Small: no more than a quarter of the line's height either way. Specks of a pixel or two, and anything
        // touching the edge (part of something sliced by it), are left out.
        let lineHeight = Double(frame.height * scale)
        let small = marks.filter { mark in
            let touchesTheEdge = mark.minX == 0 || mark.minY == 0 || mark.maxX == width - 1 || mark.maxY == height - 1
            return Double(mark.maxX - mark.minX + 1) <= lineHeight / 4
                && Double(mark.maxY - mark.minY + 1) <= lineHeight / 4
                && mark.pixels >= 3 && !touchesTheEdge
        }
        let ellipsis = small.contains { mark in
            let middle = Double(mark.minY + mark.maxY) / 2
            return small.filter { abs(Double($0.minY + $0.maxY) / 2 - middle) <= lineHeight / 10 }.count >= 3
        }
        return DrawnMarks(inked: true, marks: marks.count, ellipsis: ellipsis)
    }

    /// Every number on its own entirely in view in `area` that the screenshot doesn't show in full: drawn with "…"
    /// or not drawn at all, judged from the pixels. How many were checked, and how many text recognition also read
    /// back exactly (it can't always read a digit on its own, so that's only noted). `unchecked` says why numbers in
    /// view couldn't be checked, if they couldn't.
    func numbersCutShort(in parts: QuestionParts, area: CGRect, screenshot: UIImage, reading: ScreenReading)
        -> (checked: Int, readExactly: Int, cut: [String], unchecked: String?) {
        let numbers = parts.words.filter { Self.isANumber($0.label) && isInView($0.frame, area) }
        guard !numbers.isEmpty else {
            return (0, 0, [], nil)
        }
        guard let pixels = screenshot.cgImage, screenshot.size.width > 0 else {
            return (0, 0, [], "\(numbers.count) numbers in view not checked: the screenshot has no pixels")
        }
        var readExactly = 0
        var cut: [String] = []
        for part in numbers {
            let box = part.frame.insetBy(dx: -4, dy: -4)
            let shown = reading.lines
                .filter { box.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
                .map(\.text)
                .joined(separator: " ")
            if shown == part.label {
                readExactly += 1
            }
            let drawn = Self.marks(in: part.frame, of: pixels, pointsWide: screenshot.size.width)
            if !drawn.inked {
                cut.append("\(part.name) isn't drawn")
            } else if drawn.ellipsis {
                cut.append("\(part.name) is drawn with \"…\"" + (shown.isEmpty ? "" : ", read as \"\(shown)\""))
            }
        }
        return (numbers.count, readExactly, cut, nil)
    }

    /// Takes a screenshot, attaches it as `name` and fails for every word or button in view in `area` that it shows
    /// cut short, at every text size. Numbers on their own are checked from the pixels as well (see
    /// `marks(in:of:pointsWide:)`), so a number drawn as "…" fails even where text recognition reads nothing. If the
    /// text can't be read, that's noted in `tally` and attached, without failing, and the screenshot is read afterwards
    /// on the Mac instead; the pixel check of the numbers doesn't need it.
    @MainActor
    func screenshotAndCheckTheText(_ name: String, _ parts: QuestionParts, in area: CGRect, tally: inout ReadingTally,
                                   file: StaticString = #filePath, line: UInt = #line) {
        let (reading, image) = screenshotAndRead(name, in: area)
        tally.screenshots += 1
        let numbers = numbersCutShort(in: parts, area: area, screenshot: image, reading: reading)
        tally.numbers += numbers.checked
        tally.numbersReadExactly += numbers.readExactly
        for cut in numbers.cut {
            if !tally.cutNumbers.contains(cut) {
                tally.cutNumbers.append(cut)
            }
            XCTFail("\(name): NUMBER NOT SHOWN IN FULL: \(cut).", file: file, line: line)
        }
        if let unchecked = numbers.unchecked {
            tally.errors.append(unchecked)
            XCTFail("UNVERIFIED: \(name): \(unchecked).", file: file, line: line)
        }
        if let error = reading.error {
            tally.errors.append(error)
            attachText("\(name): text not read", error)
            return
        }
        let found = truncatedText(in: parts, area: area, reading: reading)
        tally.read += found.read
        for truncated in found.truncated {
            if !tally.truncated.contains(truncated) {
                tally.truncated.append(truncated)
            }
            XCTFail("\(name): TRUNCATED: \(truncated).", file: file, line: line)
        }
        attachText("\(name): text read", reading.lines.map { "\($0.text)  at \($0.frame)" }.joined(separator: "\n"))
    }

    /// Every frame, for the attachments.
    @MainActor
    func describe(_ parts: QuestionParts, in area: CGRect) -> String {
        var lines = ["Window: \(windowFrame)", "Question area: \(parts.area)", "Visible: \(area)"]
        if keyboardIsOnScreen {
            lines.append("Keyboard: \(keyboard.frame), glass from y = \(keyboardGlassFrame.minY)")
        }
        lines += parts.words.map { "\($0.key): \($0.frame)" }
        lines += parts.pictures.map { "\($0.key): \($0.frame)" }
        lines += parts.answerBoxes.enumerated().map { "answer box \($0.offset + 1): \($0.element)" }
        lines += parts.controls.map { "\($0.key): \($0.frame)" }
        return lines.joined(separator: "\n")
    }
}
