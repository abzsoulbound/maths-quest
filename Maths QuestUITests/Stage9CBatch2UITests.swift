//
//  Stage9CBatch2UITests.swift
//  Maths QuestUITests
//
//  Stage 9C Batch 2, approved on 17 November 2026: hints, the line under "Correct!" and the worked solution after
//  Skip for Year 6 Algebra and Probability (B2-1 and B2-2), and Algebra answers that are right but written another
//  way (B2-3) or equal but not fully simplified (B2-4), which are asked for again. An answer asked for again shows its
//  message and nothing else: no point, no wrong-answer sound, no wrong attempt towards Skip and no new hint, while a
//  hint from an earlier wrong answer stays. Genuinely wrong answers are still marked wrong, and Probability still
//  accepts equal fractions.
//
//  The sound can't be heard from a UI test; `Stage9CBatch2Tests` checks in the source that asking again plays none.
//  Every expected wording here is worked out from the question on screen, as VoiceOver reads it.
//

import XCTest

@MainActor
final class Stage9CBatch2UITests: Stage9CFeedbackChecks {

    /// Probability's Enter has no trailing space, so both activities use this.
    override var enterButton: XCUIElement { anyEnterButton }

    // MARK: - Algebra

    /// A wrong answer the hint names for each kind of question, then the right answer and its line under "Correct!".
    func testAlgebraHintsThenCorrectLines() throws {
        continueAfterFailure = true
        try forEachKindOfAlgebraQuestion { question in
            let start = currentPoints()
            let mistake = question.namedMistake
            typeAnswer(mistake.typed)
            pressEnter(expecting: .incorrect)
            let hint = checkHintStays(withoutGiving: question.answerNumbers, from: question.shownNumbers)
            XCTAssertEqual(hint, mistake.hint, "\(question): the hint after \"\(mistake.typed)\".")
            print("B2|algebra hint|\(question.kind)|\(question.label)|\(mistake.typed)|\(hint)")
            checkCorrectLine(question.correctLine) { typeAnswer(question.answer) }
            assertPoints(start + 1)
            waitForNextQuestion()
            XCTAssertFalse(hintCard.exists, "\(question): the hint came back on the next question.")
        }
    }

    /// B2-3 and B2-4: three answers that are right but written another way, or equal but not simplified, are each
    /// asked for again. Then a genuinely wrong answer is still marked wrong, and with only one wrong attempt counted
    /// Skip stays hidden. An answer asked for again after that leaves the hint as it was. The right answer then scores.
    func testAlgebraEquivalentAnswersAreAskedAgain() throws {
        continueAfterFailure = true
        try forEachKindOfAlgebraQuestion { question in
            let start = currentPoints()
            for asked in question.askedAgain {
                checkAskedAgain(asked, on: question, points: start, hint: nil)
            }
            typeAnswer(question.wrongAnswer)
            pressEnter(expecting: .incorrect)
            XCTAssertTrue(hintCard.waitForExistence(timeout: 3), "\(question): no hint after a wrong answer.")
            XCTAssertFalse(skipButton.exists,
                           "\(question): Skip showed after one wrong answer, so an answer asked for again was counted.")
            assertPoints(start)
            XCTAssertTrue(waitQuickly(timeout: 5) { shownMessage() == nil }, "\"Incorrect. Try Again!\" didn't go.")
            let hint = hintCard.label
            checkAskedAgain(question.askedAgain[0], on: question, points: start, hint: hint)
            typeAnswer(question.answer)
            pressEnter(expecting: .correct)
            assertPoints(start + 1)
            waitForNextQuestion()
        }
    }

    /// Two wrong answers and Skip show the worked solution, whose answer VoiceOver reads in words.
    func testAlgebraSkipShowsWorkedSolution() throws {
        continueAfterFailure = true
        launchApp()
        openYear(6)
        openActivity("Algebra")
        guard let question = readAlgebraQuestion() else {
            return XCTFail("No Algebra question on screen.")
        }
        print("B2|algebra skip|\(question.kind)|\(question.label)|\(question.workedAnswer)")
        try checkSkipShowsWorkedSolution(
            answerLabel: question.workedAnswer, points: currentPoints(),
            readQuestion: { self.readAlgebraQuestion()?.label ?? "" },
            questionParts: [("The question", text(question.label)), ("The instruction", text(question.instruction))],
            answerNext: {
                guard let next = self.readAlgebraQuestion() else {
                    return XCTFail("No Algebra question after Next Question.")
                }
                self.typeAnswer(next.answer)
                self.pressEnter(expecting: .correct)
            })
    }

    // MARK: - Probability

    /// The fraction upside down brings the hint that names it, which stays and gives no number away. The right answer
    /// then brings its line under "Correct!".
    func testProbabilityHintThenCorrectLine() throws {
        continueAfterFailure = true
        launchApp()
        openYear(6)
        openActivity("Probability")
        guard let question = readProbabilityQuestion() else {
            return XCTFail("No Probability question on screen.")
        }
        let start = currentPoints()
        fillFraction(question.all, question.wanted)
        pressEnter(expecting: .incorrect)
        let hint = checkHintStays(withoutGiving: [question.simplest.numerator, question.simplest.denominator],
                                  from: question.shownNumbers)
        XCTAssertEqual(hint, "Hint: The numbers are upside down. The total goes on the bottom.", "\(question)")
        print("B2|probability hint|\(question.label)|\(question.all)/\(question.wanted)|\(hint)")
        checkCorrectLine(question.correctLine) { fillFraction(question.wanted, question.all) }
        assertPoints(start + 1)
        waitForNextQuestion()
        XCTAssertFalse(hintCard.exists, "The hint came back on the next question.")
    }

    /// Probability still accepts equal fractions, with no message asking for it again: the fraction with both numbers
    /// doubled, then on the next question its simplest form where it simplifies, or both numbers trebled where it
    /// doesn't. Each scores 1 and brings the usual line under "Correct!".
    func testProbabilityEquivalentFractionsAreAccepted() throws {
        continueAfterFailure = true
        launchApp()
        openYear(6)
        openActivity("Probability")
        for number in 1...2 {
            guard let question = readProbabilityQuestion() else {
                return XCTFail("No Probability question on screen.")
            }
            let start = currentPoints()
            let typed: (Int, Int)
            if number == 1 {
                typed = (2 * question.wanted, 2 * question.all)
            } else if question.simplest != (question.wanted, question.all) {
                typed = question.simplest
            } else {
                typed = (3 * question.wanted, 3 * question.all)
            }
            print("B2|probability equal|\(question.label)|\(typed.0)/\(typed.1)")
            checkCorrectLine(question.correctLine) { fillFraction(typed.0, typed.1) }
            assertPoints(start + 1)
            waitForNextQuestion()
        }
    }

    /// Two wrong answers and Skip show the worked solution. 99/100 is never a Probability answer: the bottom number is
    /// at most 20 in its simplest form.
    func testProbabilitySkipShowsWorkedSolution() throws {
        continueAfterFailure = true
        launchApp()
        openYear(6)
        openActivity("Probability")
        guard let question = readProbabilityQuestion() else {
            return XCTFail("No Probability question on screen.")
        }
        print("B2|probability skip|\(question.label)|\(question.workedAnswer)")
        // `answerWronglyTwice()` types 99 in the first box, the numerator.
        replaceText(in: fractionBox("Denominator"), with: "100")
        try checkSkipShowsWorkedSolution(
            answerLabel: question.workedAnswer, points: currentPoints(),
            readQuestion: { self.readProbabilityQuestion()?.label ?? "" },
            questionParts: [("The question", text(question.label))],
            answerNext: {
                guard let next = self.readProbabilityQuestion() else {
                    return XCTFail("No Probability question after Next Question.")
                }
                self.fillFraction(next.wanted, next.all)
                self.pressEnter(expecting: .correct)
            })
    }

    // MARK: - Asking again

    struct AskedAgain {
        let typed: String
        /// As VoiceOver reads it.
        let message: String
        /// The line under the message, as VoiceOver reads it, or nil for none.
        let detail: String?
    }

    /// Types `asked.typed` and Enter, and checks that only the message and its line show: no hint unless `hint` was
    /// already showing (and then it's unchanged), no Skip, no point, the same question, and the answer still in the
    /// box to change. The message then goes by itself, with nothing else changed.
    func checkAskedAgain(_ asked: AskedAgain, on question: AlgebraQuestion, points: Int, hint: String?,
                         file: StaticString = #filePath, line: UInt = #line) {
        let name = "\(question), \"\(asked.typed)\""
        typeAnswer(asked.typed, file: file, line: line)
        XCTAssertTrue(waitQuickly(timeout: 5) { shownMessage() == nil && enterButton.isEnabled },
                      "\(name): Enter didn't become available.", file: file, line: line)
        tap(enterButton, file: file, line: line)
        var shown: String?
        var shownDetail: String?
        _ = waitQuickly(timeout: 3) {
            shown = shown ?? shownMessage()
            shownDetail = shownDetail ?? (try? correctLine.snapshot())?.label
            return shown != nil && (asked.detail == nil || shownDetail != nil)
        }
        attachScreenshot("Asked again: \(asked.typed)")
        print("B2|asked again|\(question.kind)|\(question.label)|\(asked.typed)|\(shown ?? "none")|\(shownDetail ?? "none")")
        XCTAssertEqual(shown, asked.message, "\(name): the message.", file: file, line: line)
        if let detail = asked.detail {
            XCTAssertEqual(shownDetail, detail, "\(name): the line under the message.", file: file, line: line)
        } else {
            XCTAssertNil(shownDetail, "\(name): a line showed under the message.", file: file, line: line)
        }
        func checkNothingElseChanged(_ when: String) {
            if let hint {
                XCTAssertEqual(hintCard.exists ? hintCard.label : nil, hint, "\(name) \(when): the hint changed.",
                               file: file, line: line)
            } else {
                XCTAssertFalse(hintCard.exists, "\(name) \(when): a hint showed.", file: file, line: line)
            }
            XCTAssertFalse(skipButton.exists, "\(name) \(when): Skip showed.", file: file, line: line)
            XCTAssertEqual(typedText(in: answerField).lowercased(), asked.typed.lowercased(),
                           "\(name) \(when): the answer box changed.", file: file, line: line)
            XCTAssertEqual(readAlgebraQuestion(timeout: 1)?.label, question.label,
                           "\(name) \(when): the question changed.", file: file, line: line)
            assertPoints(points, file: file, line: line)
        }
        checkNothingElseChanged("with the message showing")
        XCTAssertTrue(waitQuickly(timeout: 5) { shownMessage() == nil },
                      "\(name): the message didn't go.", file: file, line: line)
        pause(0.5)
        checkNothingElseChanged("after the message went")
    }

    /// Clears the answer box and types `text`. The box can start a line with a capital letter, as "X + 7 = 19", which
    /// the app reads as small: so it's compared without capitals, and any capital is recorded.
    func typeAnswer(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let field = answerField
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
        XCTAssertEqual(typedText(in: field), "", "Couldn't clear the answer box.", file: file, line: line)
        field.typeText(text)
        let shown = typedText(in: field)
        if shown != text {
            print("B2|typed differently|\(text)|\(shown)")
            attachText("Typed \"\(text)\"", "The box shows \"\(shown)\".")
        }
        XCTAssertEqual(shown.lowercased(), text.lowercased(), "The answer box doesn't show what was typed.",
                       file: file, line: line)
    }

    // MARK: - Reading an Algebra question

    struct AlgebraQuestion: CustomStringConvertible {
        enum Kind: String { case solve, simplify, expand }
        let kind: Kind
        /// As VoiceOver reads it: "x + 7 = 19", "7x + 12x" or "3 times open bracket 5x plus 2 close bracket".
        let label: String
        /// Solve: the number added to x and x. Simplify: the two coefficients. Expand: the coefficient and the number
        /// inside the bracket.
        let first: Int
        let second: Int
        /// Expand: the number outside the bracket.
        let multiplier: Int

        /// "x" for 1, "7x" otherwise.
        static func term(_ coefficient: Int) -> String {
            coefficient == 1 ? "x" : "\(coefficient)x"
        }

        var total: Int { first + second }
        /// The x term and the number of the expanded answer.
        var expanded: (x: Int, number: Int) { (multiplier * first, multiplier * second) }

        var description: String { "\(kind) \"\(label)\"" }

        var instruction: String {
            switch kind {
            case .solve: return "Solve for x in this equation"
            case .simplify: return "Simplify this expression"
            case .expand: return "Expand this expression"
            }
        }

        /// The right answer, as typed.
        var answer: String {
            switch kind {
            case .solve: return "\(second)"
            case .simplify: return Self.term(total)
            case .expand: return "\(Self.term(expanded.x))+\(expanded.number)"
            }
        }

        /// The numbers of the answer, which a hint mustn't give.
        var answerNumbers: [Int] {
            switch kind {
            case .solve: return [second]
            case .simplify: return [total]
            case .expand: return [expanded.x, expanded.number]
            }
        }

        var shownNumbers: [Int] {
            switch kind {
            case .solve: return [first, total]
            case .simplify: return [first, second]
            case .expand: return [multiplier, first, second]
            }
        }

        /// The line under "Correct!", as VoiceOver reads it.
        var correctLine: String {
            switch kind {
            case .solve:
                return "x equals \(second), because \(second) plus \(first) equals \(total)"
            case .simplify:
                return "\(Self.term(first)) plus \(Self.term(second)) equals \(Self.term(total))"
            case .expand:
                return "\(label) equals \(Self.term(expanded.x)) plus \(expanded.number)"
            }
        }

        /// The worked solution's answer, as VoiceOver reads it.
        var workedAnswer: String {
            switch kind {
            case .solve: return "The answer is x equals \(second)."
            case .simplify: return "The answer is \(Self.term(total))."
            case .expand: return "The answer is \(Self.term(expanded.x)) plus \(expanded.number)."
            }
        }

        /// A wrong answer the hint names, and that hint as VoiceOver reads it: the total for Solve, the number
        /// without its x for Simplify, and what's inside the bracket for Expand.
        var namedMistake: (typed: String, hint: String) {
            switch kind {
            case .solve:
                return ("\(total)", "Hint: \(total) is the total. What number plus \(first) makes \(total)?")
            case .simplify:
                return ("\(total)", "Hint: Keep the x. The answer is a number of x's, not a number on its own.")
            case .expand:
                return ("\(Self.term(first))+\(second)", "Hint: That is what's inside the bracket. "
                        + "The \(multiplier) outside means multiply each part by \(multiplier).")
            }
        }

        /// A genuinely wrong answer: no Algebra answer is 99, 99x or 99x + 99.
        var wrongAnswer: String {
            switch kind {
            case .solve: return "99"
            case .simplify: return "99x"
            case .expand: return "99x+99"
            }
        }

        /// The x term the messages' examples use, which is never the answer's own.
        var exampleCoefficient: Int {
            let coefficient = kind == .expand ? expanded.x : total
            return coefficient == 2 ? 3 : 2
        }

        /// Three answers asked for again, each with its message and line as approved: the question typed back, a sum
        /// or working that's equal but not simplified, and the right answer written another way.
        var askedAgain: [AskedAgain] {
            let equal = "That's equal, but it needs simplifying further."
            switch kind {
            case .solve:
                return [
                    AskedAgain(typed: "\(first)+x=\(total)", message: "That's the question. Work out what x is.",
                               detail: "Take \(first) away from both sides, so x is on its own."),
                    AskedAgain(typed: "\(total)-\(first)", message: equal, detail: "Work it out, so x is a single number."),
                    AskedAgain(typed: "\(second).0", message: "Write x as a whole number, without a decimal point.",
                               detail: nil),
                ]
            case .simplify:
                return [
                    AskedAgain(typed: "\(Self.term(first))+\(Self.term(second))",
                               message: "That's the question. It needs simplifying.",
                               detail: "Put the x terms together into one x term."),
                    AskedAgain(typed: "(\(first)+\(second))x", message: equal,
                               detail: "Write it as one x term, like \(exampleCoefficient)x."),
                    AskedAgain(typed: "\(total)*x",
                               message: "In algebra, leave out the times sign. "
                                   + "Write \(exampleCoefficient)x, not \(exampleCoefficient) times x.",
                               detail: nil),
                ]
            case .expand:
                return [
                    AskedAgain(typed: "\(multiplier)(\(Self.term(first))+\(second))",
                               message: "That's the question. It needs expanding.",
                               detail: "Multiply each part inside the bracket by \(multiplier)."),
                    AskedAgain(typed: "\(multiplier)*\(Self.term(first))+\(multiplier)*\(second)", message: equal,
                               detail: "Write it as an x term plus a number, like 2x plus 3."),
                    AskedAgain(typed: "\(Self.term(expanded.x))+\(expanded.number).0",
                               message: "Write each number as a whole number, without a decimal point.", detail: nil),
                ]
            }
        }
    }

    static let algebraLabels = #"x \+ [0-9]+ = [0-9]+|[0-9]*x \+ [0-9]*x|[0-9]+ times open bracket [0-9]*x plus [0-9]+ close bracket"#

    /// The Algebra question on screen, from what VoiceOver reads for it.
    func readAlgebraQuestion(timeout: TimeInterval = 5) -> AlgebraQuestion? {
        let element = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", Self.algebraLabels)).firstMatch
        guard element.waitForExistence(timeout: timeout), let label = (try? element.snapshot())?.label else {
            return nil
        }
        func coefficient(_ digits: Substring) -> Int { digits.isEmpty ? 1 : Int(digits)! }
        if let match = label.wholeMatch(of: #/x \+ (\d+) = (\d+)/#) {
            let (added, total) = (Int(match.1)!, Int(match.2)!)
            return AlgebraQuestion(kind: .solve, label: label, first: added, second: total - added, multiplier: 1)
        }
        if let match = label.wholeMatch(of: #/(\d*)x \+ (\d*)x/#) {
            return AlgebraQuestion(kind: .simplify, label: label, first: coefficient(match.1),
                                   second: coefficient(match.2), multiplier: 1)
        }
        if let match = label.wholeMatch(of: #/(\d+) times open bracket (\d*)x plus (\d+) close bracket/#) {
            return AlgebraQuestion(kind: .expand, label: label, first: coefficient(match.2), second: Int(match.3)!,
                                   multiplier: Int(match.1)!)
        }
        return nil
    }

    /// Opens Algebra and checks each new kind of question with `check`, answering a kind already checked so that the
    /// next question comes, until all three kinds are checked.
    func forEachKindOfAlgebraQuestion(_ check: (AlgebraQuestion) -> Void) throws {
        launchApp()
        openYear(6)
        openActivity("Algebra")
        var checked: Set<AlgebraQuestion.Kind> = []
        for _ in 1...30 {
            guard let question = readAlgebraQuestion() else {
                return XCTFail("No Algebra question on screen.")
            }
            if checked.contains(question.kind) {
                let start = currentPoints()
                typeAnswer(question.answer)
                pressEnter(expecting: .correct)
                assertPoints(start + 1)
                waitForNextQuestion()
                continue
            }
            check(question)
            checked.insert(question.kind)
            if checked.count == 3 {
                return
            }
        }
        XCTFail("Only \(checked.map(\.rawValue).sorted()) of the three kinds of Algebra question came in 30 questions.")
    }

    // MARK: - Reading a Probability question

    struct ProbabilityQuestion: CustomStringConvertible {
        let label: String
        let wanted: Int
        let all: Int
        /// "faces", "sections", "marbles" or "cards", or nil for a coin.
        let things: String?
        /// What's wanted, said for one and for several: "shows a 4" and "show a 4".
        let wantOne: String
        let wantMany: String
        let flips: Int

        var description: String { "\"\(label)\"" }

        var simplest: (numerator: Int, denominator: Int) {
            var (larger, smaller) = (all, wanted)
            while smaller != 0 {
                (larger, smaller) = (smaller, larger % smaller)
            }
            return (wanted / larger, all / larger)
        }

        var shownNumbers: [Int] {
            label.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        }

        /// "3 twelfths" for 3/12 and "5 over 11" for 5/11, as SpokenMaths reads fractions.
        static func said(_ numerator: Int, _ denominator: Int) -> String {
            let names = [2: ("half", "halves"), 3: ("third", "thirds"), 4: ("quarter", "quarters"), 5: ("fifth", "fifths"),
                         6: ("sixth", "sixths"), 7: ("seventh", "sevenths"), 8: ("eighth", "eighths"),
                         9: ("ninth", "ninths"), 10: ("tenth", "tenths"), 12: ("twelfth", "twelfths")]
            guard let name = names[denominator] else { return "\(numerator) over \(denominator)" }
            return "\(numerator) \(numerator == 1 ? name.0 : name.1)"
        }

        /// The line under "Correct!", as VoiceOver reads it.
        var correctLine: String {
            let lead: String
            if let things {
                lead = "\(wanted) of the \(all) \(things) \(wanted == 1 ? wantOne : wantMany)"
            } else {
                lead = flips == 1 ? "1 of the 2 sides is heads" : "\(flips) flips can land \(all) ways, and 1 of them is heads every time"
            }
            var fraction = Self.said(wanted, all)
            if simplest != (wanted, all) {
                fraction += ", which is the same as \(Self.said(simplest.numerator, simplest.denominator))"
            }
            return "\(lead), so the probability is \(fraction)."
        }

        /// The worked solution's answer, as VoiceOver reads it.
        var workedAnswer: String {
            guard simplest != (wanted, all) else { return "The answer is \(Self.said(wanted, all))." }
            return "The answer is \(Self.said(wanted, all)), or \(Self.said(simplest.numerator, simplest.denominator)) "
                + "in its simplest form."
        }
    }

    /// The Probability question on screen.
    func readProbabilityQuestion(timeout: TimeInterval = 5) -> ProbabilityQuestion? {
        let element = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'What is the probability'")).firstMatch
        guard element.waitForExistence(timeout: timeout), let label = (try? element.snapshot())?.label else {
            return nil
        }
        if let match = label.wholeMatch(of: #/A fair die has (\d+) faces, numbered 1 to \d+\. Each number is equally likely to be rolled\. What is the probability of rolling a (\d+)\?/#) {
            return ProbabilityQuestion(label: label, wanted: 1, all: Int(match.1)!, things: "faces",
                                       wantOne: "shows a \(match.2)", wantMany: "show a \(match.2)", flips: 0)
        }
        if let match = label.wholeMatch(of: #/A spinner has (\d+) equal sections\. (\d+) (?:is|are) blue\. What is the probability of landing on blue\?/#) {
            return ProbabilityQuestion(label: label, wanted: Int(match.2)!, all: Int(match.1)!, things: "sections",
                                       wantOne: "is blue", wantMany: "are blue", flips: 0)
        }
        if let match = label.wholeMatch(of: #/A fair coin is flipped (once|twice|3 times)\. What is the probability of getting heads every time\?/#) {
            let flips = ["once": 1, "twice": 2, "3 times": 3][String(match.1)]!
            return ProbabilityQuestion(label: label, wanted: 1, all: 1 << flips, things: nil, wantOne: "", wantMany: "",
                                       flips: flips)
        }
        if let match = label.wholeMatch(of: #/A bag contains (\d+) marbles\. (\d+) (?:is|are) red\. What is the probability of drawing a red marble\?/#) {
            return ProbabilityQuestion(label: label, wanted: Int(match.2)!, all: Int(match.1)!, things: "marbles",
                                       wantOne: "is red", wantMany: "are red", flips: 0)
        }
        if let match = label.wholeMatch(of: #/A stack of (\d+) cards has (\d+) aces?\. What is the probability of drawing an ace\?/#) {
            return ProbabilityQuestion(label: label, wanted: Int(match.2)!, all: Int(match.1)!, things: "cards",
                                       wantOne: "is an ace", wantMany: "are aces", flips: 0)
        }
        XCTFail("Couldn't read the Probability question \"\(label)\".")
        return nil
    }

    func fractionBox(_ name: String) -> XCUIElement {
        app.textFields.matching(NSPredicate(format: "placeholderValue == %@ OR label == %@", name, name)).firstMatch
    }

    func fillFraction(_ numerator: Int, _ denominator: Int, file: StaticString = #filePath, line: UInt = #line) {
        replaceText(in: fractionBox("Numerator"), with: "\(numerator)", file: file, line: line)
        replaceText(in: fractionBox("Denominator"), with: "\(denominator)", file: file, line: line)
    }
}
