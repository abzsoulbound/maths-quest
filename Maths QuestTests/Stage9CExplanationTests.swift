//
//  Stage9CExplanationTests.swift
//  Maths QuestTests
//
//  Stage 9C: the hints, worked solutions and "Correct!" lines of the Batch 1 activities. Every question each activity
//  can ask is checked where there are few enough to check them all. The answer in each worked solution is worked out
//  again here from the question's numbers, independently of the app's code, and every step is re-calculated; the
//  app's own answer checker is only a second check, never the proof. No hint may contain the answer, written or
//  spoken, unless the question already shows that number. Mistakes are never reported for a right answer. Words are
//  kept short, without the words the proposal bans, and VoiceOver hears the same numbers as are shown.
//

import Foundation
import Testing
@testable import Maths_Quest

// MARK: - Shared checks

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

/// What VoiceOver hears, with the counting words it says turned back into the numbers shown, so the numbers of the
/// spoken and shown words can be compared: "Count in fives" becomes "Count in 5".
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

/// Sentences, counted by the full stops, question marks and exclamation marks that end them: a decimal point isn't
/// followed by a space, so it isn't counted.
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

/// "The answer is 20." gives 20.
private func answerNumber(_ answer: SpokenText) -> Int? {
    guard answer.text.hasPrefix("The answer is "), answer.text.hasSuffix(".") else { return nil }
    return Int(answer.text.dropFirst("The answer is ".count).dropLast())
}

/// Checks that apply to every piece of words: nothing banned, no symbols read as symbols, and the same numbers
/// spoken as shown.
private func checkWording(_ words: SpokenText, maximumSentences: Int, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(bannedWordsUsed(in: words.text).isEmpty, "Banned word in \(words.text)", sourceLocation: sourceLocation)
    #expect(bannedWordsUsed(in: words.spoken).isEmpty, "Banned word in \(words.spoken)", sourceLocation: sourceLocation)
    #expect(!words.spoken.contains("×") && !words.spoken.contains("÷"), "Symbol read aloud in \(words.spoken)",
            sourceLocation: sourceLocation)
    #expect(spokenNumbersAsShown(words.spoken) == spokenNumbersAsShown(words.text),
            "Spoken numbers differ: \(words.text) / \(words.spoken)", sourceLocation: sourceLocation)
    #expect(sentences(in: words.text) <= maximumSentences, "Too many sentences: \(words.text)",
            sourceLocation: sourceLocation)
    #expect(sentences(in: words.text) >= 1, "Not a sentence: \(words.text)", sourceLocation: sourceLocation)
}

/// Wrong answers to try for a question: every whole number up to `upTo` but the answer, and typing that isn't a whole
/// number.
private func wrongAnswers(upTo limit: Int, except answer: Int) -> [String] {
    (0...limit).filter { $0 != answer }.map(String.init) + ["abc", "-\(answer)", "\(answer).5", "\(answer) 0", "1/2"]
}

/// Failures found in a long loop, reported together at the end. Checking each of many thousands of cases with its own
/// #expect would make the suites slow.
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

/// The highest common factor, found by trying every number from the smaller one down: slow, and nothing like the
/// app's way, so it's a fair check on it.
private func highestCommonFactorByTrying(_ a: Int, _ b: Int) -> Int {
    stride(from: min(a, b), through: 1, by: -1).first { a % $0 == 0 && b % $0 == 0 } ?? 1
}

/// Digits only, as a child types a whole number: "12" is 12, but "-2", "1.5" and "" are nothing.
private func typedWholeNumber(_ typed: String) -> Int? {
    !typed.isEmpty && typed.allSatisfy { $0.isASCII && $0.isNumber } ? Int(typed) : nil
}

// MARK: - Year 2 Multiplication

@Suite("Stage 9C: Year 2 Multiplication explanations")
struct Stage9CMultiplicationExplanationTests {
    /// Every question the activity can ask: each table, times each number, either way round.
    static let allQuestions: [Year2MultiplicationQuestion] = Year2MultiplicationQuestion.tables.flatMap { table in
        Year2MultiplicationQuestion.multipliers.flatMap { multiplier in
            [Year2MultiplicationQuestion(first: table, second: multiplier),
             Year2MultiplicationQuestion(first: multiplier, second: table)]
        }
    }

    @Test func everyQuestionIsCovered() {
        #expect(Self.allQuestions.count == 60)
        #expect(Set(Self.allQuestions.map(\.text)).count == 51)
        // The generator can't ask anything outside this list.
        var generator = SeededGenerator(seed: 9_003)
        for _ in 0..<5_000 {
            let question = Year2MultiplicationQuestion.random(using: &generator)
            #expect(Self.allQuestions.contains(question))
        }
    }

    @Test func workedSolutionsGiveTheRightAnswer() {
        for question in Self.allQuestions {
            let solution = question.workedSolution
            // Worked out here, not by the app.
            let expected = question.first * question.second
            #expect(answerNumber(solution.answer) == expected, "\(question.text): \(solution.answer.text)")
            #expect(question.evaluate(String(expected)) == .correct, "\(question.text): checker disagrees")
            #expect(solution.answer.spoken == solution.answer.text)
            #expect(solution.steps.count >= 1 && solution.steps.count <= 3)
        }
    }

    /// Step 1 turns the question into groups; step 2 counts them. Both are re-calculated.
    @Test func everyStepIsTrue() {
        for question in Self.allQuestions {
            let steps = question.workedSolution.steps
            let expected = question.first * question.second
            #expect(steps.count == 2, "\(question.text)")

            // "a × b means g groups of s." or "a × b is the same as g × s: g groups of s."
            let meaning = numbers(in: steps[0].text)
            #expect(Array(meaning.prefix(2)) == [question.first, question.second], "\(steps[0].text)")
            let groups = meaning[meaning.count - 2]
            let size = meaning[meaning.count - 1]
            #expect(groups * size == expected, "\(steps[0].text)")
            #expect(Set([groups, size]) == Set([question.first, question.second]), "\(steps[0].text)")
            #expect(steps[0].text.contains("\(groups) \(groups == 1 ? "group" : "groups") of \(size)."))
            // The group size is a 2, 5 or 10, so it can be counted in.
            #expect(Year2MultiplicationQuestion.tables.contains(size), "\(steps[0].text)")
            if steps[0].text.contains("is the same as") {
                #expect(question.first != groups)
                #expect(meaning == [question.first, question.second, groups, size, groups, size])
            } else {
                #expect(question.first == groups && question.second == size)
            }

            // "Count in s: s, 2s, …, g×s." counts g groups of s and stops on the answer.
            let counting = numbers(in: steps[1].text)
            if groups == 1 {
                #expect(steps[1].text == "1 group of \(size) is \(size).")
            } else {
                #expect(counting.first == size, "\(steps[1].text)")
                let sequence = Array(counting.dropFirst())
                #expect(sequence == (1...groups).map { $0 * size }, "\(steps[1].text)")
                #expect(sequence.last == expected)
            }
            for step in steps {
                checkWording(step, maximumSentences: 1)
            }
        }
    }

    @Test func correctLineIsTheFinishedNumberSentence() {
        for question in Self.allQuestions {
            let line = question.correctLine
            #expect(numbers(in: line.text) == [question.first, question.second, question.first * question.second])
            #expect(line.text == "\(question.first) × \(question.second) = \(question.first * question.second)")
            #expect(line.spoken == "\(question.first) times \(question.second) equals \(question.first * question.second)")
        }
    }

    /// A hint never shows the answer, unless the answer is a number already in the question, as with 1 × 5.
    @Test func hintsNeverGiveTheAnswer() {
        var hintsChecked = 0
        var answerAlreadyInQuestion = 0
        for question in Self.allQuestions {
            let answer = question.first * question.second
            let answerIsShown = [question.first, question.second].contains(answer)
            for typed in wrongAnswers(upTo: 120, except: answer) {
                #expect(question.evaluate(typed) == .incorrect, "\(question.text): \(typed)")
                let hint = question.hint(after: typed)
                hintsChecked += 1
                if answerIsShown {
                    answerAlreadyInQuestion += 1
                } else {
                    #expect(!numbers(in: hint.text).contains(answer), "\(question.text) after \(typed): \(hint.text)")
                    #expect(!spokenNumbersAsShown(hint.spoken).contains(answer), "\(question.text): \(hint.spoken)")
                }
                #expect(!hint.text.contains("The answer is"))
                checkWording(hint, maximumSentences: 2)
            }
        }
        // 60 questions, each with 120 wrong whole numbers and 5 other wrong answers.
        #expect(hintsChecked == 60 * 125)
        // 1 × 2, 2 × 1, 1 × 5, 5 × 1, 1 × 10 and 10 × 1, whose answer is a number in the question.
        #expect(answerAlreadyInQuestion == 6 * 125)
    }

    @Test func mistakesAreNamedOnlyWhenTheyAreTrue() {
        var added = 0
        var oneGroupOut = 0
        var addingIsRight = 0
        var bothApply = 0
        for question in Self.allQuestions {
            let answer = question.first * question.second
            #expect(question.mistake(in: String(answer)) == nil)
            #expect(question.mistake(in: " \(answer) ") == nil)
            for number in 0...150 where number != answer {
                let mistake = question.mistake(in: String(number))
                let isSum = number == question.first + question.second
                let groups = question.groupCount
                let size = question.countingStep
                let isOneGroupOut = groups >= 2 && number > 0 && abs(number - answer) == size
                switch mistake {
                case .added:
                    #expect(isSum, "\(question.text): \(number)")
                    added += 1
                    if isOneGroupOut { bothApply += 1 }
                case .oneGroupOut:
                    #expect(isOneGroupOut && !isSum, "\(question.text): \(number)")
                    #expect(abs(number - answer) == size)
                    oneGroupOut += 1
                case nil:
                    #expect(!isSum && !isOneGroupOut, "\(question.text): \(number)")
                }
            }
            if question.first + question.second == answer {
                addingIsRight += 1
            }
            #expect(question.mistake(in: "abc") == nil)
        }
        // Adding gives the right answer only for 2 × 2, which the list has twice (2 times 2, and 2 times the table 2).
        #expect(addingIsRight == 2)
        #expect(added == 58)
        // 2 × 4 and 4 × 2 typed 6: adding is named, which is also true.
        #expect(bothApply == 2)
        #expect(oneGroupOut == 106)
    }

    @Test func goldenExamples() {
        let fourFives = Year2MultiplicationQuestion(first: 4, second: 5)
        #expect(fourFives.hint(after: "7") == SpokenText("4 groups of 5. Count in 5s.",
                                                          spoken: "4 groups of 5. Count in fives."))
        #expect(fourFives.hint(after: "9") == SpokenText("× means groups of, not adding. 4 × 5 means 4 groups of 5.",
                                                          spoken: "Times means groups of, not adding. 4 times 5 means 4 groups of 5."))
        #expect(fourFives.hint(after: "15").text == "Close. Count the groups again: you need 4 groups of 5.")
        #expect(fourFives.hint(after: "25").text == "Close. Count the groups again: you need 4 groups of 5.")
        #expect(fourFives.workedSolution == WorkedSolution(
            steps: [SpokenText("4 × 5 means 4 groups of 5.", spoken: "4 times 5 means 4 groups of 5."),
                    SpokenText("Count in 5s: 5, 10, 15, 20.", spoken: "Count in fives: 5, 10, 15, 20.")],
            answer: SpokenText("The answer is 20.")))
        #expect(fourFives.correctLine == SpokenText("4 × 5 = 20", spoken: "4 times 5 equals 20"))

        let fiveFours = Year2MultiplicationQuestion(first: 5, second: 4)
        #expect(fiveFours.hint(after: "7").text == "5 × 4 is the same as 4 × 5. Count in 5s.")
        #expect(fiveFours.workedSolution.steps[0].text == "5 × 4 is the same as 4 × 5: 4 groups of 5.")

        let tenTwos = Year2MultiplicationQuestion(first: 10, second: 2)
        #expect(tenTwos.hint(after: "3").text == "10 × 2 is the same as 2 × 10. Count in 10s.")
        #expect(tenTwos.hint(after: "12").text == "× means groups of, not adding. 10 × 2 is the same as 2 × 10: 2 groups of 10.")
        #expect(tenTwos.workedSolution.steps[1].text == "Count in 10s: 10, 20.")

        let twoFours = Year2MultiplicationQuestion(first: 2, second: 4)
        // 6 is both 2 + 4 and one group of 2 short of 8: adding is named, which is also true.
        #expect(twoFours.mistake(in: "6") == .added)
        #expect(twoFours.hint(after: "6").text == "× means groups of, not adding. 2 × 4 is the same as 4 × 2: 4 groups of 2.")

        let oneFive = Year2MultiplicationQuestion(first: 1, second: 5)
        #expect(oneFive.hint(after: "6").text == "× means groups of, not adding. 1 × 5 means 1 group of 5.")
        #expect(oneFive.hint(after: "4").text == "1 × 5 means 1 group of 5.")
        #expect(oneFive.workedSolution.steps[1].text == "1 group of 5 is 5.")
    }
}

// MARK: - Year 2 Division

@Suite("Stage 9C: Year 2 Division explanations")
struct Stage9CDivisionExplanationTests {
    static let allQuestions: [Year2DivisionQuestion] = Year2DivisionQuestion.divisors.flatMap { divisor in
        Year2DivisionQuestion.quotients.map { Year2DivisionQuestion(divisor: divisor, quotient: $0) }
    }

    @Test func everyQuestionIsCovered() {
        #expect(Self.allQuestions.count == 30)
        #expect(Set(Self.allQuestions.map(\.text)).count == 30)
        var generator = SeededGenerator(seed: 9_004)
        for _ in 0..<5_000 {
            #expect(Self.allQuestions.contains(Year2DivisionQuestion.random(using: &generator)))
        }
    }

    @Test func workedSolutionsGiveTheRightAnswer() {
        for question in Self.allQuestions {
            // Worked out here from the numbers shown, not from the question's quotient.
            let shown = numbers(in: question.text)
            #expect(shown.count == 2)
            let (dividend, divisor) = (shown[0], shown[1])
            #expect(dividend % divisor == 0)
            let expected = dividend / divisor
            let solution = question.workedSolution
            #expect(answerNumber(solution.answer) == expected, "\(question.text): \(solution.answer.text)")
            #expect(question.evaluate(String(expected)) == .correct, "\(question.text): checker disagrees")
            #expect(solution.steps.count >= 1 && solution.steps.count <= 3)
        }
    }

    @Test func everyStepIsTrue() {
        for question in Self.allQuestions {
            let shown = numbers(in: question.text)
            let (dividend, divisor) = (shown[0], shown[1])
            let expected = dividend / divisor
            let steps = question.workedSolution.steps
            if expected == 1 {
                #expect(steps.count == 1)
                #expect(steps[0].text == "One \(divisor) makes \(dividend).")
                #expect(divisor == dividend)
            } else {
                #expect(steps.count == 2)
                // "Count in 5s until you reach 20: 5, 10, 15, 20."
                let counted = numbers(in: steps[0].text)
                #expect(Array(counted.prefix(2)) == [divisor, dividend], "\(steps[0].text)")
                let sequence = Array(counted.dropFirst(2))
                #expect(sequence == (1...expected).map { $0 * divisor }, "\(steps[0].text)")
                #expect(sequence.last == dividend)
                // "That is 4 fives." names how many were counted.
                #expect(numbers(in: steps[1].text) == [sequence.count])
                #expect(sequence.count == expected)
                #expect(steps[1].text.hasSuffix(" \(ExplanationWording.pluralName(of: divisor)).") )
            }
            for step in steps {
                checkWording(step, maximumSentences: 1)
            }
        }
    }

    @Test func correctLineIsTheFinishedNumberSentence() {
        for question in Self.allQuestions {
            let shown = numbers(in: question.text)
            let line = question.correctLine
            #expect(line.text == "\(shown[0]) ÷ \(shown[1]) = \(shown[0] / shown[1])")
            #expect(line.spoken == "\(shown[0]) divided by \(shown[1]) equals \(shown[0] / shown[1])")
        }
    }

    @Test func hintsNeverGiveTheAnswer() {
        var hintsChecked = 0
        var answerAlreadyInQuestion = 0
        for question in Self.allQuestions {
            let shown = numbers(in: question.text)
            let answer = shown[0] / shown[1]
            let answerIsShown = shown.contains(answer)
            for typed in wrongAnswers(upTo: 120, except: answer) {
                #expect(question.evaluate(typed) == .incorrect, "\(question.text): \(typed)")
                let hint = question.hint(after: typed)
                hintsChecked += 1
                if answerIsShown {
                    answerAlreadyInQuestion += 1
                } else {
                    #expect(!numbers(in: hint.text).contains(answer), "\(question.text) after \(typed): \(hint.text)")
                    #expect(!spokenNumbersAsShown(hint.spoken).contains(answer), "\(question.text): \(hint.spoken)")
                }
                checkWording(hint, maximumSentences: 2)
            }
        }
        #expect(hintsChecked == 30 * 125)
        // The answer is a number in the question only for 4 ÷ 2, 25 ÷ 5 and 100 ÷ 10.
        #expect(answerAlreadyInQuestion == 3 * 125)
    }

    @Test func multiplyingIsNamedOnlyWhenItHappened() {
        var named = 0
        for question in Self.allQuestions {
            let shown = numbers(in: question.text)
            let answer = shown[0] / shown[1]
            #expect(question.mistake(in: String(answer)) == nil)
            for number in 0...1_000 where number != answer {
                let mistake = question.mistake(in: String(number))
                #expect((mistake == .multiplied) == (number == shown[0] * shown[1]), "\(question.text): \(number)")
                if mistake == .multiplied {
                    named += 1
                    // "The answer is smaller than 20" is true.
                    #expect(answer < shown[0])
                }
            }
        }
        #expect(named == 30)
    }

    @Test func goldenExamples() {
        let twentyByFive = Year2DivisionQuestion(divisor: 5, quotient: 4)
        #expect(twentyByFive.hint(after: "3") == SpokenText("How many 5s make 20? Count in 5s.",
                                                             spoken: "How many fives make 20? Count in fives."))
        #expect(twentyByFive.hint(after: "100") == SpokenText(
            "÷ means sharing or grouping, not multiplying. The answer is smaller than 20.",
            spoken: "Divided by means sharing or grouping, not multiplying. The answer is smaller than 20."))
        #expect(twentyByFive.workedSolution == WorkedSolution(
            steps: [SpokenText("Count in 5s until you reach 20: 5, 10, 15, 20.",
                               spoken: "Count in fives until you reach 20: 5, 10, 15, 20."),
                    SpokenText("That is 4 fives.")],
            answer: SpokenText("The answer is 4.")))
        #expect(twentyByFive.correctLine == SpokenText("20 ÷ 5 = 4", spoken: "20 divided by 5 equals 4"))

        let tenByTen = Year2DivisionQuestion(divisor: 10, quotient: 1)
        #expect(tenByTen.workedSolution.steps == [SpokenText("One 10 makes 10.", spoken: "One ten makes 10.")])

        let eighteenByTwo = Year2DivisionQuestion(divisor: 2, quotient: 9)
        #expect(eighteenByTwo.hint(after: "36").text
                == "÷ means sharing or grouping, not multiplying. The answer is smaller than 18.")
        #expect(eighteenByTwo.workedSolution.steps[1].text == "That is 9 twos.")
    }
}

// MARK: - Year 4 Geometry

@Suite("Stage 9C: Year 4 Geometry explanations")
struct Stage9CGeometryExplanationTests {
    typealias Question = Year4GeometryQuestion
    typealias Mistake = Year4GeometryQuestion.Mistake

    /// What VoiceOver calls each unit, written out here rather than taken from the app.
    static let unitWords = ["mm": "millimetres", "cm": "centimetres", "m": "metres", "km": "kilometres"]
    /// Every unit the wheel offers: the four lengths, then the four areas.
    static let allUnits = Question.units + Question.units.map { $0 + "²" }

    /// Whether sides of these lengths close up into a shape: the longest is shorter than all the others together.
    static func closesUp(_ sides: [Int]) -> Bool {
        2 * (sides.max() ?? 0) < sides.reduce(0, +)
    }

    /// Every rectangle question: perimeter and area, for each width, height and unit.
    static let rectangles: [Question] = [1, 2].flatMap { kind in
        Question.sideLengths.flatMap { width in
            Question.sideLengths.flatMap { height in
                Question.units.map { unit in
                    Question(question: kind, shapeType: 4, sides: [width, height, width, height],
                             angleMeasure: 90, unitType: unit)
                }
            }
        }
    }

    /// The sides of every triangle that closes up, in drawing order.
    static let triangleSides: [[Int]] = Question.sideLengths.flatMap { a in
        Question.sideLengths.flatMap { b in Question.sideLengths.map { c in [a, b, c] } }
    }.filter(closesUp)

    /// Every triangle in every unit.
    static let triangles: [Question] = triangleSides.flatMap { sides in
        Question.units.map { Question(question: 1, shapeType: 3, sides: sides, angleMeasure: 90, unitType: $0) }
    }

    /// Every angle the activity draws. The shape isn't drawn for an angle question, so its sides don't matter.
    static let angles: [Question] = Question.angles.map {
        Question(question: 3, shapeType: 4, sides: [5, 5, 5, 5], angleMeasure: $0, unitType: "cm")
    }

    /// Every pentagon that closes up, each in the next of the four units in turn, one at a time: there are too many to
    /// keep in a list. Returns how many there were.
    @discardableResult
    static func forEachPentagon(_ body: (Question) -> Void) -> Int {
        var count = 0
        let lengths = Array(Question.sideLengths)
        for a in lengths {
            for b in lengths {
                for c in lengths {
                    for d in lengths {
                        for e in lengths where closesUp([a, b, c, d, e]) {
                            body(Question(question: 1, shapeType: 5, sides: [a, b, c, d, e], angleMeasure: 90,
                                          unitType: Question.units[count % 4]))
                            count += 1
                        }
                    }
                }
            }
        }
        return count
    }

    /// The answer to a perimeter or area question, worked out here from the side lengths the picture is labelled with,
    /// read from what VoiceOver says about it.
    static func expectedAnswer(_ question: Question) -> Int {
        let shown = numbers(in: question.figureDescription)
        return question.question == 1 ? shown.reduce(0, +) : shown[0] * shown[1]
    }

    /// The unit a perimeter or area must be given in: the sides' unit, or its square.
    static func expectedUnit(_ question: Question) -> String {
        question.question == 1 ? question.unitType : question.unitType + "²"
    }

    /// Checks a perimeter or area question's worked solution and "Correct!" line against the picture's side lengths.
    /// Every number is worked out here; every step's sum or product is re-calculated from its own numbers.
    fileprivate static func checkWorkedOut(_ question: Question, into problems: inout Problems) {
        let shown = numbers(in: question.figureDescription)
        let unit = question.unitType
        let unitWord = unitWords[unit] ?? "?"
        let name = "\(question.question == 1 ? "perimeter" : "area") of \(shown) \(unit)"
        problems.check(shown == question.sides, "\(name): the picture shows \(shown)")
        let solution = question.workedSolution
        let line = question.correctLine
        let sides = shown.map(String.init)
        problems.check(solution.steps.count >= 1 && solution.steps.count <= 3, "\(name): \(solution.steps.count) steps")

        if question.question == 1 {
            let perimeter = shown.reduce(0, +)
            problems.check(solution.answer == SpokenText("The answer is \(perimeter) \(unit).",
                                                         spoken: "The answer is \(perimeter) \(unitWord)."),
                           "\(name): \(solution.answer)")
            problems.check(question.evaluate(answer: String(perimeter), unit: unit) == .correct,
                           "\(name): the checker disagrees with \(perimeter)")
            let adding = SpokenText(sides.joined(separator: " + ") + " = \(perimeter).",
                                    spoken: sides.joined(separator: " plus ") + " equals \(perimeter).")
            let expectedSteps: [SpokenText]
            if question.shapeType == 4 {
                let listed = "\(sides[0]), \(sides[1]), \(sides[2]) and \(sides[3])"
                expectedSteps = [SpokenText("The sides are \(listed) \(unit).", spoken: "The sides are \(listed) \(unitWord)."),
                                 adding]
            } else {
                expectedSteps = [SpokenText("Add the sides: " + adding.text, spoken: "Add the sides: " + adding.spoken)]
            }
            problems.check(solution.steps == expectedSteps, "\(name): \(solution.steps.map(\.text))")
            // The adding step adds up: the numbers before the = make the one after it.
            let added = numbers(in: solution.steps.last?.text ?? "")
            problems.check(added.dropLast() == ArraySlice(shown) && added.dropLast().reduce(0, +) == added.last,
                           "\(name): \(solution.steps.last?.text ?? "")")
            problems.check(line == SpokenText(sides.joined(separator: " + ") + " = \(perimeter) \(unit)",
                                              spoken: sides.joined(separator: " plus ") + " equals \(perimeter) \(unitWord)"),
                           "\(name): \(line)")
        } else {
            let area = shown[0] * shown[1]
            problems.check(solution.answer == SpokenText("The answer is \(area) \(unit)².",
                                                         spoken: "The answer is \(area) square \(unitWord)."),
                           "\(name): \(solution.answer)")
            problems.check(question.evaluate(answer: String(area), unit: unit + "²") == .correct,
                           "\(name): the checker disagrees with \(area)")
            problems.check(solution.steps == [
                SpokenText("Area = length × width.", spoken: "Area equals length times width."),
                SpokenText("\(shown[0]) × \(shown[1]) = \(area).", spoken: "\(shown[0]) times \(shown[1]) equals \(area).")
            ], "\(name): \(solution.steps.map(\.text))")
            let multiplied = numbers(in: solution.steps.last?.text ?? "")
            problems.check(multiplied.count == 3 && multiplied[0] * multiplied[1] == multiplied[2],
                           "\(name): \(solution.steps.last?.text ?? "")")
            problems.check(line == SpokenText("\(shown[0]) × \(shown[1]) = \(area) \(unit)²",
                                              spoken: "\(shown[0]) times \(shown[1]) equals \(area) square \(unitWord)"),
                           "\(name): \(line)")
        }
        // VoiceOver reads words, never the signs.
        for words in solution.steps + [solution.answer, line] {
            problems.check(!["+", "=", "×", "²"].contains { words.spoken.contains($0) }, "\(name): \(words.spoken)")
        }
    }

    @Test func everyQuestionIsCovered() {
        #expect(Self.rectangles.count == 968)
        #expect(Self.triangleSides.count == 836)
        #expect(Self.triangles.count == 3_344)
        #expect(Self.angles.count == 133)
        #expect(Self.forEachPentagon { _ in } == 160_421)

        // The app's check on which sides close up agrees with the rule here, for every triangle and pentagon.
        var problems = Problems()
        let lengths = Array(Question.sideLengths)
        var checked = 0
        for a in lengths {
            for b in lengths {
                for c in lengths {
                    problems.check(Question.isConstructible([a, b, c]) == Self.closesUp([a, b, c]), "\([a, b, c])")
                    checked += 1
                    for d in lengths {
                        for e in lengths {
                            let sides = [a, b, c, d, e]
                            problems.check(Question.isConstructible(sides) == Self.closesUp(sides), "\(sides)")
                            checked += 1
                        }
                    }
                }
            }
        }
        #expect(checked == 1_331 + 161_051)

        // The generator asks nothing outside these lists.
        var generator = SeededGenerator(seed: 9_005)
        var kinds: [Int: Int] = [:]
        for _ in 0..<10_000 {
            let question = Question.random(using: &generator)
            let sides = question.sides
            kinds[question.question, default: 0] += 1
            problems.check(Question.units.contains(question.unitType), "unit \(question.unitType)")
            problems.check(Question.angles.contains(question.angleMeasure), "angle \(question.angleMeasure)")
            problems.check([3, 4, 5].contains(question.shapeType) && sides.count == question.shapeType,
                           "shape \(question.shapeType) with \(sides)")
            problems.check(sides.allSatisfy { Question.sideLengths.contains($0) }, "sides \(sides)")
            problems.check(Self.closesUp(sides), "sides that don't close up: \(sides)")
            if question.shapeType == 4 {
                problems.check(sides.count == 4 && sides[0] == sides[2] && sides[1] == sides[3], "rectangle \(sides)")
            }
            problems.check(question.question != 2 || question.shapeType == 4, "area of shape \(question.shapeType)")
        }
        #expect(problems.found.isEmpty, problems.summary)
        #expect(kinds.keys.sorted() == [1, 2, 3])
    }

    @Test func everyRectangleAndTriangleIsWorkedOut() {
        var problems = Problems()
        var wording: [String: SpokenText] = [:]
        for question in Self.rectangles + Self.triangles {
            Self.checkWorkedOut(question, into: &problems)
            for words in question.workedSolution.steps + [question.workedSolution.answer] {
                wording[words.text + "\u{0}" + words.spoken] = words
            }
        }
        #expect(problems.found.isEmpty, problems.summary)
        for words in wording.values {
            checkWording(words, maximumSentences: 1)
        }
    }

    @Test func everyPentagonIsWorkedOut() {
        var problems = Problems()
        // The wording of every 97th pentagon is checked too: checking all 160,421 takes too long.
        var sample: [String: SpokenText] = [:]
        var index = 0
        let count = Self.forEachPentagon { question in
            Self.checkWorkedOut(question, into: &problems)
            if index % 97 == 0 {
                for words in question.workedSolution.steps + [question.workedSolution.answer] {
                    sample[words.text + "\u{0}" + words.spoken] = words
                }
            }
            index += 1
        }
        #expect(count == 160_421)
        #expect(problems.found.isEmpty, problems.summary)
        #expect(sample.count > 1_000)
        for words in sample.values {
            checkWording(words, maximumSentences: 1)
        }
    }

    @Test func everyAngleIsNamedCorrectly() {
        for question in Self.angles {
            let angle = question.angleMeasure
            #expect(angle > 0 && angle < 180)
            // Named here from the size of the angle in degrees, which the child isn't shown.
            let type = angle < 90 ? "acute" : angle == 90 ? "right angle" : "obtuse"
            let solution = question.workedSolution
            #expect(solution.answer == SpokenText("The answer is \(type == "right angle" ? "a right angle" : type)."))
            // The answer as it's typed, without "a", is what the checker accepts.
            #expect(question.evaluate(answer: type, unit: "") == .correct, "\(angle)°: the checker disagrees")
            #expect(question.evaluate(answer: type, unit: "cm") == .correct, "\(angle)°: a unit picked by mistake")

            #expect(solution.steps.count == 2)
            #expect(solution.steps.first == SpokenText("A right angle is a square corner."))
            switch type {
            case "acute":
                #expect(solution.steps.last == SpokenText("This angle is smaller than a right angle."))
                #expect(question.correctLine == SpokenText("This angle is acute."))
            case "right angle":
                #expect(solution.steps.last == SpokenText("This angle is exactly a square corner."))
                #expect(question.correctLine == SpokenText("This is a right angle."))
            default:
                #expect(solution.steps.last
                        == SpokenText("This angle is bigger than a right angle and smaller than a straight line."))
                #expect(question.correctLine == SpokenText("This angle is obtuse."))
            }
            for words in solution.steps + [solution.answer, question.correctLine] {
                checkWording(words, maximumSentences: 1)
            }
        }
    }

    /// No hint has the answer's number in it, written or spoken, for any wrong number or unit. Each different hint is
    /// collected with every answer it was shown for, and checked once.
    @Test func hintsNeverGiveTheAnswer() {
        var problems = Problems()
        var shownFor: [String: (hint: SpokenText, answers: Set<Int>)] = [:]
        func record(_ hint: SpokenText, answer: Int) {
            let key = hint.text + "\u{0}" + hint.spoken
            shownFor[key, default: (hint, [])].answers.insert(answer)
        }

        // Every rectangle; every triangle, in one unit each; 1,000 pentagons drawn as the game draws them.
        var generator = SeededGenerator(seed: 9_006)
        let pentagons = (0..<1_000).map { index in
            Question(question: 1, shapeType: 5, sides: Question.randomSides(shapeType: 5, using: &generator),
                     angleMeasure: 90, unitType: Question.units[index % 4])
        }
        let triangles = Self.triangleSides.enumerated().map { index, sides in
            Question(question: 1, shapeType: 3, sides: sides, angleMeasure: 90, unitType: Question.units[index % 4])
        }
        let questions = Self.rectangles + triangles + pentagons
        var wrongNumbers = 0
        var wrongUnits = 0
        for question in questions {
            let answer = Self.expectedAnswer(question)
            let unit = Self.expectedUnit(question)
            let name = "\(question.question == 1 ? "perimeter" : "area") of \(question.sides) \(question.unitType)"
            for typed in wrongAnswers(upTo: 150, except: answer) {
                problems.check(question.evaluate(answer: typed, unit: unit) == .incorrect, "\(name): \(typed)")
                record(question.hint(after: (answer: typed, unit: unit)), answer: answer)
                wrongNumbers += 1
            }
            // The right number, with every other unit or none picked.
            for picked in Self.allUnits + [""] where picked != unit {
                problems.check(question.evaluate(answer: String(answer), unit: picked) == .wrongUnit,
                               "\(name): \(answer) \(picked)")
                record(question.hint(after: (answer: String(answer), unit: picked)), answer: answer)
                wrongUnits += 1
            }
        }
        #expect(problems.found.isEmpty, problems.summary)
        #expect(questions.count == 968 + 836 + 1_000)
        // 150 wrong whole numbers and 5 other wrong answers each.
        #expect(wrongNumbers == questions.count * 155)
        // 7 wrong units and none picked.
        #expect(wrongUnits == questions.count * 8)

        // Perimeter: the area given, two sides added, no unit, the wrong unit, and the plain hint for a rectangle and
        // for any other shape. Area: the perimeter given, two sides added, no unit, the wrong unit, and the plain hint.
        #expect(shownFor.count == 11)
        for (hint, answers) in shownFor.values {
            #expect(Set(numbers(in: hint.text)).isDisjoint(with: answers), "\(hint.text)")
            #expect(Set(spokenNumbersAsShown(hint.spoken)).isDisjoint(with: answers), "\(hint.spoken)")
            #expect(!hint.text.contains("The answer is"))
            #expect(!hint.spoken.contains("²"), "\(hint.spoken)")
            // "a small ²" is read "a small 2": the same number, which VoiceOver can't say as a symbol.
            checkWording(SpokenText(hint.text, spoken: hint.spoken.replacingOccurrences(of: "a small 2", with: "a small ²")),
                         maximumSentences: 2)
        }

        // An angle's hint is the same whatever the angle and whatever was typed, so it can't tell which it is.
        let angleHint = SpokenText("Compare the angle with a square corner (a right angle).")
        var angleHints = 0
        for question in Self.angles {
            for typed in ["acute", "right", "obtuse", "Right angle", "a right angle", "90", "45", "abc", "straight"]
            where question.evaluate(answer: typed, unit: "") == .incorrect {
                #expect(question.hint(after: (answer: typed, unit: "")) == angleHint, "\(question.angleMeasure)°: \(typed)")
                angleHints += 1
            }
        }
        // 9 tries each: 8 are wrong for an acute or obtuse angle, and 6 for the right angle ("right", "Right angle"
        // and "a right angle" are all right). Batch FB-B deliberately made "a right angle" right: it was 7 before.
        #expect(angleHints == 66 * 8 + 6 + 66 * 8)
        #expect(!angleHint.text.lowercased().contains("acute") && !angleHint.text.lowercased().contains("obtuse"))
        checkWording(angleHint, maximumSentences: 2)
    }

    @Test func mistakesAreNamedOnlyWhenTheyAreTrue() {
        var problems = Problems()
        var counts: [String: Int] = [:]
        for question in Self.rectangles {
            let (width, height) = (question.sides[0], question.sides[1])
            let perimeter = 2 * (width + height)
            let area = width * height
            let isPerimeter = question.question == 1
            let answer = isPerimeter ? perimeter : area
            let unit = Self.expectedUnit(question)
            let name = "\(isPerimeter ? "perimeter" : "area") of \(width) × \(height)"
            for number in 0...150 where number != answer {
                let found = question.mistake(in: (answer: String(number), unit: unit))
                // In the proposal's order: the other measurement given, then two sides added.
                let expected: Mistake?
                if isPerimeter, number == area {
                    expected = .gaveArea
                } else if !isPerimeter, number == perimeter {
                    expected = .gavePerimeter
                } else if number == width + height {
                    expected = .addedTwoSides
                } else {
                    expected = nil
                }
                problems.check(found == expected, "\(name): \(number) named \(String(describing: found))")
                // Only the right number is checked for its unit, so a wrong number is named the same whatever unit.
                problems.check(question.mistake(in: (answer: String(number), unit: "")) == found, "\(name): \(number)")
                if let found {
                    counts["\(isPerimeter ? "perimeter" : "area") \(found)", default: 0] += 1
                }
            }
            for typed in ["abc", "-\(answer)", "\(answer).5", "", " "] {
                problems.check(question.mistake(in: (answer: typed, unit: unit)) == nil, "\(name): \(typed)")
            }
        }
        // 121 rectangles in each of 4 units. The other measurement is named for all but the 3 whose area and perimeter
        // are equal (3 × 6, 6 × 3 and 4 × 4, where it's the right answer); two sides added for all but 2 × 2, whose
        // two sides make 4, which is its area.
        #expect(counts == ["perimeter gaveArea": 118 * 4, "perimeter addedTwoSides": 120 * 4,
                           "area gavePerimeter": 118 * 4, "area addedTwoSides": 120 * 4])

        // A triangle or pentagon has no area to mix up, and two of its sides added aren't a known mistake.
        var generator = SeededGenerator(seed: 9_007)
        let others = Self.triangles + (0..<500).map { _ in
            Question(question: 1, shapeType: 5, sides: Question.randomSides(shapeType: 5, using: &generator),
                     angleMeasure: 90, unitType: "m")
        }
        for question in others {
            let answer = Self.expectedAnswer(question)
            for number in 0...150 where number != answer {
                problems.check(question.mistake(in: (answer: String(number), unit: question.unitType)) == nil,
                               "\(question.sides): \(number)")
            }
        }

        // The right number: nothing with the right unit, no unit when none is picked, and the wrong unit otherwise.
        var unitCounts: [Mistake?: Int] = [:]
        for question in Self.rectangles + Self.triangles {
            let answer = String(Self.expectedAnswer(question))
            let unit = Self.expectedUnit(question)
            for picked in Self.allUnits + [""] {
                let found = question.mistake(in: (answer: answer, unit: picked))
                let expected: Mistake? = picked == unit ? nil : picked.isEmpty ? .noUnit : .wrongUnit
                problems.check(found == expected, "\(question.sides) \(answer) \(picked)")
                unitCounts[found, default: 0] += 1
            }
            // Spaces round the number don't count against it.
            problems.check(question.mistake(in: (answer: " \(answer) ", unit: unit)) == nil, "\(question.sides)")
        }
        let measured = 968 + 3_344
        #expect(unitCounts == [nil: measured, .noUnit: measured, .wrongUnit: measured * 7])

        // An angle question never names a mistake.
        for question in Self.angles {
            for typed in ["acute", "right", "obtuse", "90", "abc", ""] {
                problems.check(question.mistake(in: (answer: typed, unit: "")) == nil, "\(question.angleMeasure)°: \(typed)")
            }
        }
        #expect(problems.found.isEmpty, problems.summary)
    }

    @Test func goldenExamples() {
        let perimeter = Question(question: 1, shapeType: 4, sides: [7, 4, 7, 4], angleMeasure: 90, unitType: "cm")
        #expect(perimeter.hint(after: (answer: "28", unit: "cm"))
                == SpokenText("That is the area. Perimeter is the distance all the way round: add every side."))
        #expect(perimeter.hint(after: (answer: "11", unit: "cm")) == SpokenText("Add all 4 sides, not only 2."))
        #expect(perimeter.hint(after: (answer: "22", unit: ""))
                == SpokenText("Pick a unit as well. Perimeter is a length: use the same unit as the sides."))
        #expect(perimeter.hint(after: (answer: "22", unit: "m"))
                == SpokenText("Perimeter is a length. Use the same unit as the sides."))
        #expect(perimeter.hint(after: (answer: "22", unit: "cm²"))
                == SpokenText("Perimeter is a length. Use the same unit as the sides."))
        #expect(perimeter.hint(after: (answer: "20", unit: "cm"))
                == SpokenText("Perimeter is the distance all the way round. Add all 4 sides."))
        #expect(perimeter.workedSolution == WorkedSolution(
            steps: [SpokenText("The sides are 7, 4, 7 and 4 cm.", spoken: "The sides are 7, 4, 7 and 4 centimetres."),
                    SpokenText("7 + 4 + 7 + 4 = 22.", spoken: "7 plus 4 plus 7 plus 4 equals 22.")],
            answer: SpokenText("The answer is 22 cm.", spoken: "The answer is 22 centimetres.")))
        #expect(perimeter.correctLine == SpokenText("7 + 4 + 7 + 4 = 22 cm", spoken: "7 plus 4 plus 7 plus 4 equals 22 centimetres"))

        let area = Question(question: 2, shapeType: 4, sides: [7, 4, 7, 4], angleMeasure: 90, unitType: "cm")
        #expect(area.hint(after: (answer: "22", unit: "cm²"))
                == SpokenText("That is the perimeter. Area is the space inside: multiply length by width."))
        #expect(area.hint(after: (answer: "11", unit: "cm²")) == SpokenText("For area, multiply the sides. Do not add them."))
        #expect(area.hint(after: (answer: "28", unit: ""))
                == SpokenText("Pick a unit as well. Area is measured in square units, with a small ².",
                              spoken: "Pick a unit as well. Area is measured in square units, with a small 2."))
        #expect(area.hint(after: (answer: "28", unit: "cm"))
                == SpokenText("Area is measured in square units. Pick the one that matches the sides."))
        #expect(area.hint(after: (answer: "30", unit: "cm²"))
                == SpokenText("Area is the space inside. Multiply the length by the width."))
        #expect(area.workedSolution == WorkedSolution(
            steps: [SpokenText("Area = length × width.", spoken: "Area equals length times width."),
                    SpokenText("7 × 4 = 28.", spoken: "7 times 4 equals 28.")],
            answer: SpokenText("The answer is 28 cm².", spoken: "The answer is 28 square centimetres.")))
        #expect(area.correctLine == SpokenText("7 × 4 = 28 cm²", spoken: "7 times 4 equals 28 square centimetres"))

        let triangle = Question(question: 1, shapeType: 3, sides: [5, 6, 9], angleMeasure: 90, unitType: "m")
        #expect(triangle.workedSolution == WorkedSolution(
            steps: [SpokenText("Add the sides: 5 + 6 + 9 = 20.", spoken: "Add the sides: 5 plus 6 plus 9 equals 20.")],
            answer: SpokenText("The answer is 20 m.", spoken: "The answer is 20 metres.")))
        #expect(triangle.hint(after: (answer: "19", unit: "m"))
                == SpokenText("Perimeter is the distance all the way round. Add every side."))
        #expect(triangle.hint(after: (answer: "20", unit: "km"))
                == SpokenText("Perimeter is a length. Use the same unit as the sides."))

        let obtuse = Question(question: 3, shapeType: 3, sides: [5, 6, 9], angleMeasure: 120, unitType: "m")
        #expect(obtuse.workedSolution == WorkedSolution(
            steps: [SpokenText("A right angle is a square corner."),
                    SpokenText("This angle is bigger than a right angle and smaller than a straight line.")],
            answer: SpokenText("The answer is obtuse.")))
        #expect(obtuse.correctLine == SpokenText("This angle is obtuse."))
        #expect(obtuse.hint(after: (answer: "acute", unit: ""))
                == SpokenText("Compare the angle with a square corner (a right angle)."))

        // A 4 × 4 square: 16 is both its perimeter and its area, so 16 is right for each, and needs only its unit.
        let squarePerimeter = Question(question: 1, shapeType: 4, sides: [4, 4, 4, 4], angleMeasure: 90, unitType: "mm")
        let squareArea = Question(question: 2, shapeType: 4, sides: [4, 4, 4, 4], angleMeasure: 90, unitType: "mm")
        #expect(squarePerimeter.evaluate(answer: "16", unit: "mm") == .correct)
        #expect(squareArea.evaluate(answer: "16", unit: "mm²") == .correct)
        #expect(squarePerimeter.mistake(in: (answer: "16", unit: "mm")) == nil)
        #expect(squarePerimeter.mistake(in: (answer: "16", unit: "mm²")) == .wrongUnit)
        #expect(squareArea.mistake(in: (answer: "16", unit: "mm²")) == nil)
        #expect(squareArea.mistake(in: (answer: "8", unit: "mm²")) == .addedTwoSides)

        // A 2 × 2 square: 4 is its area and its two sides added. The area is named first.
        let small = Question(question: 1, shapeType: 4, sides: [2, 2, 2, 2], angleMeasure: 90, unitType: "km")
        #expect(small.mistake(in: (answer: "4", unit: "km")) == .gaveArea)
        let smallArea = Question(question: 2, shapeType: 4, sides: [2, 2, 2, 2], angleMeasure: 90, unitType: "km")
        #expect(smallArea.mistake(in: (answer: "8", unit: "km²")) == .gavePerimeter)
        #expect(smallArea.evaluate(answer: "4", unit: "km²") == .correct)
    }
}

// MARK: - Year 6 Ratio

/// The pairs of numbers written with a separator between them: "8 : 12" in "Simplify the ratio 8 : 12", or "8 to 12"
/// as VoiceOver hears it.
private func ratioPairs(in words: String, separator: String) -> [[Int]] {
    guard let pattern = try? NSRegularExpression(pattern: "(\\d+) \(separator) (\\d+)") else { return [] }
    let text = words as NSString
    return pattern.matches(in: words, range: NSRange(location: 0, length: text.length)).map { match in
        [Int(text.substring(with: match.range(at: 1))) ?? -1, Int(text.substring(with: match.range(at: 2))) ?? -1]
    }
}

@Suite("Stage 9C: Year 6 Ratio explanations")
struct Stage9CRatioExplanationTests {
    typealias Question = Year6RatioQuestion
    typealias Mistake = Year6RatioQuestion.Mistake

    static let kinds: [Question.Kind] = [.simplify, .share, .missingFirst, .missingSecond]

    /// Every question the activity can ask: each kind, for each ratio and multiplier.
    static let allQuestions: [Question] = kinds.flatMap { kind in
        Question.ratioTerms.flatMap { first in
            Question.ratioTerms.flatMap { second in
                Question.multipliers.map { Question(kind: kind, first: first, second: second, multiplier: $0) }
            }
        }
    }

    /// The answer, worked out here from the numbers the question shows: two numbers for a ratio, or one missing
    /// number.
    static func expectedAnswer(_ question: Question) -> [Int] {
        let shown = numbers(in: question.text)
        switch question.kind {
        case .simplify:
            // "Simplify the ratio A : B"
            let factor = highestCommonFactorByTrying(shown[0], shown[1])
            return [shown[0] / factor, shown[1] / factor]
        case .share:
            // "Divide T in the ratio a : b": one part is T ÷ (a + b).
            let onePart = shown[0] / (shown[1] + shown[2])
            return [shown[1] * onePart, shown[2] * onePart]
        case .missingFirst:
            // "___ : B = a : b": B is b scaled up, so the gap is a scaled up the same.
            return [shown[1] * (shown[0] / shown[2])]
        case .missingSecond:
            // "A : ___ = a : b"
            return [shown[2] * (shown[0] / shown[1])]
        }
    }

    /// The worked solution's steps, written here from the numbers the question shows.
    static func expectedSteps(_ question: Question) -> [SpokenText] {
        let shown = numbers(in: question.text)
        switch question.kind {
        case .simplify:
            let (a, b) = (shown[0], shown[1])
            let factor = highestCommonFactorByTrying(a, b)
            return [SpokenText("The highest common factor of \(a) and \(b) is \(factor)."),
                    SpokenText("\(a) ÷ \(factor) = \(a / factor) and \(b) ÷ \(factor) = \(b / factor).",
                               spoken: "\(a) divided by \(factor) equals \(a / factor) and \(b) divided by \(factor) equals \(b / factor).")]
        case .share:
            let (total, a, b) = (shown[0], shown[1], shown[2])
            let parts = a + b
            let onePart = total / parts
            return [SpokenText("\(a) + \(b) = \(parts) parts.", spoken: "\(a) plus \(b) equals \(parts) parts."),
                    SpokenText("\(total) ÷ \(parts) = \(onePart), so one part is \(onePart).",
                               spoken: "\(total) divided by \(parts) equals \(onePart), so one part is \(onePart)."),
                    SpokenText("\(a) × \(onePart) = \(a * onePart) and \(b) × \(onePart) = \(b * onePart).",
                               spoken: "\(a) times \(onePart) equals \(a * onePart) and \(b) times \(onePart) equals \(b * onePart).")]
        case .missingFirst, .missingSecond:
            // The term beside the gap's partner was scaled to the number shown; the other term is scaled the same.
            let shownScaled = shown[0]
            let (known, other) = question.kind == .missingFirst ? (shown[2], shown[1]) : (shown[1], shown[2])
            let factor = shownScaled / known
            return [SpokenText("\(known) × \(factor) = \(shownScaled), so the ratio was multiplied by \(factor).",
                               spoken: "\(known) times \(factor) equals \(shownScaled), so the ratio was multiplied by \(factor)."),
                    SpokenText("\(other) × \(factor) = \(other * factor).", spoken: "\(other) times \(factor) equals \(other * factor).")]
        }
    }

    /// The mistake a response shows, worked out here from the numbers the question shows, in the proposal's order:
    /// one box empty; then, for two whole numbers that aren't the answer, the answer reversed, the question's own
    /// ratio, an equal ratio that isn't simplest, or the ratio given as the shares; or, for a missing number, the
    /// difference added rather than multiplied.
    static func expectedMistake(_ question: Question, first: String, second: String, missing: String) -> Mistake? {
        let shown = numbers(in: question.text)
        let answer = expectedAnswer(question)
        if answer.count == 2 {
            let isBlank = { (typed: String) in typed.trimmingCharacters(in: .whitespaces).isEmpty }
            if isBlank(first) != isBlank(second) {
                return .oneBoxEmpty
            }
            guard let x = typedWholeNumber(first), let y = typedWholeNumber(second), [x, y] != answer else { return nil }
            if answer[0] != answer[1], [x, y] == [answer[1], answer[0]] {
                return .reversed
            }
            if question.kind == .simplify {
                if [x, y] == shown {
                    return .sameAsQuestion
                }
                if x > 0, y > 0, x < shown[0], x * shown[1] == y * shown[0] {
                    return .notSimplest
                }
                return nil
            }
            return [x, y] == [shown[1], shown[2]] ? .gaveRatio : nil
        }
        guard let typed = typedWholeNumber(missing), typed != answer[0] else { return nil }
        // "___ : B = a : b": B − b added to a. "A : ___ = a : b": A − a added to b.
        let added = question.kind == .missingFirst ? shown[1] + (shown[0] - shown[2]) : shown[2] + (shown[0] - shown[1])
        return typed == added ? .added : nil
    }

    /// What to type in the two ratio boxes: whole numbers up to 12, the numbers the question shows, the answer's own
    /// numbers, and typing that isn't a whole number.
    static func typedRatioParts(for question: Question) -> [String] {
        let values = Set(0...12).union(numbers(in: question.text)).union(expectedAnswer(question))
        return values.sorted().map(String.init) + ["abc", "1.5", "-2"]
    }

    /// Every wrong response to try: each pair of parts but the answer, and each part with the other box empty; or, for
    /// a missing number, every wrong whole number up to 150 and some typing that isn't one.
    static func wrongResponses(for question: Question) -> [(first: String, second: String, missing: String)] {
        let answer = expectedAnswer(question)
        guard answer.count == 2 else {
            return wrongAnswers(upTo: 150, except: answer[0]).map { (first: "", second: "", missing: $0) }
        }
        let parts = typedRatioParts(for: question)
        var responses: [(first: String, second: String, missing: String)] = []
        for first in parts {
            for second in parts where !(first == String(answer[0]) && second == String(answer[1])) {
                responses.append((first: first, second: second, missing: ""))
            }
        }
        for part in parts {
            responses.append((first: part, second: "", missing: ""))
            responses.append((first: "", second: part, missing: ""))
        }
        return responses
    }

    @Test func everyQuestionIsCovered() {
        #expect(Self.allQuestions.count == 1_600)
        var problems = Problems()
        for question in Self.allQuestions {
            let shown = numbers(in: question.text)
            let name = question.text.replacingOccurrences(of: "\n", with: " ")
            // Every question works out in whole numbers, and a ratio to simplify always has a common factor.
            switch question.kind {
            case .simplify:
                problems.check(shown.count == 2 && highestCommonFactorByTrying(shown[0], shown[1]) > 1, name)
            case .share:
                problems.check(shown.count == 3 && shown[0] % (shown[1] + shown[2]) == 0, name)
            case .missingFirst:
                problems.check(shown.count == 3 && shown[0] % shown[2] == 0, name)
            case .missingSecond:
                problems.check(shown.count == 3 && shown[0] % shown[1] == 0, name)
            }
            // VoiceOver hears the same numbers as are shown.
            problems.check(numbers(in: question.spokenText) == shown, "\(name) / \(question.spokenText)")
        }
        // The generator asks nothing outside this list.
        var generator = SeededGenerator(seed: 9_008)
        var kindsSeen: [String: Int] = [:]
        for _ in 0..<10_000 {
            let question = Question.random(using: &generator)
            kindsSeen["\(question.kind)", default: 0] += 1
            problems.check(Question.ratioTerms.contains(question.first) && Question.ratioTerms.contains(question.second)
                           && Question.multipliers.contains(question.multiplier), "\(question)")
        }
        #expect(problems.found.isEmpty, problems.summary)
        #expect(kindsSeen.count == 4)
    }

    @Test func workedSolutionsGiveTheRightAnswer() {
        var problems = Problems()
        for question in Self.allQuestions {
            let shown = numbers(in: question.text)
            let answer = Self.expectedAnswer(question)
            let solution = question.workedSolution
            let name = question.text.replacingOccurrences(of: "\n", with: " ")
            problems.check(solution.steps.count >= 1 && solution.steps.count <= 4, "\(name): \(solution.steps.count) steps")
            if answer.count == 2 {
                let (x, y) = (answer[0], answer[1])
                problems.check(solution.answer == SpokenText("The answer is \(x) : \(y).", spoken: "The answer is \(x) to \(y)."),
                               "\(name): \(solution.answer)")
                problems.check(question.evaluate(first: String(x), second: String(y), missing: "") == .correct,
                               "\(name): the checker disagrees with \(x) : \(y)")
                if question.kind == .simplify {
                    // Equal to the question's ratio, and as simple as it gets.
                    problems.check(x * shown[1] == y * shown[0] && highestCommonFactorByTrying(x, y) == 1, "\(name): \(x) : \(y)")
                } else {
                    // The shares make the total, in the ratio asked for.
                    problems.check(x + y == shown[0] && x * shown[2] == y * shown[1], "\(name): \(x) : \(y)")
                }
            } else {
                let missing = answer[0]
                problems.check(solution.answer == SpokenText("The answer is \(missing)."), "\(name): \(solution.answer)")
                problems.check(question.evaluate(first: "", second: "", missing: String(missing)) == .correct,
                               "\(name): the checker disagrees with \(missing)")
                // The two ratios are equal: cross-multiplying gives the same.
                let isEqual = question.kind == .missingFirst
                    ? missing * shown[2] == shown[0] * shown[1]
                    : shown[0] * shown[2] == missing * shown[1]
                problems.check(isEqual, "\(name): \(missing)")
            }
        }
        #expect(problems.found.isEmpty, problems.summary)
    }

    @Test func everyStepIsTrue() {
        var problems = Problems()
        var wording: [String: SpokenText] = [:]
        for question in Self.allQuestions {
            let name = question.text.replacingOccurrences(of: "\n", with: " ")
            let steps = question.workedSolution.steps
            let expected = Self.expectedSteps(question)
            problems.check(steps == expected, "\(name): \(steps.map(\.text))")
            // Re-calculated from each step's own numbers.
            let stepNumbers = steps.map { numbers(in: $0.text) }
            switch question.kind {
            case .simplify:
                // "The highest common factor of A and B is H." "A ÷ H = x and B ÷ H = y."
                guard stepNumbers.count == 2, stepNumbers[0].count == 3, stepNumbers[1].count == 6 else { continue }
                let (a, b, factor) = (stepNumbers[0][0], stepNumbers[0][1], stepNumbers[0][2])
                problems.check(factor == highestCommonFactorByTrying(a, b), "\(name): \(steps[0].text)")
                let n = stepNumbers[1]
                problems.check(n[0] == a && n[1] == factor && n[0] == n[1] * n[2]
                               && n[3] == b && n[4] == factor && n[3] == n[4] * n[5], "\(name): \(steps[1].text)")
            case .share:
                // "a + b = n parts." "T ÷ n = k, so one part is k." "a × k = P and b × k = Q."
                guard stepNumbers.count == 3, stepNumbers[0].count == 3, stepNumbers[1].count == 4,
                      stepNumbers[2].count == 6 else { continue }
                let (a, b, parts) = (stepNumbers[0][0], stepNumbers[0][1], stepNumbers[0][2])
                problems.check(a + b == parts, "\(name): \(steps[0].text)")
                let n = stepNumbers[1]
                problems.check(n[1] == parts && n[2] * parts == n[0] && n[3] == n[2], "\(name): \(steps[1].text)")
                let m = stepNumbers[2]
                problems.check(m[0] == a && m[1] == n[2] && m[2] == a * m[1]
                               && m[3] == b && m[4] == n[2] && m[5] == b * m[4], "\(name): \(steps[2].text)")
            case .missingFirst, .missingSecond:
                // "b × f = B, so the ratio was multiplied by f." "a × f = A."
                guard stepNumbers.count == 2, stepNumbers[0].count == 4, stepNumbers[1].count == 3 else { continue }
                let n = stepNumbers[0]
                problems.check(n[0] * n[1] == n[2] && n[3] == n[1], "\(name): \(steps[0].text)")
                let m = stepNumbers[1]
                problems.check(m[1] == n[1] && m[0] * m[1] == m[2], "\(name): \(steps[1].text)")
            }
            for step in steps + [question.workedSolution.answer] {
                wording[step.text + "\u{0}" + step.spoken] = step
            }
        }
        #expect(problems.found.isEmpty, problems.summary)
        for step in wording.values {
            checkWording(step, maximumSentences: 1)
            #expect(![":", "+", "="].contains { step.spoken.contains($0) }, "\(step.spoken)")
        }
    }

    @Test func correctLineIsTheFinishedRatio() {
        var problems = Problems()
        for question in Self.allQuestions {
            let shown = numbers(in: question.text)
            let answer = Self.expectedAnswer(question)
            let expected: SpokenText
            switch question.kind {
            case .simplify:
                expected = SpokenText("\(shown[0]) : \(shown[1]) = \(answer[0]) : \(answer[1])",
                                      spoken: "\(shown[0]) to \(shown[1]) equals \(answer[0]) to \(answer[1])")
            case .share:
                expected = SpokenText("\(shown[0]) shared in the ratio \(shown[1]) : \(shown[2]) is \(answer[0]) : \(answer[1])",
                                      spoken: "\(shown[0]) shared in the ratio \(shown[1]) to \(shown[2]) is \(answer[0]) to \(answer[1])")
            case .missingFirst:
                expected = SpokenText("\(answer[0]) : \(shown[0]) = \(shown[1]) : \(shown[2])",
                                      spoken: "\(answer[0]) to \(shown[0]) equals \(shown[1]) to \(shown[2])")
            case .missingSecond:
                expected = SpokenText("\(shown[0]) : \(answer[0]) = \(shown[1]) : \(shown[2])",
                                      spoken: "\(shown[0]) to \(answer[0]) equals \(shown[1]) to \(shown[2])")
            }
            problems.check(question.correctLine == expected, "\(question.text): \(question.correctLine)")
        }
        #expect(problems.found.isEmpty, problems.summary)
    }

    /// A hint only uses numbers the question shows or the child typed, never shows the answer as a ratio, and never
    /// shows a missing number unless the question already does.
    @Test func hintsNeverGiveTheAnswer() {
        var problems = Problems()
        var wording: [String: SpokenText] = [:]
        var hintsChecked = 0
        var missingNumberAlreadyShown = 0
        for question in Self.allQuestions {
            let shown = numbers(in: question.text)
            let answer = Self.expectedAnswer(question)
            let name = question.text.replacingOccurrences(of: "\n", with: " ")
            var checkedHere: Set<String> = []
            let answerIsShown = answer.count == 1 && shown.contains(answer[0])
            for response in Self.wrongResponses(for: question) {
                problems.check(question.evaluate(first: response.first, second: response.second, missing: response.missing)
                               == .incorrect, "\(name): \(response)")
                let hint = question.hint(after: response)
                hintsChecked += 1
                let typed = [response.first, response.second, response.missing].compactMap(typedWholeNumber)
                problems.check(Set(numbers(in: hint.text)).isSubset(of: Set(shown).union(typed)), "\(name) \(response): \(hint.text)")
                if answerIsShown {
                    missingNumberAlreadyShown += 1
                } else if answer.count == 1 {
                    problems.check(!numbers(in: hint.text).contains(answer[0]), "\(name) \(response): \(hint.text)")
                }
                let key = hint.text + "\u{0}" + hint.spoken
                if checkedHere.insert(key).inserted {
                    problems.check(!hint.text.contains("The answer is"), "\(name): \(hint.text)")
                    problems.check(!ratioPairs(in: hint.text, separator: ":").contains(answer), "\(name): \(hint.text)")
                    problems.check(!ratioPairs(in: hint.spoken, separator: "to").contains(answer), "\(name): \(hint.spoken)")
                    if answer.count == 1, !answerIsShown {
                        problems.check(!spokenNumbersAsShown(hint.spoken).contains(answer[0]), "\(name): \(hint.spoken)")
                    }
                    wording[key] = hint
                }
            }
        }
        #expect(problems.found.isEmpty, problems.summary)
        // Simplify and share: every pair of parts but the answer, and each part with the other box empty, which comes
        // to 277,485 over the 800 questions. Missing numbers: 150 wrong whole numbers and 5 other wrong answers each.
        #expect(hintsChecked == 277_485 + 800 * 155)
        // The missing number is already in the question for 52 questions of each kind: the 40 whose ratio's two terms
        // are equal (___ : 12 = 3 : 3 gives 12), and the 12 where it equals the ratio's other term (___ : 4 = 1 : 2
        // gives 2).
        #expect(missingNumberAlreadyShown == 104 * 155)
        for hint in wording.values {
            checkWording(hint, maximumSentences: 2)
            #expect(!hint.spoken.contains(":"), "\(hint.spoken)")
        }
    }

    @Test func mistakesAreNamedOnlyWhenTheyAreTrue() {
        var problems = Problems()
        var counts: [String: Int] = [:]
        for question in Self.allQuestions {
            let shown = numbers(in: question.text)
            let answer = Self.expectedAnswer(question)
            let name = question.text.replacingOccurrences(of: "\n", with: " ")
            // The right answer is never a mistake.
            if answer.count == 2 {
                problems.check(question.mistake(in: (first: String(answer[0]), second: String(answer[1]), missing: "")) == nil, name)
                problems.check(question.mistake(in: (first: " \(answer[0])", second: "\(answer[1]) ", missing: "")) == nil, name)
            } else {
                problems.check(question.mistake(in: (first: "", second: "", missing: String(answer[0]))) == nil, name)
            }
            for response in Self.wrongResponses(for: question) {
                let found = question.mistake(in: response)
                let expected = Self.expectedMistake(question, first: response.first, second: response.second,
                                                    missing: response.missing)
                problems.check(found == expected, "\(name) \(response): \(String(describing: found))")
                guard let found else { continue }
                counts["\(found)", default: 0] += 1
                // What each hint says about the mistake is true.
                let typed = [response.first, response.second].compactMap(typedWholeNumber)
                switch found {
                case .reversed:
                    problems.check(typed == [answer[1], answer[0]] && answer[0] != answer[1], "\(name): \(response)")
                case .notSimplest:
                    // "p : q is equal to A : B, but it can be simplified more."
                    problems.check(typed.count == 2 && typed[0] * shown[1] == typed[1] * shown[0]
                                   && highestCommonFactorByTrying(typed[0], typed[1]) > 1, "\(name): \(response)")
                case .sameAsQuestion:
                    problems.check(typed == shown, "\(name): \(response)")
                case .gaveRatio:
                    problems.check(typed == [shown[1], shown[2]], "\(name): \(response)")
                case .added:
                    // The difference between the term shown and its partner added to the other term.
                    let typedMissing = typedWholeNumber(response.missing) ?? -1
                    let difference = question.kind == .missingFirst ? shown[0] - shown[2] : shown[0] - shown[1]
                    let other = question.kind == .missingFirst ? shown[1] : shown[2]
                    problems.check(typedMissing == other + difference && typedMissing != answer[0], "\(name): \(response)")
                case .oneBoxEmpty:
                    problems.check(response.first.isEmpty != response.second.isEmpty, "\(name): \(response)")
                }
                // A ratio of two equal numbers is never "the wrong way round", and a missing number never "added".
                if question.first == question.second {
                    problems.check(found != .reversed && found != .added, "\(name): \(found)")
                }
            }
        }
        #expect(problems.found.isEmpty, problems.summary)
        // Reversed: the 360 simplify and 360 share questions whose answer's two numbers differ. The question's own
        // ratio typed back, and the ratio given as the shares: once for each of the 400 questions. Added: the 360
        // questions of each missing kind whose terms differ (when they're equal, adding gives the right answer).
        #expect(counts == ["oneBoxEmpty": 28_250, "reversed": 720, "sameAsQuestion": 400, "notSimplest": 768,
                           "gaveRatio": 400, "added": 720])

        // Every equal ratio between the answer and the question's own is named as not yet simplest, and its hint
        // shows the two ratios.
        var notSimplest = 0
        for question in Self.allQuestions where question.kind == .simplify {
            let shown = numbers(in: question.text)
            let answer = Self.expectedAnswer(question)
            let factor = highestCommonFactorByTrying(shown[0], shown[1])
            for k in stride(from: 2, to: factor, by: 1) {
                let (p, q) = (answer[0] * k, answer[1] * k)
                let response = (first: String(p), second: String(q), missing: "")
                problems.check(question.mistake(in: response) == .notSimplest, "\(question.text): \(p) : \(q)")
                let rest = ", but it can be simplified more. Look for a bigger number that divides both."
                problems.check(question.hint(after: response)
                               == SpokenText("\(p) : \(q) is equal to \(shown[0]) : \(shown[1])\(rest)",
                                             spoken: "\(p) to \(q) is equal to \(shown[0]) to \(shown[1])\(rest)"),
                               "\(question.text): \(p) : \(q)")
                notSimplest += 1
            }
        }
        #expect(notSimplest == 1_846)
        #expect(problems.found.isEmpty, problems.summary)
    }

    @Test func goldenExamples() {
        let strategy = "Find the biggest number that divides into both 8 and 12."
        let simplify = Question(kind: .simplify, first: 2, second: 3, multiplier: 4)
        #expect(simplify.text == "Simplify the ratio 8 : 12")
        #expect(simplify.hint(after: (first: "5", second: "5", missing: "")) == SpokenText(strategy))
        #expect(simplify.hint(after: (first: "3", second: "2", missing: ""))
                == SpokenText("The numbers are the wrong way round. Keep them in the same order as the question."))
        #expect(simplify.hint(after: (first: "4", second: "6", missing: "")) == SpokenText(
            "4 : 6 is equal to 8 : 12, but it can be simplified more. Look for a bigger number that divides both.",
            spoken: "4 to 6 is equal to 8 to 12, but it can be simplified more. Look for a bigger number that divides both."))
        #expect(simplify.hint(after: (first: "8", second: "12", missing: ""))
                == SpokenText("That is the ratio from the question. \(strategy)"))
        #expect(simplify.hint(after: (first: "2", second: "", missing: ""))
                == SpokenText("Fill in both parts of the ratio. \(strategy)"))
        #expect(simplify.workedSolution == WorkedSolution(
            steps: [SpokenText("The highest common factor of 8 and 12 is 4."),
                    SpokenText("8 ÷ 4 = 2 and 12 ÷ 4 = 3.", spoken: "8 divided by 4 equals 2 and 12 divided by 4 equals 3.")],
            answer: SpokenText("The answer is 2 : 3.", spoken: "The answer is 2 to 3.")))
        #expect(simplify.correctLine == SpokenText("8 : 12 = 2 : 3", spoken: "8 to 12 equals 2 to 3"))

        // 6 : 12 was made from 2 : 4, but simplifies all the way to 1 : 2.
        let sixTwelve = Question(kind: .simplify, first: 2, second: 4, multiplier: 3)
        #expect(sixTwelve.text == "Simplify the ratio 6 : 12")
        #expect(sixTwelve.workedSolution.steps[0].text == "The highest common factor of 6 and 12 is 6.")
        #expect(sixTwelve.workedSolution.answer.text == "The answer is 1 : 2.")
        #expect(sixTwelve.mistake(in: (first: "2", second: "4", missing: "")) == .notSimplest)
        #expect(sixTwelve.mistake(in: (first: "3", second: "6", missing: "")) == .notSimplest)

        let share = Question(kind: .share, first: 3, second: 4, multiplier: 5)
        #expect(share.text == "Divide 35 in the ratio 3 : 4")
        #expect(share.hint(after: (first: "20", second: "15", missing: ""))
                == SpokenText("The numbers are the wrong way round. Keep them in the same order as the question."))
        #expect(share.hint(after: (first: "3", second: "4", missing: ""))
                == SpokenText("That is the ratio. Work out how much one part is worth."))
        #expect(share.hint(after: (first: "10", second: "25", missing: ""))
                == SpokenText("Add the numbers in the ratio to find how many equal parts there are."))
        #expect(share.workedSolution == WorkedSolution(
            steps: [SpokenText("3 + 4 = 7 parts.", spoken: "3 plus 4 equals 7 parts."),
                    SpokenText("35 ÷ 7 = 5, so one part is 5.", spoken: "35 divided by 7 equals 5, so one part is 5."),
                    SpokenText("3 × 5 = 15 and 4 × 5 = 20.", spoken: "3 times 5 equals 15 and 4 times 5 equals 20.")],
            answer: SpokenText("The answer is 15 : 20.", spoken: "The answer is 15 to 20.")))
        #expect(share.correctLine == SpokenText("35 shared in the ratio 3 : 4 is 15 : 20",
                                                spoken: "35 shared in the ratio 3 to 4 is 15 to 20"))

        let missingFirst = Question(kind: .missingFirst, first: 2, second: 3, multiplier: 4)
        #expect(missingFirst.text == "Find the missing number.\n___ : 12 = 2 : 3")
        // 2 + (12 − 3) = 11.
        #expect(missingFirst.hint(after: (first: "", second: "", missing: "11"))
                == SpokenText("Ratios grow by multiplying, not adding. What do you multiply 3 by to get 12?"))
        #expect(missingFirst.hint(after: (first: "", second: "", missing: "5"))
                == SpokenText("What do you multiply 3 by to get 12? Do the same to 2."))
        #expect(missingFirst.workedSolution == WorkedSolution(
            steps: [SpokenText("3 × 4 = 12, so the ratio was multiplied by 4.",
                               spoken: "3 times 4 equals 12, so the ratio was multiplied by 4."),
                    SpokenText("2 × 4 = 8.", spoken: "2 times 4 equals 8.")],
            answer: SpokenText("The answer is 8.")))
        #expect(missingFirst.correctLine == SpokenText("8 : 12 = 2 : 3", spoken: "8 to 12 equals 2 to 3"))

        let missingSecond = Question(kind: .missingSecond, first: 2, second: 3, multiplier: 4)
        #expect(missingSecond.text == "Find the missing number.\n8 : ___ = 2 : 3")
        // 3 + (8 − 2) = 9.
        #expect(missingSecond.mistake(in: (first: "", second: "", missing: "9")) == .added)
        #expect(missingSecond.hint(after: (first: "", second: "", missing: "9"))
                == SpokenText("Ratios grow by multiplying, not adding. What do you multiply 2 by to get 8?"))
        #expect(missingSecond.workedSolution.answer == SpokenText("The answer is 12."))
    }
}

// MARK: - The message after Enter

@Suite("Stage 9C: what is read out after Enter")
struct Stage9CAnnouncementTests {
    @Test func correctIsReadWithItsNumberSentence() {
        let text = AnswerFeedbackText(message: "Correct!",
                                      detail: SpokenText("4 × 5 = 20", spoken: "4 times 5 equals 20"))
        #expect(text.announcement == "Correct! 4 times 5 equals 20")
    }

    @Test func incorrectIsReadWithItsHint() {
        let text = AnswerFeedbackText(message: "Incorrect. Try Again!", alsoSaying: "Hint: 4 groups of 5. Count in fives.")
        #expect(text.announcement == "Incorrect. Try Again! Hint: 4 groups of 5. Count in fives.")
    }

    @Test func otherActivitiesAreReadAsBefore() {
        #expect(AnswerFeedbackText(message: "Please enter an answer!").announcement == "Please enter an answer!")
        #expect(AnswerFeedbackText(message: "Incorrect. Try Again!").announcement == "Incorrect. Try Again!")
        #expect(AnswerFeedbackText(message: "").announcement == "")
    }
}

// MARK: - Attempts

@Suite("Stage 9C: attempts around a worked solution")
struct Stage9CAttemptTests {
    /// After Skip, while the solution shows, Enter, Return and a second Skip do nothing, so no point can be scored.
    @Test func nothingCountsWhileASolutionShows() {
        var progress = QuestionProgress()
        #expect(!progress.showSkipButton)
        progress.recordWrongAttempt()
        #expect(!progress.showSkipButton)
        progress.recordWrongAttempt()
        #expect(progress.showSkipButton)
        let skipped = progress.recordSkip()
        #expect(skipped)
        #expect(!progress.showSkipButton)
        let skippedAgain = progress.recordSkip()
        let scored = progress.recordCorrectAnswer()
        let enteredRight = progress.recordSubmission(isCorrect: true)
        let enteredWrong = progress.recordSubmission(isCorrect: false)
        #expect(!skippedAgain)
        #expect(!scored)
        #expect(enteredRight == .ignored)
        #expect(enteredWrong == .ignored)
        progress.recordWrongAttempt()
        #expect(progress.wrongAttempts == 2)
        progress.reset()
        #expect(progress == QuestionProgress())
    }
}
