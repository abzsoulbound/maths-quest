//
//  FeedbackBatchFBBUITests.swift
//  Maths QuestUITests
//

import XCTest

/// User feedback, batch FB-B, as a player sees it.
///
/// Answers written in the wrong form are asked for again. They score nothing, don't count towards Skip and bring up no
/// hint, and the answer stays in the box so it can be put right:
/// - Time: one of the two boxes left empty for a time ("Fill in both boxes.").
/// - Geometry: a perimeter or an area typed with its unit, "24cm" ("Type just the number, then pick the unit.").
/// - Volume: a cube or cuboid typed with its unit, "125cm3" ("Type just the number.").
/// - Ratio: two numbers in one box, "2:3" ("Put each number in its own box.").
/// - Shapes: "diamond" or "rhombus" for the square, which is drawn standing on a corner ("Imagine it turned to sit on
///   one side.").
///
/// Right answers written as a child might write them are accepted, and the same answers naming the wrong angle, glass
/// or bar are still wrong:
/// - Geometry: "a right angle", "an acute angle".
/// - Volume: "Glass A".
/// - Statistics: "Category B".
///
/// After each one the right answer is still marked right, with one point. The new messages can be read in full, at the
/// default and the largest text size. Every answer is worked out here from what the screen shows, not taken from the
/// app. An iPhone number pad has no letters, colon or slash, so only an iPad keyboard lets a child type "24cm" or
/// "2:3"; XCUITest types them into any box, and each test records whether the keyboard on screen has the key.
@MainActor
final class FeedbackBatchFBBUITests: FeedbackBatchUITestCase {

    // MARK: - Time: both boxes

    func testTimeAsksForBothBoxes() throws {
        try checkBothTimeBoxes(largestText: false)
    }

    func testTimeAsksForBothBoxesAtTheLargestTextSize() throws {
        try checkBothTimeBoxes(largestText: true)
    }

    /// "What is the time 2 hours and 5 minutes after 07:55?", answered in two boxes. The hours alone, twice, and then
    /// the minutes alone are asked for again. A wrong time in both boxes is still wrong.
    private func checkBothTimeBoxes(largestText: Bool) throws {
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

        // The hours alone, twice: two counted wrong answers would bring up Skip.
        replaceText(in: hoursBox, with: h)
        checkAskedAgain(Self.fillInBothBoxes, "Time\(size), the hours alone", points: start,
                        boxes: [(hoursBox, h), (minutesBox, "")], checkReadable: true)
        checkAskedAgain(Self.fillInBothBoxes, "Time\(size), the hours alone again", points: start,
                        boxes: [(hoursBox, h), (minutesBox, "")])
        // The minutes alone.
        clear(hoursBox)
        replaceText(in: minutesBox, with: m)
        checkAskedAgain(Self.fillInBothBoxes, "Time\(size), the minutes alone", points: start,
                        boxes: [(hoursBox, ""), (minutesBox, m)])

        // A wrong time in both boxes is wrong and counts, but one wrong answer doesn't bring up Skip.
        replaceText(in: hoursBox, with: String(format: "%02d", (hours + 1) % 24))
        pressEnter(expectingMessage: "Incorrect. Try Again!")
        assertPoints(start)
        XCTAssertFalse(skipButton.exists, "Skip appeared after one wrong answer.")

        replaceText(in: hoursBox, with: h)
        pressEnter(expectingMessage: "Correct!")
        assertPoints(start + 1)
        waitForNextTimeQuestion(after: label)
        assertPoints(start + 1)
    }

    // MARK: - Geometry: the unit typed in, and "a right angle"

    func testGeometryAsksForTheNumberWithoutItsUnit() throws {
        try checkGeometryUnitTypedIn(largestText: false)
    }

    func testGeometryAsksForTheNumberWithoutItsUnitAtTheLargestTextSize() throws {
        try checkGeometryUnitTypedIn(largestText: true)
    }

    /// "24cm" and "24 centimetres" for a perimeter, or "28cm" and "28 sq cm" for an area, are asked for again with no
    /// hint. A wrong number with the right unit picked is still wrong, with its hint.
    private func checkGeometryUnitTypedIn(largestText: Bool) throws {
        if largestText {
            extraLaunchArguments = Self.largestText
        }
        let size = largestText ? ", largest text" : ""
        let shape = try findQuestion(in: "Geometry", inYear: 4) { () -> GeometryShape? in
            readGeometryShape()
        }
        attachText("Geometry question\(size)", shape.description)
        let start = currentPoints()

        focus(answerField)
        let letterKey = keyboard.keys["c"].exists || keyboard.keys["C"].exists
        let typed = ["\(shape.answer)\(shape.unit)",
                     shape.isArea ? "\(shape.answer) sq \(shape.unit)" : "\(shape.answer) \(shape.unitName)"]
        for (attempt, answer) in typed.enumerated() {
            guard type(answer, into: answerField) else {
                throw XCTSkip("\"\(answer)\" can't be typed here (letter keys: \(letterKey)), so a child can't type it either.")
            }
            attachText("Geometry keyboard\(size), \(attempt + 1)",
                       "The keyboard has letter keys: \(letterKey). The box shows \"\(typedText(in: answerField))\".")
            checkAskedAgain(Self.numberThenUnit, "Geometry\(size), \"\(answer)\"", points: start,
                            boxes: [(answerField, answer)], checkReadable: attempt == 0)
        }

        // The right unit with a wrong number is marked, and wrong, with a hint. Skip doesn't appear after one.
        pickUnit(shape.answerUnit)
        replaceText(in: answerField, with: "\(shape.answer + 1)")
        pressEnter(expectingMessage: "Incorrect. Try Again!")
        assertPoints(start)
        XCTAssertTrue(hintCard.waitForExistence(timeout: 3), "No hint after a wrong number, as there was before.")
        XCTAssertFalse(skipButton.exists, "Skip appeared after one wrong answer.")

        replaceText(in: answerField, with: "\(shape.answer)")
        pressEnter(expectingMessage: "Correct!")
        assertPoints(start + 1)
        waitForNextQuestion()
        assertPoints(start + 1)
    }

    /// "a right angle" and "an obtuse angle" are accepted for the right angle type, and the wrong type is still wrong,
    /// with or without "a".
    func testGeometryAcceptsAnAngleNamedWithAOrAn() throws {
        let angle = try findQuestion(in: "Geometry", inYear: 4) { () -> String? in
            guard let shown = readAngleType() else { return nil }
            return shown
        }
        attachText("Geometry angle", "The angle is \(angle).")
        let start = currentPoints()
        func named(_ type: String) -> String { (type == "right" ? "a " : "an ") + type + " angle" }
        let wrong = angle == "acute" ? "obtuse" : "acute"

        // The angle box has the full keyboard on every device.
        answer(named(wrong), expecting: .incorrect)
        assertPoints(start)
        XCTAssertFalse(skipButton.exists, "Skip appeared after one wrong answer.")

        replaceText(in: answerField, with: named(angle).capitalized + ".")
        pressEnter(expectingMessage: "Correct!")
        assertPoints(start + 1)
        waitForNextQuestion()
        assertPoints(start + 1)
    }

    // MARK: - Volume: the unit typed in, and "Glass A"

    func testVolumeAsksForTheNumberWithoutItsUnit() throws {
        try checkVolumeUnitTypedIn(largestText: false)
    }

    func testVolumeAsksForTheNumberWithoutItsUnitAtTheLargestTextSize() throws {
        try checkVolumeUnitTypedIn(largestText: true)
    }

    /// "125cm3" and "125 cm³" for a cube or cuboid, with "cm³" already written by the box, are asked for again.
    private func checkVolumeUnitTypedIn(largestText: Bool) throws {
        if largestText {
            extraLaunchArguments = Self.largestText
        }
        let size = largestText ? ", largest text" : ""
        let pattern = #"^A (cube|cuboid)\. Width [0-9]+ centimetres, length [0-9]+ centimetres, height [0-9]+ centimetres\.$"#
        let volume = try findQuestion(in: "Volume", inYear: 5) { () -> Int? in
            guard answerField.waitForExistence(timeout: 10) else { return nil }
            let picture = labelled(pattern)
            guard picture.waitForExistence(timeout: 1),
                  let edges = picture.label.firstMatch(of: #/Width (\d+) centimetres, length (\d+) centimetres, height (\d+) centimetres/#),
                  let width = Int(edges.1), let length = Int(edges.2), let height = Int(edges.3) else { return nil }
            return width * length * height
        }
        attachText("Volume question\(size)", "Volume \(volume)")
        let start = currentPoints()

        focus(answerField)
        let letterKey = keyboard.keys["c"].exists || keyboard.keys["C"].exists
        // "cm³" if it can be typed here, or "cm" if not, which is asked for again in the same way.
        var typed = ["\(volume)cm3", "\(volume) cm³"]
        for (attempt, answer) in typed.enumerated() {
            var answer = answer
            if !type(answer, into: answerField) {
                guard attempt == 1, type("\(volume) cm", into: answerField) else {
                    throw XCTSkip("\"\(answer)\" can't be typed here (letter keys: \(letterKey)), so a child can't type it either.")
                }
                answer = "\(volume) cm"
                typed[attempt] = answer
            }
            attachText("Volume keyboard\(size), \(attempt + 1)",
                       "The keyboard has letter keys: \(letterKey). The box shows \"\(typedText(in: answerField))\".")
            checkAskedAgain(Self.justTheNumber, "Volume\(size), \"\(answer)\"", points: start,
                            boxes: [(answerField, answer)], checkReadable: attempt == 0)
        }

        replaceText(in: answerField, with: "\(volume)")
        pressEnter(expectingMessage: "Correct!")
        assertPoints(start + 1)
        waitForNextQuestion()
        assertPoints(start + 1)
    }

    /// "Glass A has 750 mL. Glass B has 0.8 L. Which has more liquid?" "glass" and the wrong letter is wrong, and
    /// "Glass" and the right letter is right.
    func testVolumeAcceptsTheGlassNamedWithItsLetter() throws {
        let fuller = try findQuestion(in: "Volume", inYear: 5) { () -> String? in
            guard answerField.waitForExistence(timeout: 10) else { return nil }
            let question = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Glass A has '")).firstMatch
            guard question.waitForExistence(timeout: 1), let label = (try? question.snapshot())?.label,
                  let amounts = label.firstMatch(of: #/Glass A has (\d+) mL\. Glass B has ([0-9.]+) L\./#),
                  let a = Int(amounts.1), let b = Double(amounts.2) else { return nil }
            let bMillilitres = Int((b * 1000).rounded())
            guard a != bMillilitres else { return nil }
            return a > bMillilitres ? "A" : "B"
        }
        attachText("Volume glasses", "Glass \(fuller) has more.")
        let start = currentPoints()
        let other = fuller == "A" ? "B" : "A"

        answer("glass \(other)", expecting: .incorrect)
        assertPoints(start)
        XCTAssertFalse(skipButton.exists, "Skip appeared after one wrong answer.")

        replaceText(in: answerField, with: "Glass \(fuller)")
        pressEnter(expectingMessage: "Correct!")
        assertPoints(start + 1)
        waitForNextQuestion()
        assertPoints(start + 1)
    }

    // MARK: - Statistics: "Category B"

    /// "Which category has the highest value?" "Category" and the wrong letter is wrong, and the right one is right.
    func testStatisticsAcceptsTheCategoryNamedWithItsLetter() throws {
        let highest = try findQuestion(in: "Statistics", inYear: 5) { () -> String? in
            let question = text("Which category has the highest value?")
            guard question.waitForExistence(timeout: 2) else { return nil }
            let bars = app.descendants(matching: .any).matching(NSPredicate(format: "label MATCHES '^Category [A-Z]$'"))
            let values = bars.allElementsBoundByIndex.compactMap { bar -> (String, Int)? in
                guard let snapshot = try? bar.snapshot(), let value = Int(snapshot.value as? String ?? "") else { return nil }
                return (String(snapshot.label.dropFirst("Category ".count)), value)
            }
            guard values.count >= 2, let top = values.max(by: { $0.1 < $1.1 }),
                  values.filter({ $0.1 == top.1 }).count == 1 else { return nil }
            return top.0
        }
        attachText("Statistics bars", "Category \(highest) is highest.")
        let start = currentPoints()
        let other = highest == "A" ? "B" : "A"

        answer("Category \(other)", expecting: .incorrect)
        assertPoints(start)
        XCTAssertFalse(skipButton.exists, "Skip appeared after one wrong answer.")

        replaceText(in: answerField, with: "category \(highest)")
        pressEnter(expectingMessage: "Correct!")
        assertPoints(start + 1)
        waitForNextQuestion()
        assertPoints(start + 1)
    }

    // MARK: - Ratio: two numbers in one box

    func testRatioAsksForEachNumberInItsOwnBox() throws {
        try checkRatioNumbersInOneBox(largestText: false)
    }

    func testRatioAsksForEachNumberInItsOwnBoxAtTheLargestTextSize() throws {
        try checkRatioNumbersInOneBox(largestText: true)
    }

    /// "Simplify the ratio 6 to 9" or "Divide 35 in the ratio 3 to 4", answered in two boxes. The answer typed as "2:3"
    /// in the first box, and then as "2/3" in the second, is asked for again with no hint.
    private func checkRatioNumbersInOneBox(largestText: Bool) throws {
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

        focus(first)
        let colonKey = keyboard.keys[":"].exists
        let colon = "\(answer[0]):\(answer[1])"
        guard type(colon, into: first) else {
            throw XCTSkip("\"\(colon)\" can't be typed here (colon key: \(colonKey)), so a child can't type it either.")
        }
        attachText("Ratio keyboard\(size)", "The keyboard has a colon key: \(colonKey). The box shows \"\(typedText(in: first))\".")
        checkAskedAgain(Self.oneNumberPerBox, "Ratio\(size), \"\(colon)\" in the first box", points: start,
                        boxes: [(first, colon), (second, "")], checkReadable: true)

        clear(first)
        let slash = "\(answer[0])/\(answer[1])"
        guard type(slash, into: second) else {
            throw XCTSkip("\"\(slash)\" can't be typed here, so a child can't type it either.")
        }
        checkAskedAgain(Self.oneNumberPerBox, "Ratio\(size), \"\(slash)\" in the second box", points: start,
                        boxes: [(first, ""), (second, slash)])

        replaceText(in: first, with: "\(answer[0])")
        replaceText(in: second, with: "\(answer[1])")
        pressEnter(expectingMessage: "Correct!")
        assertPoints(start + 1)
        waitForNextQuestion()
        assertPoints(start + 1)
    }

    // MARK: - Shapes: the square on its corner

    func testShapesAsksAgainWhenTheSquareIsCalledADiamond() throws {
        try checkTheTurnedSquare(largestText: false)
    }

    func testShapesAsksAgainWhenTheSquareIsCalledADiamondAtTheLargestTextSize() throws {
        try checkTheTurnedSquare(largestText: true)
    }

    /// "What is this shape called?" for the square, which is drawn standing on a corner. "diamond" and "Rhombus" are
    /// asked for again; "triangle" is wrong; "a square" is right.
    private func checkTheTurnedSquare(largestText: Bool) throws {
        if largestText {
            extraLaunchArguments = Self.largestText
        }
        let size = largestText ? ", largest text" : ""
        // One question in 18 names the square.
        try findQuestion(in: "Shapes", inYear: 2, attempts: 150) { () -> Bool? in
            guard text("What is this shape called?").waitForExistence(timeout: 2) else { return nil }
            let corners = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Corner'"))
            return corners.count == 4 ? true : nil
        }
        let start = currentPoints()

        for (attempt, answer) in ["diamond", "Rhombus"].enumerated() {
            replaceText(in: answerField, with: answer)
            checkAskedAgain(Self.turnedSquare, "Shapes\(size), \"\(answer)\"", points: start,
                            boxes: [(answerField, answer)], checkReadable: attempt == 0)
        }

        answer("triangle", expecting: .incorrect)
        assertPoints(start)
        XCTAssertFalse(skipButton.exists, "Skip appeared after one wrong answer.")

        replaceText(in: answerField, with: "a square")
        pressEnter(expectingMessage: "Correct!")
        assertPoints(start + 1)
        waitForNextQuestion()
        assertPoints(start + 1)
    }

    // MARK: - Reading questions

    struct GeometryShape: CustomStringConvertible {
        let isArea: Bool
        let picture: String
        let sides: [Int]
        /// "cm".
        let unit: String
        /// "centimetres".
        let unitName: String

        /// The perimeter, or length × width for a rectangle or square's area.
        var answer: Int { isArea ? sides[0] * sides[1] : sides.reduce(0, +) }
        /// On the unit wheel.
        var answerUnit: String { isArea ? unit + "²" : unit }
        var description: String { (isArea ? "Area" : "Perimeter") + " | \(picture) | answer \(answer) \(answerUnit)" }
    }

    /// A perimeter or area question, from its words and what VoiceOver reads for the shape, as in
    /// `Stage9CFeedbackUITests.readGeometryQuestion`.
    private func readGeometryShape() -> GeometryShape? {
        let questionTexts = ["Find the perimeter of the shape below", "Calculate the area of the shape below"]
        let shown = app.staticTexts.matching(NSPredicate(format: "label IN %@", questionTexts)).firstMatch
        let picture = labelled(#"^A (triangle|square|rectangle|pentagon|shape) with sides of .+ and \d+ (milli|centi|kilo)?metres?\.$"#)
        guard shown.waitForExistence(timeout: 3), picture.waitForExistence(timeout: 1),
              let questionText = (try? shown.snapshot())?.label,
              let description = (try? picture.snapshot())?.label else { return nil }
        let isArea = questionText == questionTexts[1]
        let lengths = description.matches(of: #/(\d+) (milli|centi|kilo)?metres?/#)
        guard let first = lengths.first else { return nil }
        let prefix = first.output.2.map { String($0) } ?? ""
        guard let unit = ["milli": "mm", "centi": "cm", "": "m", "kilo": "km"][prefix] else { return nil }
        let sides = lengths.compactMap { Int($0.output.1) }
        guard !isArea || sides.count == 4 else { return nil }
        return GeometryShape(isArea: isArea, picture: description, sides: sides, unit: unit, unitName: prefix + "metres")
    }

    /// "acute", "right" or "obtuse", from what VoiceOver reads for the angle.
    private func readAngleType() -> String? {
        guard text("Identify this angle type.").waitForExistence(timeout: 3) else { return nil }
        let picture = labelled(#"^An angle\. One arm points right, and the other points (up and to the right|straight up|up and to the left)\.$"#)
        guard picture.waitForExistence(timeout: 1), let description = (try? picture.snapshot())?.label,
              let match = description.firstMatch(of: #/points (up and to the right|straight up|up and to the left)\.$/#)
        else { return nil }
        return ["up and to the right": "acute", "straight up": "right", "up and to the left": "obtuse"][String(match.1)]
    }

    /// A Ratio question answered in two boxes, and its answer worked out here.
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

// MARK: - Shared by the feedback batches' UI tests

/// What the FB-B and FB-C UI tests share: finding a question, reading the message after Enter and checking it can be
/// read, and checking that an answer was asked for again rather than marked.
@MainActor
class FeedbackBatchUITestCase: MathsQuestUITestCase {

    static let largestText = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

    // The messages from batch FB-B, as the app words them in `AnswerFormat`.
    static let fillInBothBoxes = "Fill in both boxes."
    static let oneNumberPerBox = "Put each number in its own box."
    static let numberThenUnit = "Type just the number, then pick the unit."
    static let justTheNumber = "Type just the number."
    static let turnedSquare = "Imagine it turned to sit on one side."

    /// The Stage 9C hint, under Enter.
    var hintCard: XCUIElement { app.descendants(matching: .any)["HintCard"] }

    /// An answer box by the name VoiceOver reads for it. Boxes with their own accessibility label (Ratios) have it as
    /// `label`; boxes named only by their title (Time's Hours and Minutes) have it as `placeholderValue` and an empty
    /// label, so both are matched, as the Stage 5D and 9B tests do.
    func box(labelled name: String) -> XCUIElement {
        app.textFields.matching(NSPredicate(format: "label == %@ OR placeholderValue == %@", name, name)).firstMatch
    }

    /// Waits for the next question after a Time question reading `label`. Time's next question may be setting the
    /// clock, which has no answer box, so `waitForNextQuestion` (which waits for an empty box) can't be used: this
    /// waits for the question that was answered to go, with no message showing.
    func waitForNextTimeQuestion(after label: String, file: StaticString = #filePath, line: UInt = #line) {
        let answered = app.staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch
        XCTAssertTrue(waitQuickly(timeout: 5) { !answered.exists && visibleFeedback() == nil },
                      "The next question didn't appear.", file: file, line: line)
    }

    func labelled(_ pattern: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label MATCHES %@", pattern)).firstMatch
    }

    // MARK: Finding a question

    struct QuestionNotFound: Error, CustomStringConvertible {
        let description: String
    }

    /// When the app was last launched. The interstitial ad can show on a menu 3 minutes after launch, so the app is
    /// launched again well before then rather than going back through the menus.
    private var lastLaunch: Date?

    /// Opens `activity` until `read` finds a question it wants, and returns what it read.
    @discardableResult
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

    // MARK: Typing

    /// Empties `field`.
    func clear(_ field: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        focus(field, file: file, line: line)
        for _ in 0..<3 {
            let existing = typedText(in: field)
            if existing.isEmpty {
                break
            }
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
            if !typedText(in: field).isEmpty {
                focus(field, file: file, line: line)
            }
        }
        XCTAssertEqual(typedText(in: field), "", "Couldn't empty the box.", file: file, line: line)
    }

    /// Types `text` in place of what's in `field`, and says whether the box shows it. Unlike `replaceText(in:with:)`,
    /// it doesn't fail if the keyboard can't type it.
    func type(_ text: String, into field: XCUIElement, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        clear(field, file: file, line: line)
        field.typeText(text)
        return typedText(in: field) == text
    }

    // MARK: Messages

    /// Any message after Enter, including the FB-B ones, which `visibleFeedback()` doesn't look for.
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

    /// Taps Enter on an answer written in the wrong form and checks that `message` shows (and, if `checkReadable`,
    /// that it can be read in full); that the points haven't changed; that neither Skip nor a hint has appeared; and
    /// that every box still shows what was typed, so the answer can be put right. Skip comes after two wrong answers,
    /// so two of these in a row with no Skip show that neither counted.
    func checkAskedAgain(_ message: String, _ when: String, points: Int, boxes: [(XCUIElement, String)],
                         checkReadable: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        if checkReadable {
            enterAndCheckTheMessage(message, when, file: file, line: line)
        } else {
            pressEnter(expectingMessage: message, file: file, line: line)
        }
        assertPoints(points, file: file, line: line)
        XCTAssertFalse(skipButton.exists, "\(when): Skip appeared, so the answer counted as wrong.", file: file, line: line)
        XCTAssertFalse(hintCard.exists, "\(when): a hint appeared, so the answer was marked.", file: file, line: line)
        for (box, text) in boxes {
            XCTAssertEqual(typedText(in: box), text, "\(when): the answer was changed, so it can't be put right.",
                           file: file, line: line)
        }
    }

    // MARK: Checking a message can be read, as in FeedbackBatchFBAUITests

    /// The screen, read once while a message shows.
    private struct MessageSample {
        /// Seconds since Enter was tapped, at the middle of the snapshot.
        let time: TimeInterval
        let parts: QuestionParts
    }

    /// How long the keyboard, the message, Enter and the answer boxes must have stayed put for a snapshot to count as
    /// taken while nothing was moving, as in the Stage 9B tests (`Stage9BInteractionChecks.stillFor`).
    private static let stillFor: TimeInterval = 0.15

    /// Taps Enter and checks that `expected` follows and can be read: below the header, and above the keyboard's glass
    /// if the keyboard is up. The message shows for a second, too briefly for `waitForExistence`, so the screen is read
    /// as often as snapshots allow while it shows, as the Stage 9B tests do. Only snapshots taken while nothing was
    /// moving are judged: the whole message with the keyboard down, and its first line with the keyboard up, which is
    /// the line the app keeps above the keyboard. A screenshot is attached, because a frame check can't see text cut
    /// short with "…".
    func enterAndCheckTheMessage(_ expected: String, _ when: String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitQuickly(timeout: 5) { shownMessage() == nil && enterButton.isEnabled },
                      "\(when): Enter didn't become available again.", file: file, line: line)
        let overhang = keyboardIsOnScreen ? keyboard.frame.minY - keyboardGlassFrame.minY : 0
        tap(enterButton, file: file, line: line)
        let start = Date()
        var samples: [MessageSample] = []
        var sawMessage = false
        var tookScreenshot = false
        while Date().timeIntervalSince(start) < 3 {
            let before = Date()
            let parts = questionParts()
            guard !parts.area.isNull else {
                continue // The snapshot failed.
            }
            let time = (before.timeIntervalSince(start) + Date().timeIntervalSince(start)) / 2
            if !tookScreenshot, let previous = samples.last, previous.parts.message != nil, parts.message != nil,
               nothingMoved(previous.parts, parts) {
                attachScreenshot("\(when): the message")
                tookScreenshot = true
            }
            samples.append(MessageSample(time: time, parts: parts))
            if parts.message != nil {
                sawMessage = true
            } else if sawMessage {
                break
            }
        }
        attachText("\(when): snapshots after Enter", messageLog(samples, overhang: overhang))

        guard let first = samples.compactMap(\.parts.message).first else {
            return XCTFail("\(when): \"\(expected)\" wasn't seen in \(samples.count) snapshots over the 3 seconds after "
                           + "Enter.", file: file, line: line)
        }
        XCTAssertEqual(first.label, expected, "\(when): unexpected message after Enter.", file: file, line: line)
        let still = stillSamples(samples)
        guard !still.isEmpty else {
            return XCTFail("UNVERIFIED: \(when): the message was never seen standing still, so whether it can be read "
                           + "couldn't be checked.", file: file, line: line)
        }
        var problems: [String] = []
        for sample in still {
            guard let message = sample.parts.message else {
                continue
            }
            let area = visibleArea(of: sample.parts, overhang: overhang)
            var frame = message.frame
            var part = "the message"
            if sample.parts.keyboardUp {
                frame.size.height = min(frame.height, firstLineHeight(in: sample.parts))
                part = "the message's first line"
            }
            if !isInView(frame, area) {
                problems.append(String(format: "%.2f s: ", sample.time)
                                + "\(part) \(frame) is \(percentInView(frame, area))% in view of \(area)")
            }
        }
        XCTAssertTrue(problems.isEmpty, "\(when): the message can't be read in full: "
                      + problems.joined(separator: "; "), file: file, line: line)
    }

    /// Whether the keyboard, the message, Enter and the answer boxes are where they were.
    private func nothingMoved(_ a: QuestionParts, _ b: QuestionParts) -> Bool {
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

    /// The samples taken while nothing was moving: each that agrees with every sample in the `stillFor` seconds before
    /// it, all with the message showing.
    private func stillSamples(_ samples: [MessageSample]) -> [MessageSample] {
        samples.indices.compactMap { index in
            let sample = samples[index]
            guard sample.parts.message != nil else {
                return nil
            }
            var earlier = index - 1
            while earlier >= 0, samples[earlier].parts.message != nil, nothingMoved(samples[earlier].parts, sample.parts) {
                if sample.time - samples[earlier].time >= Self.stillFor {
                    return sample
                }
                earlier -= 1
            }
            return nil
        }
    }

    /// The height of the message's first line: bold, at 7.5% of the content's width, which is the screen's up to 600
    /// points, as in `AnswerFeedbackText`.
    private func firstLineHeight(in parts: QuestionParts) -> CGFloat {
        let width = min(parts.window.isNull ? parts.area.width : parts.window.width, 600)
        return UIFont.systemFont(ofSize: width * 0.075, weight: .bold).lineHeight
    }

    private func messageLog(_ samples: [MessageSample], overhang: CGFloat) -> String {
        let lines = samples.map { sample -> String in
            let parts = sample.parts
            return [
                String(format: "%.2f s", sample.time),
                parts.keyboardUp ? "keyboard \(parts.keyboard)" : "keyboard down",
                "message " + (parts.message.map { "\"\($0.label)\" \($0.frame)" } ?? "none"),
                "boxes \(parts.answerBoxes)",
                "Enter " + (parts.enter.map { "\($0)" } ?? "none"),
                "visible \(visibleArea(of: parts, overhang: overhang))",
            ].joined(separator: " | ")
        }
        return (["Keyboard glass \(overhang) pt above the keyboard XCUITest reports. Times are from Enter."] + lines)
            .joined(separator: "\n")
    }
}
