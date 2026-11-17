//
//  Stage9CBatch2Tests.swift
//  Maths QuestTests
//
//  Stage 9C Batch 2, for Year 6 Algebra and Probability: hints, a worked solution after Skip and a line under
//  "Correct!" (B2-1); Solve accepting "12 = x" and "+12" (B2-2); and a right answer written another way (B2-3), or
//  equal to the answer but not fully simplified (B2-4), asked for again rather than marked wrong. Every question
//  both activities can ask is checked: 1,805 for Algebra and 604 for Probability. The answers, messages and
//  mistakes expected are worked out here from each question's numbers, not taken from the app's code. Wrong
//  mathematics must still be marked wrong, and Probability must still accept equal fractions, such as 2/8 for 1/4.
//  The counts of hints and mistakes were worked out separately, by a script written from the design.
//

import Foundation
import Testing
@testable import Maths_Quest

// MARK: - Shared checks, as in Stage9CExplanationTests.swift, where they're private

/// The whole numbers in some words, in order: "4 groups of 5" gives [4, 5].
private func numbers(in words: String) -> [Int] {
    var found: [Int] = []
    var digits = ""
    for character in words + " " {
        if character.isASCII, character.isNumber {
            digits.append(character)
        } else if !digits.isEmpty {
            found.append(Int(digits)!)
            digits = ""
        }
    }
    return found
}

/// What VoiceOver hears, with the counting words it says turned back into the numbers shown.
private func spokenNumbersAsShown(_ spoken: String) -> [Int] {
    var words = spoken
    for (word, number) in [("twos", "2"), ("fives", "5"), ("tens", "10"), ("two", "2"), ("five", "5"), ("ten", "10")] {
        words = words.replacingOccurrences(of: "\\b\(word)\\b", with: number, options: .regularExpression)
    }
    return numbers(in: words)
}

/// The words the proposal says never to use.
private let bannedWords = ["carry", "borrow", "just", "easy", "simply", "obviously"]

private func bannedWordsUsed(in words: String) -> [String] {
    bannedWords.filter {
        words.range(of: "\\b\($0)\\b", options: [.regularExpression, .caseInsensitive]) != nil
    }
}

/// Sentences, counted by the full stops, question marks and exclamation marks that end them.
private func sentences(in words: String) -> Int {
    var count = 0
    let characters = Array(words)
    for (index, character) in characters.enumerated() where ".?!".contains(character) {
        if index + 1 == characters.count || characters[index + 1] == " " {
            count += 1
        }
    }
    return count
}

/// Failures found in a long loop, reported together at the end.
private struct Problems {
    private(set) var found: [String] = []

    mutating func check(_ condition: Bool, _ message: @autoclosure () -> String) {
        if !condition {
            found.append(message())
        }
    }

    var summary: Comment {
        Comment(rawValue: "\(found.count) problem(s), the first: " + found.prefix(10).joined(separator: " | "))
    }
}

/// The highest common factor, found by trying every number from the smaller one down.
private func highestCommonFactorByTrying(_ a: Int, _ b: Int) -> Int {
    stride(from: min(a, b), through: 1, by: -1).first { a % $0 == 0 && b % $0 == 0 } ?? 1
}

/// Digits only, as a child types a whole number: "12" is 12, but "-2", "1.5" and "" are nothing.
private func typedWholeNumber(_ typed: String) -> Int? {
    !typed.isEmpty && typed.allSatisfy { $0.isASCII && $0.isNumber } ? Int(typed) : nil
}

/// The shown words with each fraction, such as "1/2", as VoiceOver says it, "1 half", so that the numbers can be
/// compared with the spoken words. Fractions are read by `SpokenMaths`, tested in earlier stages.
private func fractionsSaid(_ text: String) -> String {
    let fraction = try! Regex(#"(\d+)/(\d+)"#, as: (Substring, Substring, Substring).self)
    var said = text
    while let match = said.firstMatch(of: fraction) {
        said.replaceSubrange(match.range, with: SpokenMaths.fraction(numerator: Int(match.1)!, denominator: Int(match.2)!))
    }
    return said
}

/// Nothing banned, no sign read aloud as a sign, the same numbers spoken as shown, and not too long. For Algebra,
/// "+" and "−" must be said too, as "plus" and "minus".
private func checkWording(_ words: SpokenText, maximumSentences: Int, readsFractions: Bool = false,
                          algebra: Bool = false, into problems: inout Problems) {
    problems.check(bannedWordsUsed(in: words.text).isEmpty && bannedWordsUsed(in: words.spoken).isEmpty,
                   "Banned word: \(words.text)")
    let signs = algebra ? "×÷=/+−" : "×÷=/"
    problems.check(!words.spoken.contains { signs.contains($0) }, "A sign read aloud: \(words.spoken)")
    let shown = readsFractions ? fractionsSaid(words.text) : words.text
    problems.check(spokenNumbersAsShown(words.spoken) == spokenNumbersAsShown(shown),
                   "Spoken numbers differ: \(words.text) / \(words.spoken)")
    let count = sentences(in: words.text)
    problems.check(count >= 1 && count <= maximumSentences, "\(count) sentences: \(words.text)")
}

// MARK: - Every question

private enum AlgebraQuestions {
    /// Both numbers, 1 to 19.
    static var pairs: [(Int, Int)] {
        (1...19).flatMap { first in (1...19).map { (first, $0) } }
    }

    /// The multiplier isn't used by Solve or Simplify.
    static var solve: [Year6AlgebraQuestion] {
        pairs.map { Year6AlgebraQuestion(kind: .solve, first: $0.0, second: $0.1, multiplier: 2) }
    }

    static var simplify: [Year6AlgebraQuestion] {
        pairs.map { Year6AlgebraQuestion(kind: .simplify, first: $0.0, second: $0.1, multiplier: 2) }
    }

    static func expand(_ multiplier: Int) -> [Year6AlgebraQuestion] {
        pairs.map { Year6AlgebraQuestion(kind: .expand, first: $0.0, second: $0.1, multiplier: multiplier) }
    }

    static var all: [Year6AlgebraQuestion] {
        solve + simplify + (2...4).flatMap(expand)
    }

    /// "x" for 1 lot of x, "7x" for 7.
    static func term(_ coefficient: Int) -> String {
        coefficient == 1 ? "x" : "\(coefficient)x"
    }

    /// The x term the messages use as an example, never the answer's own: 2x, or 3x when the answer has 2x.
    static func example(_ answerCoefficient: Int) -> Int {
        answerCoefficient == 2 ? 3 : 2
    }
}

private enum ProbabilityQuestions {
    static var all: [Year6ProbabilityQuestion] {
        let dice = (4...10).flatMap { faces in (1...faces).map { Year6ProbabilityQuestion.die(faces: faces, target: $0) } }
        let counted = (5...20).flatMap { total in
            (1..<total).flatMap { selected -> [Year6ProbabilityQuestion] in
                [.spinner(sections: total, blue: selected), .marbles(total: total, red: selected),
                 .cards(total: total, aces: selected)]
            }
        }
        let coins = (1...3).map { Year6ProbabilityQuestion.coin(flips: $0) }
        return dice + counted + coins
    }

    /// The ways wanted and all the equally likely ways, counted here: 2 × 2 × … for the coin flips.
    static func chance(_ question: Year6ProbabilityQuestion) -> (wanted: Int, all: Int) {
        switch question {
        case let .die(faces, _): return (1, faces)
        case let .spinner(sections, blue): return (blue, sections)
        case let .coin(flips): return (1, (0..<flips).reduce(1) { product, _ in product * 2 })
        case let .marbles(total, red): return (red, total)
        case let .cards(total, aces): return (aces, total)
        }
    }

    /// What's counted, and the words for the ones wanted: "sections" and "are blue".
    static func counted(_ question: Year6ProbabilityQuestion) -> (things: String, want: String) {
        let one = chance(question).wanted == 1
        switch question {
        case let .die(_, target): return ("faces", "shows a \(target)")
        case .spinner: return ("sections", one ? "is blue" : "are blue")
        case .marbles: return ("marbles", one ? "is red" : "are red")
        case .cards: return ("cards", one ? "is an ace" : "are aces")
        case .coin: return ("", "")
        }
    }

    /// The mistake a wrong fraction shows, worked out from the design, checked in the design's order.
    static func mistake(_ question: Year6ProbabilityQuestion, top: Int, bottom: Int) -> Year6ProbabilityQuestion.Mistake? {
        let (wanted, all) = chance(question)
        func equals(_ numerator: Int, _ denominator: Int) -> Bool {
            denominator > 0 && top * denominator == numerator * bottom
        }
        if bottom <= 0 || equals(wanted, all) { return nil }
        if wanted != all && equals(all, wanted) { return .upsideDown }
        if top > bottom { return .moreThanOne }
        if top == 0 { return .zero }
        if top == bottom { return .certain }
        if equals(all - wanted, all) { return .complement }
        if equals(wanted, all - wanted) { return .odds }
        if case let .coin(flips) = question {
            if flips >= 2 && equals(1, 2) { return .oneFlip }
            if flips >= 3 && equals(1, 2 * flips) { return .flipsTimesTwo }
        }
        if case let .die(faces, target) = question, target != 1, equals(target, faces) { return .faceNumber }
        return nil
    }
}

@Suite("Stage 9C Batch 2: the questions checked are every question asked")
struct Stage9CBatch2QuestionTests {
    @Test func algebraQuestionsAreAllChecked() {
        #expect(AlgebraQuestions.all.count == 1_805)
        var generator = SeededGenerator(seed: 0x9C_B2_01)
        var kinds = Set<String>()
        var outOfRange: [String] = []
        for _ in 0..<3_000 {
            let question = Year6AlgebraQuestion.random(using: &generator)
            kinds.insert(String(describing: question.kind))
            if !(1...19).contains(question.first) || !(1...19).contains(question.second)
                || !(2...4).contains(question.multiplier) {
                outOfRange.append(question.expression)
            }
        }
        #expect(outOfRange.isEmpty, "\(outOfRange.prefix(5))")
        #expect(kinds == ["solve", "simplify", "expand"])
    }

    @Test func probabilityQuestionsAreAllChecked() {
        let all = ProbabilityQuestions.all
        #expect(all.count == 604)
        var generator = SeededGenerator(seed: 0x9C_B2_02)
        var notListed: [String] = []
        for _ in 0..<3_000 {
            let question = Year6ProbabilityQuestion.random(using: &generator)
            if !all.contains(question) {
                notListed.append(question.text)
            }
        }
        #expect(notListed.isEmpty, "\(notListed.prefix(3))")
    }
}

// MARK: - B2-2: Solve

@Suite("Stage 9C Batch 2: Solve accepts x on either side of the equals sign (B2-2)")
struct Stage9CBatch2SolveAcceptanceTests {
    /// The Solve checker before Batch 2, written again here: small letters, no spaces, an "x=" in front taken off,
    /// then a whole number equal to x.
    private func outcomeBefore(_ question: Year6AlgebraQuestion, _ text: String) -> Year6AlgebraQuestion.Outcome {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .unanswered }
        var typed = text.lowercased().filter { !$0.isWhitespace }
        if typed.hasPrefix("x=") {
            typed.removeFirst(2)
        }
        return typedWholeNumber(typed) == question.second ? .correct : .incorrect
    }

    @Test func theAnswerIsAcceptedWrittenEitherWay() {
        var problems = Problems()
        var accepted = 0
        for question in AlgebraQuestions.solve {
            let s = question.second
            let before = ["\(s)", " \(s) ", "x=\(s)", "X = \(s)", "0\(s)"]
            let added = ["\(s) = x", "\(s)=x", "+\(s)", "x = +\(s)", "+\(s) = x", "\(s) = X"]
            for typed in before + added {
                problems.check(question.evaluate(typed) == .correct, "\(question.expression): \(typed) not accepted")
                problems.check(question.askedAgain(typed) == nil, "\(question.expression): \(typed) asked again")
                accepted += 1
            }
            for typed in before {
                problems.check(outcomeBefore(question, typed) == .correct, "Old checker: \(typed)")
            }
            for typed in ["", "   "] {
                problems.check(question.evaluate(typed) == .unanswered && question.askedAgain(typed) == nil, "Blank")
            }
        }
        #expect(problems.found.isEmpty, problems.summary)
        #expect(accepted == 361 * 11)
    }

    @Test func aWrongValueIsNeverAccepted() {
        var problems = Problems()
        for question in AlgebraQuestions.solve {
            for value in 0...60 where value != question.second {
                for typed in ["\(value)", "\(value) = x", "+\(value)", "x = +\(value)", "x = \(value)"] {
                    problems.check(question.evaluate(typed) == .incorrect, "\(question.expression): \(typed)")
                }
            }
        }
        #expect(problems.found.isEmpty, problems.summary)
    }

    /// Everything else is marked as it was before Batch 2.
    @Test func otherTypingIsMarkedAsBefore() {
        var problems = Problems()
        for question in AlgebraQuestions.solve {
            let s = question.second
            let typings = ["x=\(s)=x", "=x", "x=", "x", "\(s)=x=x", "++\(s)", "+-\(s)", "-\(s)", "−\(s)", "\(s)x",
                           "x=x", "1 2", "x=1=2", "\(s).5", "\(s).0", "x = \(question.first + s)", "99999999999999999999"]
            for typed in typings {
                problems.check(question.evaluate(typed) == outcomeBefore(question, typed), "\(question.expression): \(typed)")
            }
        }
        #expect(problems.found.isEmpty, problems.summary)
    }
}

// MARK: - B2-3 and B2-4: asked for again

private enum Wording {
    static let equal = "That's equal, but it needs simplifying further."
    static let workItOut = SpokenText("Work it out, so x is a single number.")
    static let solveDecimal = AskedAgainMessage(message: SpokenText("Write x as a whole number, without a decimal point."))
    static let decimals = AskedAgainMessage(message: SpokenText("Write each number as a whole number, without a decimal point."))

    static func times(_ example: Int) -> AskedAgainMessage {
        AskedAgainMessage(message: SpokenText("In algebra, leave out the × sign. Write \(example)x, not \(example) × x.",
                                              spoken: "In algebra, leave out the times sign. Write \(example)x, not \(example) times x."))
    }

    static func numberFirst(_ example: Int) -> AskedAgainMessage {
        AskedAgainMessage(message: SpokenText("In algebra, write the number before the x, like \(example)x."))
    }
}

@Suite("Stage 9C Batch 2: a right answer written another way is asked for again (B2-3, B2-4)")
struct Stage9CBatch2AskedAgainTests {
    /// Each answer typed, and the message expected: nil where it must be marked as usual.
    private func check(_ question: Year6AlgebraQuestion, askedAgain: [(String, AskedAgainMessage)], marked: [String],
                       into problems: inout Problems) {
        for (typed, expected) in askedAgain {
            problems.check(question.evaluate(typed) == .incorrect, "\(question.expression): \(typed) isn't wrong as written")
            let found = question.askedAgain(typed)
            problems.check(found == expected, "\(question.expression): \(typed) gave \(String(describing: found?.message.text))")
            if let found {
                checkWording(found.message, maximumSentences: 2, algebra: true, into: &problems)
                if let detail = found.detail {
                    checkWording(detail, maximumSentences: 1, algebra: true, into: &problems)
                }
            }
        }
        for typed in marked {
            problems.check(question.evaluate(typed) == .incorrect, "\(question.expression): \(typed) not marked wrong")
            problems.check(question.askedAgain(typed) == nil, "\(question.expression): \(typed) asked again")
        }
    }

    @Test func solve() {
        var problems = Problems()
        for question in AlgebraQuestions.solve {
            let (f, s) = (question.first, question.second)
            let t = f + s
            let sum = AskedAgainMessage(message: SpokenText(Wording.equal), detail: Wording.workItOut)
            let questionBack = AskedAgainMessage(message: SpokenText("That's the question. Work out what x is."),
                                                 detail: SpokenText("Take \(f) away from both sides, so x is on its own."))
            let trueEquation = AskedAgainMessage(message: SpokenText("That's true, but it needs simplifying further."),
                                                 detail: Wording.workItOut)
            let askedAgain: [(String, AskedAgainMessage)] = [
                ("\(s).0", Wording.solveDecimal), ("\(s).", Wording.solveDecimal), ("x = \(s).0", Wording.solveDecimal),
                ("+\(s).0", Wording.solveDecimal), ("\(s).00 = x", Wording.solveDecimal),
                ("\(t) − \(f)", sum), ("\(t)-\(f)", sum), ("\(s) + 0", sum), ("x = \(t) - \(f)", sum), ("\(t) - \(f) = x", sum),
                ("x + \(f) = \(t)", questionBack), ("\(f) + x = \(t)", questionBack), ("\(t) = x + \(f)", questionBack),
                ("2x = \(2 * s)", trueEquation), ("x + \(f + 1) = \(t + 1)", trueEquation), ("x - \(s) = 0", trueEquation),
            ]
            let marked = ["x = \(t) + \(f)", "x + \(f) = \(t + 1)", "2x = \(2 * s + 1)", "x = x", "0 = 0", "\(s) = \(s)",
                          "x = \(s) = x", "-\(s)", "\(s).5", "\(s + 1).0", "0.\(s)", "\(s).0.0", "\(t) + \(f)", "\(t)",
                          "x = \(t)", "\(s) - 0.5"]
            check(question, askedAgain: askedAgain, marked: marked, into: &problems)
        }
        #expect(problems.found.isEmpty, problems.summary)
    }

    @Test func simplify() {
        var problems = Problems()
        let term = AlgebraQuestions.term
        for question in AlgebraQuestions.simplify {
            let (f, s) = (question.first, question.second)
            let k = f + s
            let example = AlgebraQuestions.example(k)
            let questionBack = AskedAgainMessage(message: SpokenText("That's the question. It needs simplifying."),
                                                 detail: SpokenText("Put the x terms together into one x term."))
            let equal = AskedAgainMessage(message: SpokenText(Wording.equal),
                                          detail: SpokenText("Write it as one x term, like \(example)x."))
            let askedAgain: [(String, AskedAgainMessage)] = [
                ("\(k) × x", Wording.times(example)), ("\(k)*x", Wording.times(example)), ("\(k)·x", Wording.times(example)),
                ("\(k).0x", Wording.decimals), ("\(k).x", Wording.decimals), ("x\(k)", Wording.numberFirst(example)),
                ("\(term(f)) + \(term(s))", questionBack), ("\(term(s))+\(term(f))", questionBack),
                ("\(k)x + 0", equal), ("\(k + 1)x - x", equal), ("(\(f) + \(s))x", equal), ("\(f)x + \(s)x", questionBack),
            ]
            // "1x + 12x" is the question typed back only when neither number is 1.
            let fixedAskedAgain = askedAgain.map { typed, message in
                typed == "\(f)x + \(s)x" && (f == 1 || s == 1) ? (typed, equal) : (typed, message)
            }
            var marked = ["\(k)x²", "\(k)x^2", "\(k)x2", "\(k + 1)x", "\(k - 1)x", "\(k)", "\(k)x + 1", "\(f)x × \(s)x",
                          "\(k + 1) × x", "\(k) × x + 1", "x\(k + 1)", "\(k).5x", "x\(f) + x\(s)", "\(k)y", "-\(k)x"]
            if f * s != k {
                marked.append("\(f * s)x")
            }
            check(question, askedAgain: fixedAskedAgain, marked: marked, into: &problems)
        }
        #expect(problems.found.isEmpty, problems.summary)
    }

    @Test(arguments: [2, 3, 4])
    func expand(multiplier m: Int) {
        var problems = Problems()
        let term = AlgebraQuestions.term
        for question in AlgebraQuestions.expand(m) {
            let (f, s) = (question.first, question.second)
            let (a, b) = (m * f, m * s)
            let example = AlgebraQuestions.example(a)
            let typedBack = "\(m)(\(term(f)) + \(s))"
            let questionBack = AskedAgainMessage(message: SpokenText("That's the question. It needs expanding."),
                                                 detail: SpokenText("Multiply each part inside the bracket by \(m)."))
            let equal = AskedAgainMessage(message: SpokenText(Wording.equal),
                                          detail: SpokenText("Write it as an x term plus a number, like 2x + 3.",
                                                             spoken: "Write it as an x term plus a number, like 2x plus 3."))
            let askedAgain: [(String, AskedAgainMessage)] = [
                ("\(a) × x + \(b)", Wording.times(example)), ("\(a)*x + \(b)", Wording.times(example)),
                ("\(a).0x + \(b)", Wording.decimals), ("\(a)x + \(b).0", Wording.decimals),
                ("x\(a) + \(b)", Wording.numberFirst(example)), ("\(b) + x\(a)", Wording.numberFirst(example)),
                (typedBack, questionBack), (typedBack.replacingOccurrences(of: " ", with: ""), questionBack),
                ("\(m) × \(term(f)) + \(m) × \(s)", equal), ("\(a)x + \(b) + 0", equal), ("\(a)x + \(b + 1) - 1", equal),
            ]
            let marked = ["\(a)x + \(b + 1)", "\(a + 1)x + \(b)", "\(a)x", "\(b)", "\(a)x - \(b)", "\(m)(\(term(f)) + \(s + 1))",
                          "\(a + 1) × x + \(b)", "\(m) × \(term(f)) + \(m) × \(s + 1)", "\(a)x\(b)", "\(a).5x + \(b)",
                          "\(term(f)) + \(s)", "\(a + b)x", "\(m)\(term(f)) + \(s)"]
            check(question, askedAgain: askedAgain, marked: marked, into: &problems)
            for typed in ["\(a)x + \(b)", "\(b) + \(a)x", "\(a)x+\(b)", "+\(a)x + \(b)"] {
                problems.check(question.evaluate(typed) == .correct && question.askedAgain(typed) == nil,
                               "\(question.expression): \(typed) not accepted")
            }
        }
        #expect(problems.found.isEmpty, problems.summary)
    }

    @Test func rightAnswersAreNeverAskedAgain() {
        var problems = Problems()
        for question in AlgebraQuestions.simplify {
            let k = question.first + question.second
            for typed in ["\(k)x", "+\(k)x", " \(k)X "] {
                problems.check(question.evaluate(typed) == .correct && question.askedAgain(typed) == nil, "\(typed)")
            }
        }
        for question in AlgebraQuestions.all {
            for typed in ["", "   "] {
                problems.check(question.evaluate(typed) == .unanswered && question.askedAgain(typed) == nil, "Blank")
            }
        }
        #expect(problems.found.isEmpty, problems.summary)
    }
}

// MARK: - B2-1: hints

/// The checks on every different hint a question gives: the wording, and no number the question doesn't show, so a
/// hint never gives the answer away.
private func checkAlgebraHint(_ question: Year6AlgebraQuestion, _ hint: SpokenText, checked: inout Set<String>,
                              into problems: inout Problems) {
    guard checked.insert(hint.text).inserted else { return }
    checkWording(hint, maximumSentences: 3, algebra: true, into: &problems)
    let shown = Set(numbers(in: question.expression)).union([1])
    problems.check(Set(numbers(in: hint.text)).isSubset(of: shown), "\(question.expression): hint \(hint.text)")
}

@Suite("Stage 9C Batch 2: Algebra hints point at the mistake, and wrong answers stay wrong (B2-1)")
struct Stage9CBatch2AlgebraHintTests {
    /// Every wrong answer here must be marked wrong, never asked for again.
    private func checkMarkedWrong(_ question: Year6AlgebraQuestion, _ typed: String, into problems: inout Problems) {
        problems.check(question.evaluate(typed) == .incorrect, "\(question.expression): \(typed) not wrong")
        problems.check(question.askedAgain(typed) == nil, "\(question.expression): \(typed) asked again")
    }

    @Test func solve() {
        var problems = Problems()
        var counts: [String: Int] = [:]
        var hints = 0
        for question in AlgebraQuestions.solve {
            let (f, s) = (question.first, question.second)
            let t = f + s
            var checked = Set<String>()
            let typings = (0...60).filter { $0 != s }.map(String.init) + ["abc", "x = x", "-\(s)", "\(s).5", "1/2"]
            for typed in typings {
                hints += 1
                checkMarkedWrong(question, typed, into: &problems)
                let value = typedWholeNumber(typed)
                let expected: Year6AlgebraQuestion.Mistake? = value == t ? .total
                    : value == f + t ? .added : value == f ? .numberAdded : nil
                let found = question.mistake(in: typed)
                problems.check(found == expected, "\(question.expression): \(typed) gave \(String(describing: found))")
                if let found {
                    counts[String(describing: found), default: 0] += 1
                }
                checkAlgebraHint(question, question.hint(after: typed), checked: &checked, into: &problems)
            }
        }
        #expect(problems.found.isEmpty, problems.summary)
        #expect(hints == 23_465)
        #expect(counts == ["total": 361, "added": 361, "numberAdded": 342])
    }

    @Test func simplify() {
        var problems = Problems()
        var counts: [String: Int] = [:]
        var hints = 0
        for question in AlgebraQuestions.simplify {
            let (f, s) = (question.first, question.second)
            let k = f + s
            var checked = Set<String>()
            var typings: [(String, Year6AlgebraQuestion.Mistake?)] = []
            for c in 0...45 where c != k {
                typings.append(("\(c)x", c == f * s ? .multiplied : nil))
            }
            for c in 0...45 {
                typings.append(("\(c)", c == k ? .missingX : nil))
            }
            typings += [("\(k)x²", .squared), ("\(k)x^2", .squared), ("\(k)x2", .squared), ("abc", nil), ("\(k)y", nil),
                        ("\(k)x + 1", nil)]
            for (typed, expected) in typings {
                hints += 1
                checkMarkedWrong(question, typed, into: &problems)
                let found = question.mistake(in: typed)
                problems.check(found == expected, "\(question.expression): \(typed) gave \(String(describing: found))")
                if let found {
                    counts[String(describing: found), default: 0] += 1
                }
                checkAlgebraHint(question, question.hint(after: typed), checked: &checked, into: &problems)
            }
        }
        #expect(problems.found.isEmpty, problems.summary)
        #expect(hints == 35_017)
        #expect(counts == ["multiplied": 123, "missingX": 361, "squared": 1_083])
    }

    @Test(arguments: [2, 3, 4])
    func expand(multiplier m: Int) {
        var problems = Problems()
        var counts: [String: Int] = [:]
        var hints = 0
        for question in AlgebraQuestions.expand(m) {
            let (f, s) = (question.first, question.second)
            let (a, b) = (m * f, m * s)
            var checked = Set<String>()
            func expected(_ c: Int, _ d: Int) -> Year6AlgebraQuestion.Mistake? {
                switch (c, d) {
                case (a, b): return nil
                case (m * f, s): return .onlyFirst
                case (f, m * s): return .onlyNumber
                case (f, s): return .notMultiplied
                case (f + m, s + m): return .addedMultiplier
                case (m * (f + s), 0), (0, m * (f + s)): return .combined
                default: return nil
                }
            }
            var typings: [(String, Year6AlgebraQuestion.Mistake?)] = []
            for c in 0...(a + 3) {
                for d in 0...(b + 3) where (c, d) != (a, b) {
                    typings.append(("\(c)x + \(d)", expected(c, d)))
                }
            }
            typings += [("abc", nil), ("\(a)x", expected(a, 0)), ("\(b)", expected(0, b)), ("\(a + b)x", expected(a + b, 0)),
                        ("\(a + b)", expected(0, a + b))]
            for (typed, expected) in typings {
                hints += 1
                checkMarkedWrong(question, typed, into: &problems)
                let found = question.mistake(in: typed)
                problems.check(found == expected, "\(question.expression): \(typed) gave \(String(describing: found))")
                if let found {
                    counts[String(describing: found), default: 0] += 1
                }
                checkAlgebraHint(question, question.hint(after: typed), checked: &checked, into: &problems)
            }
        }
        let expectedCounts: (hints: Int, mistakes: [String: Int]) = switch m {
        case 2: (209_380, ["addedMultiplier": 360, "combined": 760, "notMultiplied": 361, "onlyFirst": 361, "onlyNumber": 361])
        case 3: (418_760, ["addedMultiplier": 361, "combined": 760, "notMultiplied": 361, "onlyFirst": 361, "onlyNumber": 361])
        default: (700_340, ["addedMultiplier": 361, "combined": 722, "notMultiplied": 361, "onlyFirst": 361, "onlyNumber": 361])
        }
        #expect(problems.found.isEmpty, problems.summary)
        #expect(hints == expectedCounts.hints)
        #expect(counts == expectedCounts.mistakes)
    }
}

@Suite("Stage 9C Batch 2: Probability hints point at the mistake (B2-1)")
struct Stage9CBatch2ProbabilityHintTests {
    @Test func everyWrongFraction() {
        var problems = Problems()
        var counts: [String: Int] = [:]
        var hints = 0
        for question in ProbabilityQuestions.all {
            let (wanted, all) = ProbabilityQuestions.chance(question)
            let shown = Set(numbers(in: question.text)).union([0, 1, 2])
            var checked = Set<String>()
            for top in 0...25 {
                for bottom in 1...25 where top * all != wanted * bottom {
                    hints += 1
                    let response = (numerator: "\(top)", denominator: "\(bottom)")
                    problems.check(question.evaluate(numerator: response.numerator, denominator: response.denominator) == .incorrect,
                                   "\(question.text) \(top)/\(bottom) not wrong")
                    let expected = ProbabilityQuestions.mistake(question, top: top, bottom: bottom)
                    let found = question.mistake(top: top, bottom: bottom)
                    problems.check(found == expected, "\(question.text) \(top)/\(bottom) gave \(String(describing: found))")
                    if let found {
                        counts[String(describing: found), default: 0] += 1
                    }
                    let hint = question.hint(after: response)
                    guard checked.insert(hint.text).inserted else { continue }
                    checkWording(hint, maximumSentences: 3, readsFractions: true, into: &problems)
                    problems.check(Set(numbers(in: hint.text)).isSubset(of: shown), "\(question.text): hint \(hint.text)")
                    let fraction = try! Regex(#"(\d+)/(\d+)"#, as: (Substring, Substring, Substring).self)
                    for match in hint.text.matches(of: fraction) {
                        problems.check(Int(match.1)! * all != wanted * Int(match.2)!, "Answer in hint: \(hint.text)")
                    }
                }
            }
            // A fraction typed into one box, or a number that isn't whole, gets the way to work it out.
            for response in [(numerator: "1/2", denominator: ""), (numerator: "1.5", denominator: "4"),
                             (numerator: "-1", denominator: "4")] {
                let hint = question.hint(after: response)
                problems.check(!hint.text.isEmpty && Set(numbers(in: hint.text)).isSubset(of: shown), "\(hint.text)")
            }
        }
        #expect(problems.found.isEmpty, problems.summary)
        #expect(hints == 390_809)
        #expect(counts == ["certain": 15_100, "complement": 1_491, "faceNumber": 152, "flipsTimesTwo": 4,
                           "moreThanOne": 179_409, "odds": 1_177, "oneFlip": 24, "upsideDown": 1_791, "zero": 15_100])
    }
}

// MARK: - B2-1: worked solutions and the line under "Correct!"

@Suite("Stage 9C Batch 2: worked solutions and Correct! lines are right for every question (B2-1)")
struct Stage9CBatch2WorkedSolutionTests {
    @Test func algebra() throws {
        let arithmetic = try Regex(#"(\d+) ([+−×]) (\d+) = (\d+)"#,
                                   as: (Substring, Substring, Substring, Substring, Substring).self)
        let timesTerm = try Regex(#"(\d+) × (\d*)x = (\d+)x"#, as: (Substring, Substring, Substring, Substring).self)
        let term = AlgebraQuestions.term
        var problems = Problems()
        for question in AlgebraQuestions.all {
            let (f, s, m) = (question.first, question.second, question.multiplier)
            let answer: (text: String, spoken: String)
            let line: SpokenText
            let equationsShown: Int
            switch question.kind {
            case .solve:
                answer = ("x = \(s)", "x equals \(s)")
                line = SpokenText("x = \(s), because \(s) + \(f) = \(f + s)",
                                  spoken: "x equals \(s), because \(s) plus \(f) equals \(f + s)")
                equationsShown = 2
            case .simplify:
                answer = ("\(f + s)x", "\(f + s)x")
                line = SpokenText("\(term(f)) + \(term(s)) = \(f + s)x",
                                  spoken: "\(term(f)) plus \(term(s)) equals \(f + s)x")
                equationsShown = 1
            case .expand:
                answer = ("\(m * f)x + \(m * s)", "\(m * f)x plus \(m * s)")
                line = SpokenText("\(m)(\(term(f)) + \(s)) = \(m * f)x + \(m * s)",
                                  spoken: "\(m) times open bracket \(term(f)) plus \(s) close bracket equals \(m * f)x plus \(m * s)")
                equationsShown = 2
            }
            let solution = question.workedSolution
            problems.check(solution.answer == SpokenText("The answer is \(answer.text).", spoken: "The answer is \(answer.spoken)."),
                           "\(question.expression): \(solution.answer.text) / \(solution.answer.spoken)")
            problems.check(question.evaluate(answer.text) == .correct, "\(question.expression): \(answer.text) not accepted")
            problems.check(question.correctLine == line, "\(question.expression): \(question.correctLine.text)")
            checkWording(solution.answer, maximumSentences: 1, algebra: true, into: &problems)
            var equations = 0
            for step in solution.steps {
                checkWording(step, maximumSentences: 2, algebra: true, into: &problems)
                for match in step.text.matches(of: arithmetic) {
                    equations += 1
                    let (left, right, result) = (Int(match.1)!, Int(match.3)!, Int(match.4)!)
                    let value = match.2 == "+" ? left + right : match.2 == "−" ? left - right : left * right
                    problems.check(value == result, "\(question.expression): \(step.text)")
                }
                for match in step.text.matches(of: timesTerm) {
                    equations += 1
                    let times = match.2.isEmpty ? 1 : Int(match.2)!
                    problems.check(Int(match.1)! * times == Int(match.3)!, "\(question.expression): \(step.text)")
                }
            }
            problems.check(equations == equationsShown, "\(question.expression): \(equations) equations")
        }
        #expect(problems.found.isEmpty, problems.summary)
    }

    @Test func probability() throws {
        let coinWays = try Regex(#"Each flip can land 2 ways, so (\d+) flips can land ((?:2 × )+2) = (\d+) ways: (.+)\."#,
                                 as: (Substring, Substring, Substring, Substring, Substring).self)
        let said = SpokenMaths.fraction(numerator:denominator:)
        var problems = Problems()
        for question in ProbabilityQuestions.all {
            let (wanted, all) = ProbabilityQuestions.chance(question)
            let divisor = highestCommonFactorByTrying(wanted, all)
            let (top, bottom) = (wanted / divisor, all / divisor)
            let solution = question.workedSolution
            let answer = divisor == 1
                ? SpokenText("The answer is \(wanted)/\(all).", spoken: "The answer is \(said(wanted, all)).")
                : SpokenText("The answer is \(wanted)/\(all), or \(top)/\(bottom) in its simplest form.",
                             spoken: "The answer is \(said(wanted, all)), or \(said(top, bottom)) in its simplest form.")
            problems.check(solution.answer == answer, "\(question.text): \(solution.answer.text)")
            problems.check(question.evaluate(numerator: "\(wanted)", denominator: "\(all)") == .correct
                               && question.evaluate(numerator: "\(top)", denominator: "\(bottom)") == .correct,
                           "\(question.text): the answer isn't accepted")
            checkWording(solution.answer, maximumSentences: 1, readsFractions: true, into: &problems)

            let (things, want) = ProbabilityQuestions.counted(question)
            let lead: String
            switch question {
            case .coin(flips: 1):
                lead = "1 of the 2 sides is heads"
                problems.check(solution.steps == [SpokenText("A coin can land 2 ways, heads or tails, and both are equally likely."),
                                                  SpokenText("1 of them is heads.")], "One flip: \(solution.steps.map(\.text))")
            case let .coin(flips):
                lead = "\(flips) flips can land \(all) ways, and 1 of them is heads every time"
                let allHeads = String(repeating: "H", count: flips)
                problems.check(solution.steps.count == 2, "\(flips) flips: \(solution.steps.count) steps")
                if let match = solution.steps.first?.text.wholeMatch(of: coinWays) {
                    let twos = match.2.components(separatedBy: " × ")
                    problems.check(Int(match.1) == flips && twos.count == flips && Int(match.3) == all, "\(match.0)")
                    let ways = match.4.replacingOccurrences(of: " and ", with: ", ").components(separatedBy: ", ")
                    problems.check(ways.count == all && Set(ways).count == all
                                       && ways.allSatisfy { $0.count == flips && $0.allSatisfy { "HT".contains($0) } },
                                   "Ways: \(ways)")
                } else {
                    problems.check(false, "\(flips) flips: \(solution.steps.first?.text ?? "no steps")")
                }
                let heads = Array(repeating: "heads", count: flips).joined(separator: " ")
                problems.check(solution.steps.last == SpokenText("Only \(allHeads) is heads every time.",
                                                                 spoken: "Only \(heads) is heads every time."),
                               "\(solution.steps.last?.text ?? "")")
            default:
                lead = "\(wanted) of the \(all) \(things) \(want)"
                var steps = [SpokenText("There are \(all) \(things), and each is equally likely."),
                             SpokenText("\(wanted) of them \(want)."),
                             SpokenText("So the probability is \(wanted) out of \(all), which is \(wanted)/\(all).",
                                        spoken: "So the probability is \(wanted) out of \(all), which is \(said(wanted, all)).")]
                if divisor > 1 {
                    steps.append(SpokenText("\(wanted)/\(all) simplifies to \(top)/\(bottom), dividing both numbers by \(divisor).",
                                            spoken: "\(said(wanted, all)) simplifies to \(said(top, bottom)), "
                                                + "dividing both numbers by \(divisor)."))
                }
                problems.check(solution.steps == steps, "\(question.text): \(solution.steps.map(\.text))")
            }
            for step in solution.steps {
                checkWording(step, maximumSentences: 2, readsFractions: true, into: &problems)
            }

            let fraction = divisor == 1 ? "\(wanted)/\(all)" : "\(wanted)/\(all) = \(top)/\(bottom)"
            let spokenFraction = divisor == 1 ? said(wanted, all) : "\(said(wanted, all)), which is the same as \(said(top, bottom))"
            problems.check(question.correctLine == SpokenText("\(lead), so the probability is \(fraction).",
                                                              spoken: "\(lead), so the probability is \(spokenFraction)."),
                           "\(question.text): \(question.correctLine.text)")
            checkWording(question.correctLine, maximumSentences: 1, readsFractions: true, into: &problems)
        }
        #expect(problems.found.isEmpty, problems.summary)
    }
}

// MARK: - Probability marking, unchanged

@Suite("Stage 9C Batch 2: Probability still accepts every equal fraction")
struct Stage9CBatch2ProbabilityMarkingTests {
    @Test func everyFractionUpTo25() {
        var problems = Problems()
        var correct = 0
        for question in ProbabilityQuestions.all {
            let (wanted, all) = ProbabilityQuestions.chance(question)
            for top in 0...25 {
                for bottom in 0...25 {
                    let expected: Year6ProbabilityQuestion.Outcome = bottom == 0 ? .invalidInput
                        : top * all == wanted * bottom ? .correct : .incorrect
                    if expected == .correct { correct += 1 }
                    problems.check(question.evaluate(numerator: "\(top)", denominator: "\(bottom)") == expected,
                                   "\(question.text) \(top)/\(bottom)")
                }
            }
            for (top, bottom, expected) in [("", "", Year6ProbabilityQuestion.Outcome.unanswered), ("  ", " ", .unanswered),
                                            ("3", "", .invalidInput), ("", "4", .invalidInput), ("1.5", "4", .invalidInput),
                                            ("-1", "4", .invalidInput), ("1/2", "", .invalidInput)] {
                problems.check(question.evaluate(numerator: top, denominator: bottom) == expected, "\(top)/\(bottom)")
            }
        }
        #expect(problems.found.isEmpty, problems.summary)
        #expect(correct > 604)
    }
}

// MARK: - Examples from the proposal

@Suite("Stage 9C Batch 2: the proposal's examples")
struct Stage9CBatch2ExampleTests {
    @Test func solveXPlus7Makes19() {
        let question = Year6AlgebraQuestion(kind: .solve, first: 7, second: 12, multiplier: 2)
        #expect(question.expression == "x + 7 = 19")
        #expect(question.workedSolution.steps.map(\.text)
            == ["To get x on its own, take 7 away from both sides.", "19 − 7 = 12, so x = 12.", "Check: 12 + 7 = 19."])
        #expect(question.workedSolution.steps.map(\.spoken)
            == ["To get x on its own, take 7 away from both sides.", "19 minus 7 equals 12, so x equals 12.",
                "Check: 12 plus 7 equals 19."])
        #expect(question.workedSolution.answer == SpokenText("The answer is x = 12.", spoken: "The answer is x equals 12."))
        #expect(question.correctLine.text == "x = 12, because 12 + 7 = 19")
        #expect(question.hint(after: "19").text == "19 is the total. What number plus 7 makes 19?")
        #expect(question.hint(after: "26").spoken == "You added 7. To undo plus 7, take 7 away instead.")
        #expect(question.evaluate("12 = x") == .correct)
        #expect(question.askedAgain("19 − 7")?.message.text == "That's equal, but it needs simplifying further.")
        #expect(question.askedAgain("x + 7 = 19")?.message.text == "That's the question. Work out what x is.")
        #expect(question.askedAgain("12.0")?.message.text == "Write x as a whole number, without a decimal point.")
    }

    @Test func simplify7xPlus12x() {
        let question = Year6AlgebraQuestion(kind: .simplify, first: 7, second: 12, multiplier: 2)
        #expect(question.workedSolution.steps.map(\.text)
            == ["7x is 7 lots of x, and 12x is 12 lots of x.", "7 + 12 = 19, so that is 19 lots of x."])
        #expect(question.workedSolution.answer.text == "The answer is 19x.")
        #expect(question.correctLine == SpokenText("7x + 12x = 19x", spoken: "7x plus 12x equals 19x"))
        #expect(question.hint(after: "84x").text
            == "You multiplied. 7x means 7 lots of x and 12x means 12 lots of x. How many lots of x is that altogether?")
        #expect(question.hint(after: "19").text == "Keep the x. The answer is a number of x's, not a number on its own.")
        #expect(question.askedAgain("19 × x") == Wording.times(2))
        #expect(question.askedAgain("19.0x") == Wording.decimals)
        #expect(question.askedAgain("x19") == Wording.numberFirst(2))
        #expect(question.askedAgain("7x + 12x")?.message.text == "That's the question. It needs simplifying.")
        #expect(question.askedAgain("19x²") == nil)
        #expect(question.evaluate("19x²") == .incorrect)
    }

    @Test func expand3Times5xPlus2() {
        let question = Year6AlgebraQuestion(kind: .expand, first: 5, second: 2, multiplier: 3)
        #expect(question.workedSolution.steps.map(\.text)
            == ["Multiply each part inside the bracket by 3.", "3 × 5x = 15x and 3 × 2 = 6.", "Join the two parts with +."])
        #expect(question.workedSolution.answer == SpokenText("The answer is 15x + 6.", spoken: "The answer is 15x plus 6."))
        #expect(question.correctLine.spoken == "3 times open bracket 5x plus 2 close bracket equals 15x plus 6")
        #expect(question.hint(after: "15x + 2").text
            == "You multiplied 5x by 3, but not 2. Multiply each part inside the bracket by 3.")
        #expect(question.hint(after: "21x").spoken
            == "An x term and a number can't be added together. Keep them as two parts joined by plus.")
        #expect(question.askedAgain("3 × 5x + 3 × 2")?.detail?.spoken == "Write it as an x term plus a number, like 2x plus 3.")
        #expect(question.askedAgain("15x + 7") == nil)
        #expect(question.evaluate("6 + 15x") == .correct)
    }

    @Test func spinner3Of12Blue() {
        let question = Year6ProbabilityQuestion.spinner(sections: 12, blue: 3)
        #expect(question.workedSolution.answer
            == SpokenText("The answer is 3/12, or 1/4 in its simplest form.",
                          spoken: "The answer is 3 twelfths, or 1 quarter in its simplest form."))
        #expect(question.correctLine
            == SpokenText("3 of the 12 sections are blue, so the probability is 3/12 = 1/4.",
                          spoken: "3 of the 12 sections are blue, so the probability is 3 twelfths, which is the same as 1 quarter."))
        #expect(question.hint(after: (numerator: "9", denominator: "12")).text
            == "That is the chance of not landing on blue. How many sections are blue? How many sections are there altogether?")
        #expect(question.hint(after: (numerator: "12", denominator: "3")).text
            == "The numbers are upside down. The total goes on the bottom.")
        #expect(question.evaluate(numerator: "2", denominator: "8") == .correct)
    }

    @Test func threeCoinFlips() {
        let question = Year6ProbabilityQuestion.coin(flips: 3)
        #expect(question.workedSolution.steps.first?.text
            == "Each flip can land 2 ways, so 3 flips can land 2 × 2 × 2 = 8 ways: HHH, HHT, HTH, HTT, THH, THT, TTH and TTT.")
        #expect(question.hint(after: (numerator: "1", denominator: "6")).text
            == "Each flip can land 2 ways, so multiply 2s together, one 2 for each flip.")
        #expect(question.hint(after: (numerator: "1", denominator: "2")).spoken
            == "1 half is the chance for one flip. Each extra flip halves it again.")
    }
}

// MARK: - The Algebra and Probability views

private enum B2SourceError: Error {
    case missing(String)
}

private enum B2Source {
    static let projectFolder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static var isAvailable: Bool {
        FileManager.default.fileExists(atPath: projectFolder.appendingPathComponent("Maths Quest/ContentView.swift").path)
    }

    static func view(_ name: String) throws -> String {
        let source = try String(contentsOf: projectFolder.appendingPathComponent("Maths Quest/ContentView.swift"),
                                encoding: .utf8)
        guard let start = source.range(of: "\nstruct \(name): View {"),
              let end = source.range(of: "\n}\n", range: start.upperBound..<source.endIndex) else {
            throw B2SourceError.missing(name)
        }
        return String(source[start.lowerBound..<end.upperBound])
    }

    static func function(_ opening: String, in body: String) throws -> String {
        guard let start = body.range(of: "    " + opening),
              let end = body.range(of: "\n    }\n", range: start.upperBound..<body.endIndex) else {
            throw B2SourceError.missing(opening)
        }
        return String(body[start.lowerBound..<end.upperBound])
    }

    static func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    /// The lines of `text`, trimmed, without blanks or comments.
    static func lines(of text: String) -> [String] {
        text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("//") }
    }
}

@Suite("Stage 9C Batch 2: asking again costs nothing, and Skip shows the worked solution",
       .enabled(if: B2Source.isAvailable, "ContentView.swift isn't reachable from this test run"))
struct Stage9CBatch2ViewTests {
    /// B2-4: no point, no sound, no wrong attempt counted towards Skip, and no new hint. The message is shown and the
    /// answer can be changed.
    @Test func askingAgainOnlyShowsTheMessage() throws {
        let body = try B2Source.view("Year6AlgebraView")
        let lines = B2Source.lines(of: try B2Source.function("private func checkAnswer() {", in: body))
        #expect(Array(lines.prefix(9)) == [
            "private func checkAnswer() {",
            "guard !progress.isAdvancing else { return }",
            "askedAgain = current.askedAgain(stringAnswer)",
            "if let askedAgain {",
            "responseMessage = askedAgain.message.text",
            "showFeedback()",
            "return",
            "}",
            "switch current.evaluate(stringAnswer) {",
        ])
        // Points, sounds, wrong attempts and hints happen only after the asked-again check has returned.
        let askedAgainBlock = lines[2...6].joined(separator: "\n")
        for effect in ["points", "playSound", "recordWrongAttempt", "recordCorrectAnswer", "hint =", "saveData"] {
            #expect(!askedAgainBlock.contains(effect), "\(effect)")
        }
        #expect(B2Source.count("progress.recordWrongAttempt()", in: lines.joined(separator: "\n")) == 1)
    }

    /// The message and its second line are read in one announcement; a hint from an earlier wrong answer isn't read
    /// again; and the message stays 3 seconds when it has a second line to read.
    @Test func theMessageIsShownAndRead() throws {
        let body = try B2Source.view("Year6AlgebraView")
        #expect(body.contains("AnswerFeedbackText(message: responseMessage, spokenMessage: askedAgain?.message.spoken,"))
        #expect(body.contains("detail: correctLine ?? askedAgain?.detail, alsoSaying: hintAnnouncement)"))
        #expect(body.contains("responseMessage == \"Incorrect. Try Again!\" ? hint.map { \"Hint: \\($0.spoken)\" } : nil"))
        let showFeedback = try B2Source.function("private func showFeedback() {", in: body)
        #expect(showFeedback.contains("asyncAfter(deadline: .now() + (askedAgain?.detail == nil ? 1.5 : 3))"))
        let reset = B2Source.lines(of: try B2Source.function("private func resetQuestion() {", in: body))
        #expect(reset.contains("askedAgain = nil"))
    }

    @Test(arguments: ["Year6AlgebraView", "Year6ProbabilityView"])
    func skipShowsTheWorkedSolution(view: String) throws {
        let body = try B2Source.view(view)
        let lines = B2Source.lines(of: body)
        let skips = lines.indices.filter { lines[$0] == "guard progress.recordSkip() else { return }" }
        #expect(skips.count == 1)
        if let skip = skips.first {
            #expect(lines[skip + 1] == "showSolution()")
        }
        #expect(B2Source.count("skipQuestion(", in: body) == 0)
        #expect(B2Source.lines(of: try B2Source.function("private func showSolution() {", in: body))
            == ["private func showSolution() {", "hideKeyboard()", "hint = nil", "solution = current.workedSolution", "}"])
        #expect(B2Source.count("NextQuestionButton(action: nextQuestion)", in: body) == 1)
        #expect(B2Source.count("ExplanationCards(hint: hint, solution: solution,", in: body) == 2)
        #expect(B2Source.count(".answeredBySolution(solution != nil)", in: body) == 1)
    }

    @Test func theAnnouncementJoinsTheMessageAndItsSecondLine() throws {
        let question = Year6AlgebraQuestion(kind: .simplify, first: 7, second: 12, multiplier: 2)
        let times = try #require(question.askedAgain("19 × x"))
        #expect(AnswerFeedbackText(message: times.message.text, spokenMessage: times.message.spoken, detail: times.detail)
            .announcement == "In algebra, leave out the times sign. Write 2x, not 2 times x.")
        let typedBack = try #require(question.askedAgain("7x + 12x"))
        #expect(AnswerFeedbackText(message: typedBack.message.text, spokenMessage: typedBack.message.spoken,
                                   detail: typedBack.detail)
            .announcement == "That's the question. It needs simplifying. Put the x terms together into one x term.")
        #expect(AnswerFeedbackText(message: "Incorrect. Try Again!", alsoSaying: "Hint: Keep the x.").announcement
            == "Incorrect. Try Again! Hint: Keep the x.")
    }
}
