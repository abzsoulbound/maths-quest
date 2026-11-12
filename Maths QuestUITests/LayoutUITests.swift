//
//  LayoutUITests.swift
//  Maths QuestUITests
//

import UIKit
import XCTest

/// The main controls fit on screen and don't overlap, with and without the keyboard. Run on an iPhone and an
/// iPad to cover both layouts.
///
/// The keyboard tests need the on-screen keyboard. On an iPhone simulator it comes up once something is typed,
/// even with the Mac's keyboard connected. On an iPad simulator with the Mac's keyboard connected, the letter
/// keyboards come up but the number and decimal pads don't, so a test that needs one is skipped there, never
/// passed.
final class LayoutUITests: MathsQuestUITestCase {

    @MainActor
    func testMainMenuFitsTheScreen() throws {
        launchApp()
        assertMainMenuFits()
        attachScreenshot("Main menu layout")
    }

    @MainActor
    func testActivityScreenFitsTheScreen() throws {
        launchApp()
        openYear(1)
        openActivity("Addition")
        assertAdditionScreenFits()
        attachScreenshot("Activity layout")
    }

    // MARK: Answering with the keyboard up

    /// A player can answer with the keyboard up, go on to the next question with the keyboard up again, and put
    /// the keyboard away without answering.
    @MainActor
    func testEnterWorksWithTheKeyboardUp() throws {
        launchApp()
        openYear(1)
        openActivity("Addition")
        let start = currentPoints()
        let (a, b) = operands(using: "+")
        guard showKeyboard(typing: "\(a + b)", into: answerField) else {
            throw XCTSkip(Self.noKeyboard(on: "Addition"))
        }
        assertAnswerAndEnterInView("Addition, keyboard up")
        attachScreenshot("Addition with the keyboard up")

        pressEnter(expecting: .correct)
        XCTAssertTrue(waitQuickly(timeout: 3) { !keyboardIsOnScreen }, "The keyboard stayed up after Enter.")
        assertPoints(start + 1)
        waitForNextQuestion()

        let (c, d) = operands(using: "+")
        XCTAssertTrue(showKeyboard(typing: "\(c + d)", into: answerField),
                      "The keyboard didn't come up for the next question.")
        assertAnswerAndEnterInView("Next question, keyboard up")
        attachScreenshot("Next question with the keyboard up")

        // Putting the keyboard away doesn't answer the question.
        hideKeyboardByTappingBackground()
        XCTAssertEqual(typedText(in: answerField), "\(c + d)", "Putting the keyboard away changed the answer.")
        XCTAssertNil(visibleFeedback(), "Putting the keyboard away answered the question.")
        assertPoints(start + 1)
        assertAnswerAndEnterInView("Next question, keyboard put away")

        pressEnter(expecting: .correct)
        assertPoints(start + 2)
    }

    /// Two wrong answers given with the keyboard up bring up Skip. With the keyboard up again, Enter and Skip
    /// are side by side above it and Skip can be tapped. The offer of an ad is turned down, so the question
    /// stays and no point is given.
    @MainActor
    func testWrongAnswersAndSkipWithTheKeyboardUpOnAddition() throws {
        try checkWrongAnswersAndSkipWithTheKeyboardUp(on: "Addition", inYear: 1, wrongAnswer: "99",
                                                      question: "[0-9]+ \\+ [0-9]+")
    }

    /// The same on the tallest question screen.
    @MainActor
    func testWrongAnswersAndSkipWithTheKeyboardUpOnPercentages() throws {
        try checkWrongAnswersAndSkipWithTheKeyboardUp(on: "Percentages", inYear: 5, wrongAnswer: "0",
                                                      question: "Find [0-9]+% of [0-9]+")
    }

    /// The same with a letter keyboard, which is taller than the number pad and also comes up on an iPad
    /// simulator. No Algebra answer is 0: x and the coefficients are all at least 1.
    @MainActor
    func testWrongAnswersAndSkipWithTheKeyboardUpOnAlgebra() throws {
        try checkWrongAnswersAndSkipWithTheKeyboardUp(
            on: "Algebra", inYear: 6, wrongAnswer: "0",
            question: "x \\+ [0-9]+ = [0-9]+|[0-9]*x \\+ [0-9]*x|[0-9] times open bracket [0-9]*x plus [0-9]+ close bracket")
    }

    /// An answer typed by tapping the keyboard's keys, as a player does, and then Enter. On the iPad, the first tap
    /// in the app after typing on a number or decimal pad used to shrink the keyboard as the finger lifted, so the
    /// screen moved under it and Enter did nothing. `typeText`, which the other tests use, doesn't tap the keys.
    @MainActor
    func testEnterWorksAfterTappingTheNumberPadKeys() throws {
        try checkEnterAfterTappingTheKeys(on: "Addition", inYear: 1)
    }

    /// The same with the decimal pad.
    @MainActor
    func testEnterWorksAfterTappingTheDecimalPadKeys() throws {
        try checkEnterAfterTappingTheKeys(on: "Decimals", inYear: 4)
    }

    // MARK: The keyboard on every activity

    @MainActor func testCountingWithTheKeyboard() throws { try checkTheKeyboard(on: "Counting", inYear: 1) }
    @MainActor func testAdditionWithTheKeyboard() throws { try checkTheKeyboard(on: "Addition", inYear: 1) }
    @MainActor func testSubtractionWithTheKeyboard() throws { try checkTheKeyboard(on: "Subtraction", inYear: 1) }
    @MainActor func testMultiplicationWithTheKeyboard() throws { try checkTheKeyboard(on: "Multiplication", inYear: 2) }
    @MainActor func testDivisionWithTheKeyboard() throws { try checkTheKeyboard(on: "Division", inYear: 2) }
    @MainActor func testShapesWithTheKeyboard() throws { try checkTheKeyboard(on: "Shapes", inYear: 2) }
    @MainActor func testFractionsWithTheKeyboard() throws { try checkTheKeyboard(on: "Fractions", inYear: 3) }
    @MainActor func testMeasurementWithTheKeyboard() throws { try checkTheKeyboard(on: "Measurement", inYear: 3) }
    @MainActor func testTimeWithTheKeyboard() throws { try checkTheKeyboard(on: "Time", inYear: 3) }
    @MainActor func testDecimalsWithTheKeyboard() throws { try checkTheKeyboard(on: "Decimals", inYear: 4) }
    @MainActor func testGeometryWithTheKeyboard() throws { try checkTheKeyboard(on: "Geometry", inYear: 4) }
    @MainActor func testMoneyWithTheKeyboard() throws { try checkTheKeyboard(on: "Money", inYear: 4) }
    @MainActor func testPercentagesWithTheKeyboard() throws { try checkTheKeyboard(on: "Percentages", inYear: 5) }
    @MainActor func testStatisticsWithTheKeyboard() throws { try checkTheKeyboard(on: "Statistics", inYear: 5) }
    @MainActor func testVolumeWithTheKeyboard() throws { try checkTheKeyboard(on: "Volume", inYear: 5) }
    @MainActor func testAlgebraWithTheKeyboard() throws { try checkTheKeyboard(on: "Algebra", inYear: 6) }
    @MainActor func testProbabilityWithTheKeyboard() throws { try checkTheKeyboard(on: "Probability", inYear: 6) }
    @MainActor func testRatiosWithTheKeyboard() throws { try checkTheKeyboard(on: "Ratios", inYear: 6) }

    // MARK: The tallest questions

    /// A cube or cuboid has a diagram above the drawing pad. On most iPhones the pad is made just short enough for
    /// the answer box and Enter to fit.
    @MainActor
    func testVolumeDiagramFitsWithTheKeyboard() throws {
        try checkTallQuestion(on: "Volume", inYear: 5, startingWith: "What is the volume of this")
    }

    /// On the smallest iPhones the clock to read is drawn just small enough for the answer boxes and Enter to fit.
    @MainActor
    func testReadingTheClockFitsWithTheKeyboard() throws {
        try checkTallQuestion(on: "Time", inYear: 3, startingWith: "What time is shown on this clock?")
    }

    // MARK: Other layouts

    @MainActor
    func testEnterAndSkipFitSideBySide() throws {
        launchApp()
        openYear(1)
        openActivity("Addition")
        answerWronglyTwice()

        let window = windowFrame
        assertFullyVisible(enterButton, "Enter", within: window)
        assertFullyVisible(skipButton, "Skip Question", within: window)
        assertNoOverlap([("Enter", enterButton.frame), ("Skip Question", skipButton.frame)])
        attachScreenshot("Enter and Skip")
    }

    /// The app's info.plist makes it portrait only, on iPad as well as iPhone, so turning the device
    /// sideways must leave it upright with everything still on screen.
    @MainActor
    func testTurningTheDeviceSidewaysKeepsTheAppUpright() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        addTeardownBlock { @MainActor in
            XCUIDevice.shared.orientation = .portrait
        }

        launchApp()
        assertUpright("Launched with the device sideways")
        assertMainMenuFits()
        attachScreenshot("Main menu, device sideways")

        openYear(1)
        openActivity("Addition")
        XCUIDevice.shared.orientation = .landscapeRight
        assertUpright("Turned the other way on an activity")
        assertAdditionScreenFits()
        attachScreenshot("Activity, device turned the other way")
    }

    // MARK: - Helpers

    /// Activities that use the number or decimal pad for some questions and a letter keyboard for others: Shapes
    /// for naming a shape, Geometry for naming an angle, Statistics for naming the highest bar and Volume for
    /// comparing the glasses.
    static let letterKeyboardOnSomeQuestions: Set<String> = ["Shapes", "Geometry", "Statistics", "Volume"]

    /// Why the keyboard checks on `activity` were skipped.
    static func noKeyboard(on activity: String) -> String {
        if UIDevice.current.userInterfaceIdiom == .pad {
            let letters = letterKeyboardOnSomeQuestions.contains(activity)
                ? "no question with a letter keyboard came up on \(activity)"
                : "\(activity) uses only those"
            return "Unverified on iPad with the keyboard up: the iPad simulator doesn't show the on-screen number or "
                + "decimal pad while the Mac's keyboard is connected (I/O > Keyboard > Connect Hardware Keyboard), "
                + "and \(letters)."
        }
        return "Unverified: the on-screen keyboard didn't come up on \(activity). In Simulator, turn off "
            + "I/O > Keyboard > Connect Hardware Keyboard."
    }

    /// Checks one activity the way a player answers it:
    /// 1. With the keyboard down, the header is clear of the question and every answer box and Enter are in view.
    /// 2. With the keyboard up, every answer box and Enter are still in view, between the header and the
    ///    keyboard's glass.
    /// 3. Enter can be tapped with the keyboard up. It shows a message and puts the keyboard away, and once the
    ///    keyboard has gone the message is in full view, clear of the header.
    /// 4. With the keyboard up again, tapping the background puts it away without answering, and the answer
    ///    boxes and Enter are back in view.
    /// Typing "1" is usually a wrong answer; when it's right the activity just moves on, which is fine here.
    @MainActor
    private func checkTheKeyboard(on activity: String, inYear year: Int) throws {
        continueAfterFailure = true
        launchApp()
        guard try openQuestionAndShowKeyboard(activity, inYear: year) else {
            return
        }

        let keyboardKind = UIDevice.current.userInterfaceIdiom == .pad
            ? "iPad keyboard"
            : (keyboardHasLetters ? "letters" : "number pad")
        attachScreenshot("\(activity) with the keyboard up")
        attachText("\(activity) frames with the keyboard up", """
            Window: \(windowFrame)
            Question area: \(questionAreaFrame)
            Keyboard: \(keyboard.frame), \(keyboardKind), glass from y = \(keyboardGlassFrame.minY)
            Answer boxes: \(app.textFields.allElementsBoundByIndex.map(\.frame))
            Enter: \(anyEnterButton.frame)
            """)
        assertAnswerAndEnterInView("\(activity), keyboard up")

        tap(anyEnterButton)
        let message = app.staticTexts.matching(NSPredicate(format: "label IN %@", Self.feedbackMessages)).firstMatch
        XCTAssertTrue(waitQuickly(timeout: 3) { message.exists }, "\(activity): Enter with the keyboard up showed no message.")
        XCTAssertTrue(waitQuickly(timeout: 3) { !keyboardIsOnScreen }, "\(activity): the keyboard stayed up after Enter.")
        if let shown = settledFrame(of: message) {
            attachScreenshot("\(activity) message after Enter")
            let area = questionAreaFrame.intersection(windowFrame)
            XCTAssertTrue(area.insetBy(dx: -0.5, dy: -0.5).contains(shown.frame),
                          "\(activity): the message \"\(shown.label)\" at \(shown.frame) isn't entirely in view in \(area).")
            assertNoOverlap([("The message", shown.frame), ("Home", homeButton.frame), ("The points", pointsLabel.frame),
                             ("Settings", settingsButton.frame)])
        } else {
            XCTFail("\(activity): the message after Enter went before it could be checked.")
        }
        XCTAssertTrue(waitQuickly(timeout: 5) { !message.exists && anyEnterButton.isEnabled },
                      "\(activity): Enter didn't become available again.")

        // A right answer can move on to a question with no answer box, such as Time's clock.
        guard answerField.waitForExistence(timeout: 3) else {
            return
        }
        XCTAssertTrue(showKeyboard(typing: "2", into: answerField), "\(activity): the keyboard didn't come up again.")
        assertAnswerAndEnterInView("\(activity), keyboard up again")
        hideKeyboardByTappingBackground()
        XCTAssertFalse(message.exists, "\(activity): putting the keyboard away answered the question.")
        _ = waitForFrameToSettle(of: anyEnterButton, timeout: 3, steadyFor: 0.3)
        assertAnswerAndEnterInView("\(activity), keyboard put away")
        attachScreenshot("\(activity) with the keyboard put away")
    }

    /// Opens the activity, checks it fits with the keyboard down, and types "1" in its first answer box to bring
    /// the keyboard up. Goes back out and in again for a new question while it shows one with no answer box,
    /// such as Time's "set the clock", or, on an iPad, one with a number pad where another question might use
    /// a letter keyboard. Throws XCTSkip if the keyboard never comes up, and fails if no answer box does.
    @MainActor
    private func openQuestionAndShowKeyboard(_ activity: String, inYear year: Int, attempts: Int = 12) throws -> Bool {
        let retryForLetters = UIDevice.current.userInterfaceIdiom == .pad
            && Self.letterKeyboardOnSomeQuestions.contains(activity)
        var sawAnswerBox = false
        for _ in 1...attempts {
            openYear(year)
            openActivity(activity)
            if answerField.waitForExistence(timeout: 2) {
                sawAnswerBox = true
                assertHeaderClearOfTheQuestion("\(activity), keyboard down")
                assertAnswerAndEnterInView("\(activity), keyboard down")
                if showKeyboard(typing: "1", into: answerField) {
                    return true
                }
                guard retryForLetters else {
                    break
                }
            }
            goHome()
        }
        guard sawAnswerBox else {
            XCTFail("\(attempts) \(activity) questions in a row had no answer box.")
            return false
        }
        throw XCTSkip(Self.noKeyboard(on: activity))
    }

    /// Opens `activity` until it shows the question starting with `question`, which is one of the tallest. Checks
    /// that its answer boxes and Enter are in view with the keyboard down, up, and put away again. With the keyboard
    /// up, the question's words and its picture must be entirely in view too, and the question mustn't grow: it can
    /// be laid out more tightly while the player types (the clock beside its instructions, at least 150 points across,
    /// or the cube beside its question), and it must be back at its size when the keyboard goes. The question is
    /// measured from the top of its words or its picture, whichever is higher, to the bottom of Enter. With the
    /// keyboard down, up and put away, the words and the picture must keep at least 8 points from each side of the
    /// screen. Throws XCTSkip after the keyboard-down check if the keyboard doesn't come up.
    @MainActor
    private func checkTallQuestion(on activity: String, inYear year: Int, startingWith question: String) throws {
        continueAfterFailure = true
        let attempts = 45
        var questionText: XCUIElement?
        for attempt in 0..<attempts {
            // The interstitial can come up at a menu three minutes after launch, so start afresh now and then.
            if attempt % 15 == 0 {
                launchApp()
            }
            openYear(year)
            openActivity(activity)
            let shown = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", question)).firstMatch
            if shown.waitForExistence(timeout: 2) {
                questionText = shown
                break
            }
            goHome()
        }
        guard let questionText else {
            XCTFail("\(attempts) \(activity) questions in a row didn't start \"\(question)\".")
            return
        }

        // The clock to read, or the cube or cuboid.
        let picture = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Clock' OR label BEGINSWITH 'A cub'")).firstMatch
        // From the top of the question's words or its picture, whichever is higher, to the bottom of Enter. It changes
        // if the picture or pad is resized, or the picture moves beside the words.
        func questionHeight() -> CGFloat {
            let top = picture.exists ? min(questionText.frame.minY, picture.frame.minY) : questionText.frame.minY
            return anyEnterButton.frame.maxY - top
        }
        func assertSideMargins(_ when: String) {
            let window = windowFrame
            for (name, element) in [("words", questionText), ("picture", picture)] where element.exists {
                let frame = element.frame
                XCTAssertGreaterThanOrEqual(frame.minX - window.minX, 7.5,
                    "\(activity), \(when): the question's \(name) at \(frame) are less than 8 points from the left of the screen.")
                XCTAssertGreaterThanOrEqual(window.maxX - frame.maxX, 7.5,
                    "\(activity), \(when): the question's \(name) at \(frame) are less than 8 points from the right of the screen.")
            }
        }
        func attachFrames(_ when: String) {
            attachText("\(activity) frames, \(when)", """
                Window: \(windowFrame)
                Question area: \(questionAreaFrame)
                Keyboard glass from y = \(keyboardIsOnScreen ? "\(keyboardGlassFrame.minY)" : "none")
                Question: \(questionText.frame)
                Picture: \(picture.exists ? "\(picture.label): \(picture.frame)" : "none")
                Clear (below the drawing pad, if there is one): \(app.buttons["Clear"].exists ? "\(app.buttons["Clear"].frame)" : "none")
                Answer boxes: \(app.textFields.allElementsBoundByIndex.map(\.frame))
                Enter: \(anyEnterButton.frame)
                """)
        }

        _ = waitForFrameToSettle(of: anyEnterButton, timeout: 3, steadyFor: 0.3)
        assertHeaderClearOfTheQuestion("\(activity), keyboard down")
        assertAnswerAndEnterInView("\(activity), keyboard down")
        assertSideMargins("keyboard down")
        let height = questionHeight()
        attachScreenshot("\(activity): \(question) with the keyboard down")
        attachFrames("keyboard down")

        guard showKeyboard(typing: "1", into: answerField) else {
            throw XCTSkip("\(activity): \"\(question)\" fits with the keyboard down. With it up it's unverified: "
                + "the on-screen keyboard didn't come up. The iPad simulator doesn't show the number or decimal pad "
                + "while the Mac's keyboard is connected (I/O > Keyboard > Connect Hardware Keyboard).")
        }
        _ = waitForFrameToSettle(of: anyEnterButton, timeout: 3, steadyFor: 0.3)
        assertAnswerAndEnterInView("\(activity), keyboard up")
        XCTAssertLessThanOrEqual(questionHeight(), height + 1, "\(activity): the question grew when the keyboard came up.")
        let area = visibleQuestionArea
        assertFullyVisible(questionText, "With the keyboard up, the question", within: area, tappable: false)
        assertFullyVisible(picture, "With the keyboard up, the picture", within: area, tappable: false)
        if picture.label == "Clock" {
            XCTAssertGreaterThanOrEqual(picture.frame.width, 149.5, "\(activity): the clock is too small to read with the keyboard up.")
        }
        assertSideMargins("keyboard up")
        attachScreenshot("\(activity): \(question) with the keyboard up")
        attachFrames("keyboard up")

        hideKeyboardByTappingBackground()
        _ = waitForFrameToSettle(of: anyEnterButton, timeout: 3, steadyFor: 0.3)
        assertAnswerAndEnterInView("\(activity), keyboard put away")
        XCTAssertEqual(questionHeight(), height, accuracy: 1, "\(activity): the question changed size when the keyboard went.")
        assertSideMargins("keyboard put away")
    }

    /// The two wrong answers, the Skip button and the offer of an ad, all with the keyboard up. `question` is a
    /// regular expression matching the question, to check it stays.
    @MainActor
    private func checkWrongAnswersAndSkipWithTheKeyboardUp(on activity: String, inYear year: Int,
                                                           wrongAnswer: String, question: String) throws {
        launchApp()
        openYear(year)
        openActivity(activity)
        let start = currentPoints()
        let questionText = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", question)).firstMatch
        XCTAssertTrue(questionText.waitForExistence(timeout: 10), "No \(activity) question on screen.")
        let shownQuestion = questionText.label

        for attempt in 1...2 {
            guard showKeyboard(replacingAnswerWith: wrongAnswer) else {
                throw XCTSkip(Self.noKeyboard(on: activity))
            }
            assertAnswerAndEnterInView("\(activity), wrong answer \(attempt), keyboard up")
            XCTAssertFalse(skipButton.exists, "Skip appeared after \(attempt - 1) wrong answers.")
            pressEnter(expecting: .incorrect)
            XCTAssertTrue(waitQuickly(timeout: 3) { !keyboardIsOnScreen }, "The keyboard stayed up after Enter.")
        }
        XCTAssertTrue(skipButton.waitForExistence(timeout: 5), "Skip didn't appear after two wrong answers.")
        assertPoints(start)

        XCTAssertTrue(showKeyboard(replacingAnswerWith: wrongAnswer), "The keyboard didn't come up again.")
        let area = visibleQuestionArea
        assertFullyVisible(answerField, "With the keyboard up, the answer box", within: area)
        assertFullyVisible(enterButton, "With the keyboard up, Enter", within: area)
        assertFullyVisible(skipButton, "With the keyboard up, Skip Question", within: area)
        assertNoOverlap([("Enter", enterButton.frame), ("Skip Question", skipButton.frame)])
        attachScreenshot("\(activity): Enter and Skip with the keyboard up")
        attachText("\(activity): Enter and Skip with the keyboard up", """
            Keyboard glass from y = \(keyboardGlassFrame.minY)
            Answer box: \(answerField.frame)
            Enter: \(enterButton.frame)
            Skip Question: \(skipButton.frame)
            """)

        tap(skipButton)
        let offer = app.alerts["Skip this question?"]
        let notReady = app.alerts["Ad Not Ready"]
        XCTAssertTrue(waitQuickly(timeout: 10) { offer.exists || notReady.exists },
                      "Tapping Skip with the keyboard up didn't offer an ad. If the question was skipped, Remove Ads "
                      + "has been bought in this simulator: erase it, or delete the app, to clear the local purchase.")
        attachScreenshot("\(activity): Skip tapped with the keyboard up")
        if offer.exists {
            tap(offer.buttons["No thanks"])
            XCTAssertTrue(offer.waitForNonExistence(timeout: 5), "The offer to watch an ad didn't close.")
        } else if notReady.exists {
            tap(notReady.buttons["OK"])
            XCTAssertTrue(notReady.waitForNonExistence(timeout: 5), "\"Ad Not Ready\" didn't close.")
        }
        XCTAssertFalse(text("Test mode").exists, "An ad played without being asked for.")
        XCTAssertEqual(questionText.label, shownQuestion, "Turning down the ad changed the question.")
        assertPoints(start)
    }

    /// Twice, types a wrong answer by tapping the keyboard's keys and taps Enter with the keyboard up. The second
    /// time, the keyboard has been put away by Enter and brought back. No Addition or Decimals answer is 999 or 99.
    @MainActor
    private func checkEnterAfterTappingTheKeys(on activity: String, inYear year: Int) throws {
        launchApp()
        openYear(year)
        openActivity(activity)
        let start = currentPoints()
        for (attempt, wrongAnswer) in ["999", "99"].enumerated() {
            focus(answerField)
            // The iPhone simulators only show their keyboard once something is typed. The iPad shows it on focus.
            if !waitQuickly(timeout: 2, until: { keyboardIsOnScreen }) {
                answerField.typeText("0")
            }
            guard waitQuickly(timeout: 5, until: { keyboardIsOnScreen }) else {
                throw XCTSkip(Self.noKeyboard(on: activity))
            }
            waitForKeyboardToSettle()
            let previous = typedText(in: answerField)
            if !previous.isEmpty {
                answerField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count))
            }
            for character in wrongAnswer {
                let key = app.keys[String(character)]
                XCTAssertTrue(key.waitForExistence(timeout: 5), "The \(activity) keyboard has no \(character) key.")
                key.tap()
            }
            XCTAssertEqual(typedText(in: answerField), wrongAnswer, "Tapping the keys didn't type the answer.")
            assertAnswerAndEnterInView("\(activity), answer \(attempt + 1) typed on the keys")
            attachScreenshot("\(activity): answer \(attempt + 1) typed on the keys")
            pressEnter(expecting: .incorrect)
            XCTAssertTrue(waitQuickly(timeout: 3) { !keyboardIsOnScreen }, "The keyboard stayed up after Enter.")
        }
        assertPoints(start)
    }

    /// Types `text` in place of the answer and waits for the keyboard to finish coming up. False if it doesn't.
    @MainActor
    private func showKeyboard(replacingAnswerWith text: String) -> Bool {
        replaceText(in: answerField, with: text)
        guard waitQuickly(timeout: 5, until: { keyboardIsOnScreen }) else {
            return false
        }
        waitForKeyboardToSettle()
        return true
    }

    @MainActor
    private func assertUpright(_ when: String, file: StaticString = #filePath, line: UInt = #line) {
        // The iPad turns the whole portrait screen round with the device, so wait for that to finish.
        XCTAssertTrue(waitForFrameToSettle(of: app.windows.firstMatch, timeout: 10, steadyFor: 1.5),
                      "\(when): the screen didn't stop moving.", file: file, line: line)
        let window = windowFrame
        XCTAssertGreaterThan(window.height, window.width, "\(when): the app turned sideways, but it's portrait only.",
                             file: file, line: line)
    }

    @MainActor
    private func assertMainMenuFits(file: StaticString = #filePath, line: UInt = #line) {
        let window = windowFrame
        assertFullyVisible(text("Maths Quest"), "The title", within: window, tappable: false, file: file, line: line)
        assertFullyVisible(pointsLabel, "The points", within: window, tappable: false, file: file, line: line)
        assertFullyVisible(menuButton, "The sidebar button", within: window, file: file, line: line)
        var frames: [(name: String, frame: CGRect)] = [("The title", text("Maths Quest").frame),
                                                       ("The points", pointsLabel.frame)]
        for year in 1...6 {
            let yearButton = button("Year \(year)")
            assertFullyVisible(yearButton, "Year \(year)", within: window, file: file, line: line)
            frames.append(("Year \(year)", yearButton.frame))
        }
        assertNoOverlap(frames, file: file, line: line)
    }

    @MainActor
    private func assertAdditionScreenFits(file: StaticString = #filePath, line: UInt = #line) {
        let window = windowFrame
        let questionText = text(question(using: "+", file: file, line: line))
        let prompt = text("What is the sum of these numbers?")
        assertFullyVisible(homeButton, "Home", within: window, file: file, line: line)
        assertFullyVisible(settingsButton, "Settings", within: window, file: file, line: line)
        assertFullyVisible(pointsLabel, "The points", within: window, tappable: false, file: file, line: line)
        assertFullyVisible(questionText, "The question", within: window, tappable: false, file: file, line: line)
        assertFullyVisible(prompt, "The prompt", within: window, tappable: false, file: file, line: line)
        assertFullyVisible(answerField, "The answer field", within: window, file: file, line: line)
        assertFullyVisible(enterButton, "Enter", within: window, file: file, line: line)
        assertNoOverlap([("Home", homeButton.frame), ("The points", pointsLabel.frame), ("Settings", settingsButton.frame),
                         ("The question", questionText.frame), ("The prompt", prompt.frame),
                         ("The answer field", answerField.frame), ("Enter", enterButton.frame)],
                        file: file, line: line)
    }
}
