//
//  Year5Year6CorrectnessTests.swift
//  Maths QuestTests
//
//  Regression tests for the Year 5 Volume and Statistics questions, the Year 6 Probability and
//  Ratios questions, and the per-question progress used by all four. Everything here
//  is pure maths and state, so it runs without the simulator UI, StoreKit or Firebase.
//

import Foundation
import Testing
@testable import Maths_Quest

/// The whole numbers in a question's text, in order, so the tests can check what is shown on screen
/// against the answer key.
private func wholeNumbers(in text: String) -> [Int] {
    text.split(whereSeparator: { !($0.isASCII && $0.isNumber) }).compactMap { Int($0) }
}

// MARK: - Typed answers

struct TypedAnswerTests {
    private func decimal(_ text: String) -> [Int]? {
        TypedAnswer.exactDecimal(text).map { [$0.numerator, $0.denominator] }
    }

    @Test func wholeNumberParsing() {
        #expect(TypedAnswer.wholeNumber("0") == 0)
        #expect(TypedAnswer.wholeNumber("7") == 7)
        #expect(TypedAnswer.wholeNumber(" 12 ") == 12)
        #expect(TypedAnswer.wholeNumber("\n42\t") == 42)
        #expect(TypedAnswer.wholeNumber("007") == 7)
        #expect(TypedAnswer.wholeNumber("\(Int.max)") == Int.max)

        let rejected = ["", " ", "7.0", "7,0", "-3", "+3", "1e3", "7abc", "1 2", "0x1F", "∞",
                        "²", "½", "７", "١٢", "99999999999999999999"]
        for text in rejected {
            #expect(TypedAnswer.wholeNumber(text) == nil, "\(text)")
        }
    }

    @Test func exactDecimalParsing() {
        let accepted: [(String, [Int])] = [
            ("7", [7, 1]), ("7.0", [7, 1]), ("7,00", [7, 1]), ("07", [7, 1]),
            ("7.5", [15, 2]), ("7,5", [15, 2]), ("7.50", [15, 2]),
            (".5", [1, 2]), ("5.", [5, 1]), ("0.25", [1, 4]), (" 2.35 ", [47, 20]),
            ("0", [0, 1]), ("000", [0, 1]), ("0.0", [0, 1]),
            ("0000000000000000000000007", [7, 1]),
            ("1.000000000000000000000000", [1, 1]),
            ("0.000000000000000001", [1, 1_000_000_000_000_000_000]),
        ]
        for (text, fraction) in accepted {
            #expect(decimal(text) == fraction, "\(text)")
        }

        let rejected = ["", " ", ".", ",", "..", "1.2.3", "1,2.3", "1.2,3", "-3", "+3", "-0.5",
                        "1e3", "1.5e2", "7abc", "7 .5", "1 000", "0x10", "inf", "nan", "½", "١٫٥",
                        "0.0000000000000000001", "99999999999999999999", "9999999999.999999999"]
        for text in rejected {
            #expect(decimal(text) == nil, "\(text)")
        }
    }

    @Test func numbersAreComparedExactly() {
        for text in ["7", "7.0", "07", "7,000", " 7 "] {
            #expect(TypedAnswer.isNumber(text, equalTo: 7), "\(text)")
        }
        for text in ["7.01", "6.99999", "70", "", "seven", "7/1"] {
            #expect(!TypedAnswer.isNumber(text, equalTo: 7), "\(text)")
        }
        #expect(TypedAnswer.isNumber("7.5", equalTo: 15, over: 2))
        #expect(TypedAnswer.isNumber("7.5", equalTo: 75, over: 10))
        #expect(!TypedAnswer.isNumber("7.49", equalTo: 15, over: 2))
    }

    @Test func fractionComparison() {
        #expect(TypedAnswer.fractionsAreEqual(2, 8, 1, 4))
        #expect(TypedAnswer.fractionsAreEqual(1, 4, 2, 8))
        #expect(TypedAnswer.fractionsAreEqual(0, 5, 0, 7))
        #expect(TypedAnswer.fractionsAreEqual(3, 3, 1, 1))
        #expect(!TypedAnswer.fractionsAreEqual(1, 4, 1, 3))

        // Zero and negative denominators, and negative numerators, are never equal to anything.
        #expect(!TypedAnswer.fractionsAreEqual(1, 0, 1, 0))
        #expect(!TypedAnswer.fractionsAreEqual(1, 0, 2, 0))
        #expect(!TypedAnswer.fractionsAreEqual(0, 0, 0, 0))
        #expect(!TypedAnswer.fractionsAreEqual(-1, 4, -1, 4))
        #expect(!TypedAnswer.fractionsAreEqual(1, -4, 1, -4))

        // Nothing is multiplied, so the largest values can't overflow.
        #expect(TypedAnswer.fractionsAreEqual(Int.max, Int.max, 1, 1))
        #expect(TypedAnswer.fractionsAreEqual(Int.max, 1, Int.max, 1))
        #expect(!TypedAnswer.fractionsAreEqual(Int.max - 1, Int.max, 1, 1))
    }

    @Test func greatestCommonDivisor() {
        #expect(TypedAnswer.greatestCommonDivisor(12, 18) == 6)
        #expect(TypedAnswer.greatestCommonDivisor(18, 12) == 6)
        #expect(TypedAnswer.greatestCommonDivisor(-12, 18) == 6)
        #expect(TypedAnswer.greatestCommonDivisor(17, 5) == 1)
        #expect(TypedAnswer.greatestCommonDivisor(7, 0) == 7)
        #expect(TypedAnswer.greatestCommonDivisor(0, 7) == 7)
        #expect(TypedAnswer.greatestCommonDivisor(0, 0) == 0)
        // Int.min has no positive Int counterpart, which used to trap.
        #expect(TypedAnswer.greatestCommonDivisor(Int.min, 6) == 2)
        #expect(TypedAnswer.greatestCommonDivisor(Int.min, 0) == Int.max)
        #expect(TypedAnswer.greatestCommonDivisor(Int.min, Int.min) == Int.max)
    }
}

// MARK: - Year 5 Volume (MQ-09)

struct Year5VolumeQuestionTests {
    private func glasses(_ glassA: Int, _ glassB: Int) -> Year5VolumeQuestion {
        Year5VolumeQuestion(kind: .comparison, length: 0, width: 0, height: 0,
                            glassAMillilitres: glassA, glassBMillilitres: glassB)
    }

    private func solid(_ kind: Year5VolumeQuestion.Kind, _ length: Int, _ width: Int, _ height: Int) -> Year5VolumeQuestion {
        Year5VolumeQuestion(kind: kind, length: length, width: width, height: height,
                            glassAMillilitres: 0, glassBMillilitres: 0)
    }

    /// MQ-09: the answer was checked with Int(answer) == Int("A" or "B"). Both sides were nil, so
    /// any text that wasn't a whole number was marked correct.
    @Test func comparisonAcceptsOnlyTheFullerGlass() {
        let bHasMore = glasses(1500, 2350)
        let aHasMore = glasses(2400, 2350)
        #expect(bHasMore.glassWithMore == "B")
        #expect(aHasMore.glassWithMore == "A")

        for answer in ["B", "b", " B ", "B\n"] {
            #expect(bHasMore.isCorrect(answer: answer), "\(answer)")
            #expect(!aHasMore.isCorrect(answer: answer), "\(answer)")
        }
        for answer in ["A", "a", " a "] {
            #expect(aHasMore.isCorrect(answer: answer), "\(answer)")
            #expect(!bHasMore.isCorrect(answer: answer), "\(answer)")
        }
    }

    @Test func comparisonRejectsAnythingThatIsntAOrB() {
        let rejected = ["", " ", "C", "AB", "BA", "A or B", "B.", "BB", "glass B", "Β", "ｂ",
                        "2350", "2.35", "1500", "0", "yes", "?", "😀"]
        for question in [glasses(1500, 2350), glasses(2400, 2350)] {
            for answer in rejected {
                #expect(!question.isCorrect(answer: answer), "\(answer)")
            }
        }
    }

    @Test func equalGlassesHaveNoCorrectAnswer() {
        let question = glasses(2000, 2000)
        #expect(question.glassWithMore == nil)
        #expect(!question.isCorrect(answer: "A"))
        #expect(!question.isCorrect(answer: "B"))
    }

    @Test func millilitresAreWrittenAsExactLitres() {
        let cases: [(Int, String)] = [(0, "0"), (10, "0.01"), (500, "0.5"), (990, "0.99"), (1000, "1"),
                                      (2005, "2.005"), (2050, "2.05"), (2350, "2.35"), (5000, "5"), (5490, "5.49")]
        for (millilitres, litres) in cases {
            #expect(Year5VolumeQuestion.litres(fromMillilitres: millilitres) == litres)
        }
    }

    /// MQ-09: glass B was stored as Int(litres), so 2.35 L was shown and marked as 2 L, which made
    /// 2100 mL look like more.
    @Test func glassBIsNotTruncatedToWholeLitres() {
        let question = glasses(2100, 2350)
        #expect(question.text == "Glass A has 2100 mL. Glass B has 2.35 L. Which has more liquid? \n A or B?")
        #expect(question.isCorrect(answer: "B"))
        #expect(!question.isCorrect(answer: "A"))
    }

    @Test func cubeAndCuboidVolumesAreInCubicCentimetres() {
        let cube = solid(.cube, 5, 5, 5)
        #expect(cube.volume == 125)
        #expect(cube.text == "What is the volume of this cube?")
        for answer in ["125", " 125 ", "0125", "125.0", "125,0", "125.000"] {
            #expect(cube.isCorrect(answer: answer), "\(answer)")
        }
        for answer in ["", "124", "126", "125.5", "12.5", "125cm³", "125 cm", "1.25e2", "-125", "+125",
                       "25", "15", "A", "B"] {
            #expect(!cube.isCorrect(answer: answer), "\(answer)")
        }

        let cuboid = solid(.cuboid, 2, 3, 4)
        #expect(cuboid.volume == 24)
        #expect(cuboid.text == "What is the volume of this cuboid?")
        #expect(cuboid.isCorrect(answer: "24"))
        #expect(!cuboid.isCorrect(answer: "9"))  // 2 + 3 + 4
        #expect(!cuboid.isCorrect(answer: "52")) // the surface area
    }

    @Test func everyCuboidIsLengthTimesWidthTimesHeight() {
        var mistakes = [String]()
        let edges = Year5VolumeQuestion.edgeLengths
        for length in edges {
            for width in edges {
                for height in edges {
                    let question = solid(.cuboid, length, width, height)
                    let volume = length * width * height
                    if !question.isCorrect(answer: "\(volume)")
                        || question.isCorrect(answer: "\(volume + 1)")
                        || question.isCorrect(answer: "\(volume - 1)") {
                        mistakes.append("\(length)×\(width)×\(height)")
                    }
                }
            }
        }
        #expect(mistakes.isEmpty, "\(mistakes.prefix(10))")
    }

    @Test func generatedQuestionsAlwaysHaveOneCorrectAnswer() throws {
        var generator = SeededGenerator(seed: 0x3B_0009)
        var kinds = Set<Year5VolumeQuestion.Kind>()
        var fullerGlasses = [String: Int]()

        for _ in 0..<10_000 {
            let question = Year5VolumeQuestion.random(using: &generator)
            kinds.insert(question.kind)

            switch question.kind {
            case .cube, .cuboid:
                #expect(Year5VolumeQuestion.edgeLengths.contains(question.length))
                #expect(Year5VolumeQuestion.edgeLengths.contains(question.width))
                #expect(Year5VolumeQuestion.edgeLengths.contains(question.height))
                if question.kind == .cube {
                    #expect(question.length == question.width && question.width == question.height)
                }
                let volume = question.length * question.width * question.height
                #expect(question.isCorrect(answer: "\(volume)"))
                #expect(!question.isCorrect(answer: "\(volume + 1)"))
                #expect(!question.isCorrect(answer: "A"))
                #expect(!question.isCorrect(answer: "B"))

            case .comparison:
                let glassA = question.glassAMillilitres
                let glassB = question.glassBMillilitres
                #expect(glassA != glassB)
                #expect(glassA % 10 == 0 && glassB % 10 == 0)
                #expect((500...5490).contains(glassA) && (500...5490).contains(glassB))
                #expect((100...490).contains(abs(glassA - glassB)))

                // What's on screen is exactly what's marked.
                let litres = Year5VolumeQuestion.litres(fromMillilitres: glassB)
                #expect(question.text.contains("Glass A has \(glassA) mL."))
                #expect(question.text.contains("Glass B has \(litres) L."))
                let shown = try #require(TypedAnswer.exactDecimal(litres))
                #expect(TypedAnswer.fractionsAreEqual(shown.numerator, shown.denominator, glassB, 1000))

                let fuller = try #require(question.glassWithMore)
                #expect(fuller == (glassA > glassB ? "A" : "B"))
                #expect(question.isCorrect(answer: fuller))
                #expect(!question.isCorrect(answer: fuller == "A" ? "B" : "A"))
                #expect(!question.isCorrect(answer: "C"))
                fullerGlasses[fuller, default: 0] += 1
            }
        }

        #expect(kinds.count == 3)
        #expect(fullerGlasses["A", default: 0] > 1_000)
        #expect(fullerGlasses["B", default: 0] > 1_000)
    }
}

// MARK: - Year 5 Statistics (MQ-13)

struct Year5StatisticsQuestionTests {
    private func question(_ kind: Year5StatisticsQuestion.Kind, _ numbers: [Int]) -> Year5StatisticsQuestion {
        Year5StatisticsQuestion(kind: kind, numbers: numbers, bars: [:])
    }

    private func barChart(_ bars: [String: Int]) -> Year5StatisticsQuestion {
        Year5StatisticsQuestion(kind: .highestBar, numbers: [], bars: bars)
    }

    /// MQ-13: the mean was compared with String(format: "%.1f"), so "7" was marked wrong when the
    /// mean was 7.0, and "7,5" was always wrong.
    @Test func meanAcceptsEquivalentNumbers() {
        let mean = question(.mean, [5, 6, 7, 8, 9, 5, 6, 7, 8, 9])
        #expect(mean.text == "Find the mean (average) of: 5, 6, 7, 8, 9, 5, 6, 7, 8, 9")
        for answer in ["7", "7.0", "7,0", "7.00", " 7 ", "07"] {
            #expect(mean.isCorrect(answer: answer), "\(answer)")
        }
        for answer in ["", "7.1", "6.9", "70", "6", "8", "seven", "7/1", "7.0.0", "-7"] {
            #expect(!mean.isCorrect(answer: answer), "\(answer)")
        }
    }

    @Test func meanWithADecimal() {
        let sevenAndAHalf = question(.mean, [10, 5, 7, 8, 9, 6, 7, 8, 9, 6])
        for answer in ["7.5", "7,5", "7.50", "07.5"] {
            #expect(sevenAndAHalf.isCorrect(answer: answer), "\(answer)")
        }
        for answer in ["7", "8", "7.4", "7.6", "75", "7.55", ".75"] {
            #expect(!sevenAndAHalf.isCorrect(answer: answer), "\(answer)")
        }

        let sevenPointThree = question(.mean, [10, 5, 7, 8, 9, 6, 7, 8, 9, 4])
        #expect(sevenPointThree.isCorrect(answer: "7.3"))
        #expect(sevenPointThree.isCorrect(answer: "7,30"))
        for answer in ["7", "7.29", "7.31", "7.33"] {
            #expect(!sevenPointThree.isCorrect(answer: answer), "\(answer)")
        }
    }

    /// There's no tolerance: only the exact mean is correct. The generator always uses ten whole
    /// numbers, so its means never need more than one decimal place.
    @Test func meanHasNoTolerance() {
        let fourThirds = question(.mean, [1, 1, 2])
        for answer in ["1", "1.3", "1.33", "1.333333", "1.34"] {
            #expect(!fourThirds.isCorrect(answer: answer), "\(answer)")
        }
        #expect(question(.mean, []).mean?.numerator == nil)
        #expect(!question(.mean, []).isCorrect(answer: "0"))
    }

    @Test func modeWithRepeats() {
        let mode = question(.mode, [3, 7, 7, 2, 7, 5, 3, 1, 9, 10])
        #expect(mode.text == "Find the mode (most frequent number) in: 3, 7, 7, 2, 7, 5, 3, 1, 9, 10")
        #expect(mode.mode == 7)
        for answer in ["7", "7.0", " 7"] {
            #expect(mode.isCorrect(answer: answer), "\(answer)")
        }
        for answer in ["", "3", "77", "7.5", "seven", "10"] {
            #expect(!mode.isCorrect(answer: answer), "\(answer)")
        }
    }

    /// MQ-13: findMode took whichever tied number the dictionary happened to list first.
    @Test func tiedModesHaveNoAnswer() {
        let tie = question(.mode, [1, 1, 2, 2, 3, 4, 5, 6, 7, 8])
        #expect(tie.mode == nil)
        for value in 1...8 {
            #expect(!tie.isCorrect(answer: "\(value)"))
        }
        #expect(question(.mode, Array(1...10)).mode == nil)
        #expect(question(.mode, []).mode == nil)
    }

    @Test func barChartQuestion() {
        let chart = barChart(["A": 3, "B": 9, "C": 5, "D": 1])
        #expect(chart.text == "Which category has the highest value?")
        #expect(chart.highestCategory == "B")
        for answer in ["B", "b", " b "] {
            #expect(chart.isCorrect(answer: answer), "\(answer)")
        }
        for answer in ["", "A", "C", "D", "9", "BB", "Β"] {
            #expect(!chart.isCorrect(answer: answer), "\(answer)")
        }

        let tie = barChart(["A": 9, "B": 9, "C": 5, "D": 1])
        #expect(tie.highestCategory == nil)
        #expect(!tie.isCorrect(answer: "A"))
        #expect(!tie.isCorrect(answer: "B"))
    }

    /// MQ-13: the old generator could give another number as many repeats as the intended mode, or
    /// more.
    @Test func generatedModeQuestionsHaveOneUnambiguousMode() throws {
        var generator = SeededGenerator(seed: 0x3B_0013)
        var modesSeen = Set<Int>()
        var modeCountsSeen = Set<Int>()

        for _ in 0..<10_000 {
            let numbers = Year5StatisticsQuestion.datasetForMode(using: &generator)
            let mode = question(.mode, numbers)
            #expect(numbers.count == Year5StatisticsQuestion.datasetSize)
            #expect(numbers.allSatisfy { (1...10).contains($0) })
            #expect(wholeNumbers(in: mode.text) == numbers)

            let counts = Dictionary(grouping: numbers, by: { $0 }).mapValues(\.count)
            let answer = try #require(mode.mode)
            let answerCount = try #require(counts[answer])
            #expect((3...5).contains(answerCount))
            #expect(counts.allSatisfy { $0.key == answer || $0.value < answerCount })

            #expect(mode.isCorrect(answer: "\(answer)"))
            for other in counts.keys where other != answer {
                #expect(!mode.isCorrect(answer: "\(other)"))
            }
            modesSeen.insert(answer)
            modeCountsSeen.insert(answerCount)
        }

        // Every mode and every number of repeats still turns up.
        #expect(modesSeen == Set(1...10))
        #expect(modeCountsSeen == [3, 4, 5])
    }

    @Test func generatedMeanQuestionsMarkTheirExactMean() {
        var generator = SeededGenerator(seed: 0x3B_0113)
        var mistakes = [String]()

        for _ in 0..<10_000 {
            let numbers = Year5StatisticsQuestion.datasetForMean(using: &generator)
            let mean = question(.mean, numbers)
            let sum = numbers.reduce(0, +)
            let oneDecimalPlace = "\(sum / 10).\(sum % 10)"

            let ok = numbers.count == 10
                && numbers.allSatisfy { (1...20).contains($0) }
                && wholeNumbers(in: mean.text) == numbers
                && mean.isCorrect(answer: oneDecimalPlace)
                && mean.isCorrect(answer: oneDecimalPlace.replacingOccurrences(of: ".", with: ","))
                && (sum % 10 != 0 || mean.isCorrect(answer: "\(sum / 10)"))
                && (sum % 10 == 0 || !mean.isCorrect(answer: "\(sum / 10)"))
                && !mean.isCorrect(answer: "\(sum / 10).\(sum % 10 + 1)")
                && !mean.isCorrect(answer: "\(sum)")
            if !ok {
                mistakes.append("\(numbers)")
            }
        }
        #expect(mistakes.isEmpty, "\(mistakes.prefix(10))")
    }

    @Test func generatedQuestionsShowWhatIsMarked() throws {
        var generator = SeededGenerator(seed: 0x3B_0213)
        var kinds = Set<Year5StatisticsQuestion.Kind>()
        var leaders = Set<String>()

        for _ in 0..<10_000 {
            let question = Year5StatisticsQuestion.random(using: &generator)
            kinds.insert(question.kind)

            switch question.kind {
            case .mean, .mode:
                #expect(question.bars.isEmpty)
                #expect(question.numbers.count == Year5StatisticsQuestion.datasetSize)
                #expect(wholeNumbers(in: question.text) == question.numbers)
                if question.kind == .mode {
                    #expect(question.mode != nil)
                }

            case .highestBar:
                #expect(question.numbers.isEmpty)
                #expect(Set(question.bars.keys) == Set(Year5StatisticsQuestion.categories))
                #expect(Set(question.bars.values).count == Year5StatisticsQuestion.categories.count)
                #expect(question.bars.values.allSatisfy { (1...15).contains($0) })

                let leader = try #require(question.highestCategory)
                #expect(question.bars[leader] == question.bars.values.max())
                for category in Year5StatisticsQuestion.categories {
                    #expect(question.isCorrect(answer: category) == (category == leader))
                    #expect(question.isCorrect(answer: category.lowercased()) == (category == leader))
                }
                leaders.insert(leader)
            }
        }

        #expect(kinds.count == 3)
        #expect(leaders == Set(Year5StatisticsQuestion.categories))
    }
}

// MARK: - Year 6 Probability (MQ-10)

struct Year6ProbabilityQuestionTests {
    typealias Question = Year6ProbabilityQuestion

    /// Every question the generator can make.
    static let everyQuestion: [Question] = {
        var all = [Question]()
        for faces in 4...10 {
            for target in 1...faces {
                all.append(.die(faces: faces, target: target))
            }
        }
        for total in 5...20 {
            for selected in 1..<total {
                all += [.spinner(sections: total, blue: selected),
                        .marbles(total: total, red: selected),
                        .cards(total: total, aces: selected)]
            }
        }
        for flips in 1...3 {
            all.append(.coin(flips: flips))
        }
        return all
    }()

    @Test func eachKindHasItsOwnProbability() {
        let die = Question.die(faces: 6, target: 3)
        #expect(die.text == "A fair die has 6 faces, numbered 1 to 6. Each number is equally likely to be rolled. "
                + "What is the probability of rolling a 3?")
        #expect(die.evaluate(numerator: "1", denominator: "6") == .correct)
        #expect(die.evaluate(numerator: "2", denominator: "12") == .correct)
        #expect(die.evaluate(numerator: "3", denominator: "6") == .incorrect)

        let spinner = Question.spinner(sections: 8, blue: 3)
        #expect(spinner.text == "A spinner has 8 equal sections. 3 are blue. What is the probability of landing on blue?")
        #expect(spinner.evaluate(numerator: "3", denominator: "8") == .correct)
        #expect(spinner.evaluate(numerator: "6", denominator: "16") == .correct)
        #expect(spinner.evaluate(numerator: "1", denominator: "8") == .incorrect)
        #expect(spinner.evaluate(numerator: "5", denominator: "8") == .incorrect)
        #expect(spinner.evaluate(numerator: "8", denominator: "3") == .incorrect)

        let coin = Question.coin(flips: 3)
        #expect(coin.text == "A fair coin is flipped 3 times. What is the probability of getting heads every time?")
        #expect(coin.evaluate(numerator: "1", denominator: "8") == .correct)
        #expect(coin.evaluate(numerator: "2", denominator: "16") == .correct)
        #expect(coin.evaluate(numerator: "1", denominator: "2") == .incorrect)
        #expect(coin.evaluate(numerator: "3", denominator: "8") == .incorrect)
        #expect(coin.evaluate(numerator: "1", denominator: "6") == .incorrect)
        #expect(Question.coin(flips: 1).evaluate(numerator: "2", denominator: "4") == .correct)

        let marbles = Question.marbles(total: 12, red: 4)
        #expect(marbles.text == "A bag contains 12 marbles. 4 are red. What is the probability of drawing a red marble?")
        #expect(marbles.evaluate(numerator: "4", denominator: "12") == .correct)
        #expect(marbles.evaluate(numerator: "1", denominator: "3") == .correct)
        #expect(marbles.evaluate(numerator: "4", denominator: "8") == .incorrect)
        #expect(marbles.evaluate(numerator: "8", denominator: "12") == .incorrect)

        let cards = Question.cards(total: 20, aces: 5)
        #expect(cards.text == "A stack of 20 cards has 5 aces. What is the probability of drawing an ace?")
        #expect(cards.evaluate(numerator: "5", denominator: "20") == .correct)
        #expect(cards.evaluate(numerator: "1", denominator: "4") == .correct)
        #expect(cards.evaluate(numerator: "1", denominator: "13") == .incorrect)
        #expect(cards.evaluate(numerator: "5", denominator: "15") == .incorrect)
    }

    /// MQ-10: every question accepted selected/total, 1/dice and 1/2^flips from shared state, so
    /// the answer to one kind of question was marked correct on another.
    @Test func answersToOtherQuestionsAreRejected() {
        var mistakes = [String]()
        for question in Self.everyQuestion {
            let expected = question.probability
            for other in Self.everyQuestion {
                let answer = other.probability
                let sameProbability = expected.numerator * answer.denominator == answer.numerator * expected.denominator
                let marked = question.evaluate(numerator: "\(answer.numerator)", denominator: "\(answer.denominator)")
                if marked != (sameProbability ? .correct : .incorrect) {
                    mistakes.append("\(question.text) \(answer.numerator)/\(answer.denominator)")
                }
            }
        }
        #expect(mistakes.isEmpty, "\(mistakes.prefix(10))")
    }

    @Test func everyQuestionAcceptsExactlyTheEquivalentFractions() {
        let numerators = (0...30).map { "\($0)" }
        let denominators = (0...40).map { "\($0)" }
        var mistakes = [String]()

        for question in Self.everyQuestion {
            let expected = question.probability
            for top in 0...30 {
                for bottom in 1...40 {
                    let equal = top * expected.denominator == bottom * expected.numerator
                    let marked = question.evaluate(numerator: numerators[top], denominator: denominators[bottom])
                    if marked != (equal ? .correct : .incorrect) {
                        mistakes.append("\(question.text) \(top)/\(bottom)")
                    }
                }
            }
        }
        #expect(mistakes.isEmpty, "\(mistakes.prefix(10))")
    }

    @Test func invalidInputIsNeitherCorrectNorIncorrect() {
        let question = Question.die(faces: 6, target: 2)
        let invalid: [(String, String)] = [
            ("1", ""), ("", "6"), (" ", "6"), ("one", "six"), ("1.0", "6"), ("1", "6.0"),
            ("-1", "-6"), ("+1", "6"), ("1/6", ""), ("1", "6x"), ("١", "٦"),
            ("1", "0"), ("0", "0"),
            ("1", "99999999999999999999"), ("99999999999999999999", "6"),
        ]
        for (top, bottom) in invalid {
            #expect(question.evaluate(numerator: top, denominator: bottom) == .invalidInput, "\(top)/\(bottom)")
        }
        // Both boxes empty is asked for again (Stage 6E), rather than called invalid.
        #expect(question.evaluate(numerator: "", denominator: "") == .unanswered)
        #expect(question.evaluate(numerator: " ", denominator: "\n") == .unanswered)
        #expect(question.evaluate(numerator: "0", denominator: "6") == .incorrect)
        #expect(question.evaluate(numerator: " 1 ", denominator: " 6 ") == .correct)
        #expect(question.evaluate(numerator: "01", denominator: "06") == .correct)
    }

    @Test func hugeFractionsDoNotOverflow() {
        let question = Question.die(faces: 6, target: 1)
        let big = Int.max / 6
        #expect(question.evaluate(numerator: "\(big)", denominator: "\(big * 6)") == .correct)
        #expect(question.evaluate(numerator: "\(Int.max)", denominator: "\(Int.max)") == .incorrect)
        #expect(question.evaluate(numerator: "\(Int.max - 1)", denominator: "\(Int.max)") == .incorrect)
        #expect(question.evaluate(numerator: "1", denominator: "\(Int.max)") == .incorrect)
    }

    @Test func generatedQuestionsAreValidProbabilities() {
        var generator = SeededGenerator(seed: 0x3B_0010)
        var kinds = Set<String>()
        var mistakes = [String]()

        for _ in 0..<10_000 {
            let question = Question.random(using: &generator)
            let probability = question.probability
            let shown = wholeNumbers(in: question.text)

            // What's on screen leads to the answer that's marked.
            let matchesText: Bool
            switch question {
            case let .die(faces, target):
                kinds.insert("die")
                matchesText = (4...10).contains(faces) && (1...faces).contains(target)
                    && shown == [faces, 1, faces, target] && probability == (1, faces)
            case let .spinner(sections, blue):
                kinds.insert("spinner")
                matchesText = (5...20).contains(sections) && (1..<sections).contains(blue)
                    && shown == [sections, blue] && probability == (blue, sections)
            case let .coin(flips):
                kinds.insert("coin")
                // One and two flips are written "once" and "twice".
                matchesText = (1...3).contains(flips) && shown == (flips >= 3 ? [flips] : []) && probability == (1, 1 << flips)
            case let .marbles(total, red):
                kinds.insert("marbles")
                matchesText = (5...20).contains(total) && (1..<total).contains(red)
                    && shown == [total, red] && probability == (red, total)
            case let .cards(total, aces):
                kinds.insert("cards")
                matchesText = (5...20).contains(total) && (1..<total).contains(aces)
                    && shown == [total, aces] && probability == (aces, total)
            }

            let divisor = TypedAnswer.greatestCommonDivisor(probability.numerator, probability.denominator)
            let ok = matchesText
                && probability.numerator > 0 && probability.numerator < probability.denominator
                && question.evaluate(numerator: "\(probability.numerator)", denominator: "\(probability.denominator)") == .correct
                && question.evaluate(numerator: "\(probability.numerator / divisor)", denominator: "\(probability.denominator / divisor)") == .correct
                && question.evaluate(numerator: "\(probability.numerator * 3)", denominator: "\(probability.denominator * 3)") == .correct
                && question.evaluate(numerator: "\(probability.numerator + 1)", denominator: "\(probability.denominator)") == .incorrect
            if !ok {
                mistakes.append(question.text)
            }
        }

        #expect(mistakes.isEmpty, "\(mistakes.prefix(10))")
        #expect(kinds == ["die", "spinner", "coin", "marbles", "cards"])
    }
}

// MARK: - Year 6 Ratios (MQ-11)

struct Year6RatioQuestionTests {
    typealias Question = Year6RatioQuestion

    private func ratio(_ question: Question, _ first: String, _ second: String) -> Question.Outcome {
        question.evaluate(first: first, second: second, missing: "")
    }

    private func missing(_ question: Question, _ value: String) -> Question.Outcome {
        question.evaluate(first: "", second: "", missing: value)
    }

    /// MQ-11: 6:12 made by scaling up 2:4 expected the answer 2:4, which isn't in its simplest form.
    @Test func simplifyingExpectsLowestTerms() {
        let question = Question(kind: .simplify, first: 2, second: 4, multiplier: 3)
        #expect(question.text == "Simplify the ratio 6 : 12")
        #expect(question.asksForRatio)
        #expect(ratio(question, "1", "2") == .correct)
        #expect(ratio(question, " 1 ", "2\n") == .correct)
        for (first, second) in [("2", "4"), ("3", "6"), ("6", "12"), ("2", "1"), ("1", "3"), ("0", "0"),
                                ("0.5", "1"), ("1", "2.0")] {
            #expect(ratio(question, first, second) == .incorrect, "\(first):\(second)")
        }
    }

    /// MQ-11: either order was accepted, so 12:6 was marked correct for 6:12.
    @Test func ratioPartsMustBeInTheOrderAsked() {
        let share = Question(kind: .share, first: 1, second: 2, multiplier: 6)
        #expect(share.text == "Divide 18 in the ratio 1 : 2")
        #expect(ratio(share, "6", "12") == .correct)
        #expect(ratio(share, "12", "6") == .incorrect)

        let simplify = Question(kind: .simplify, first: 3, second: 2, multiplier: 4)
        #expect(simplify.text == "Simplify the ratio 12 : 8")
        #expect(ratio(simplify, "3", "2") == .correct)
        #expect(ratio(simplify, "2", "3") == .incorrect)

        let equalParts = Question(kind: .share, first: 2, second: 2, multiplier: 3)
        #expect(ratio(equalParts, "6", "6") == .correct)
    }

    @Test func missingValues() {
        let first = Question(kind: .missingFirst, first: 2, second: 3, multiplier: 4)
        #expect(first.text == "Find the missing number.\n___ : 12 = 2 : 3")
        #expect(!first.asksForRatio)
        #expect(missing(first, "8") == .correct)
        #expect(missing(first, " 8 ") == .correct)
        for value in ["12", "2", "3", "7", "9", "8.0", "-8", "eight", "8:12"] {
            #expect(missing(first, value) == .incorrect, "\(value)")
        }

        let second = Question(kind: .missingSecond, first: 2, second: 3, multiplier: 4)
        #expect(second.text == "Find the missing number.\n8 : ___ = 2 : 3")
        #expect(missing(second, "12") == .correct)
        #expect(missing(second, "8") == .incorrect)
    }

    @Test func blankAnswersAreUnansweredRatherThanWrong() {
        let simplify = Question(kind: .simplify, first: 1, second: 2, multiplier: 2)
        #expect(ratio(simplify, "", "") == .unanswered)
        #expect(ratio(simplify, "  ", "\n") == .unanswered)
        #expect(ratio(simplify, "1", "") == .incorrect)
        #expect(ratio(simplify, "", "2") == .incorrect)

        let gap = Question(kind: .missingFirst, first: 1, second: 2, multiplier: 2)
        #expect(missing(gap, "") == .unanswered)
        #expect(missing(gap, " ") == .unanswered)
    }

    /// Only the boxes the question shows are marked, so nothing typed for another kind of question
    /// can count.
    @Test func onlyTheBoxesShownAreMarked() {
        let gap = Question(kind: .missingFirst, first: 2, second: 3, multiplier: 4)
        #expect(gap.correctRatio?.first == nil)
        #expect(gap.evaluate(first: "8", second: "12", missing: "") == .unanswered)
        #expect(gap.evaluate(first: "8", second: "12", missing: "7") == .incorrect)

        let simplify = Question(kind: .simplify, first: 2, second: 3, multiplier: 4)
        #expect(simplify.correctMissingValue == nil)
        #expect(simplify.evaluate(first: "", second: "", missing: "2") == .unanswered)
        #expect(simplify.evaluate(first: "2", second: "3", missing: "99") == .correct)
    }

    @Test func invalidTextIsNeverCorrect() {
        let share = Question(kind: .share, first: 1, second: 2, multiplier: 2)
        #expect(ratio(share, "2", "4") == .correct)
        let rejected: [(String, String)] = [("2.0", "4"), ("2", "4.0"), ("+2", "4"), ("2", "-4"),
                                            ("two", "four"), ("2:4", ""), ("2", "4x"), ("٢", "٤"),
                                            ("99999999999999999999", "4")]
        for (first, second) in rejected {
            #expect(ratio(share, first, second) == .incorrect, "\(first):\(second)")
        }
    }

    @Test func everyQuestionHasExactlyOneAnswer() {
        var mistakes = [String]()
        let kinds: [Question.Kind] = [.simplify, .share, .missingFirst, .missingSecond]

        for kind in kinds {
            for first in Question.ratioTerms {
                for second in Question.ratioTerms {
                    for multiplier in Question.multipliers {
                        let question = Question(kind: kind, first: first, second: second, multiplier: multiplier)
                        let total = (first + second) * multiplier

                        func check(_ marked: Question.Outcome, _ correct: Bool, _ answer: String) {
                            if marked != (correct ? .correct : .incorrect) {
                                mistakes.append("\(question.text) → \(answer)")
                            }
                        }

                        switch kind {
                        case .simplify:
                            // The same ratio with no common factor.
                            for a in 0...20 {
                                for b in 0...20 {
                                    let correct = a * second == b * first && TypedAnswer.greatestCommonDivisor(a, b) == 1
                                    check(ratio(question, "\(a)", "\(b)"), correct, "\(a):\(b)")
                                }
                            }
                        case .share:
                            // The two parts add up to the total and are in the ratio, in order.
                            let grid = multiplier == 2 ? 0...total : 0...0
                            for a in 0...total {
                                check(ratio(question, "\(a)", "\(total - a)"), a * second == (total - a) * first, "\(a):\(total - a)")
                                for b in grid {
                                    check(ratio(question, "\(a)", "\(b)"), a + b == total && a * second == b * first, "\(a):\(b)")
                                }
                            }
                        case .missingFirst:
                            for value in 0...60 {
                                check(missing(question, "\(value)"), value * second == second * multiplier * first, "\(value)")
                            }
                        case .missingSecond:
                            for value in 0...60 {
                                check(missing(question, "\(value)"), first * multiplier * second == value * first, "\(value)")
                            }
                        }
                    }
                }
            }
        }
        #expect(mistakes.isEmpty, "\(mistakes.prefix(10))")
    }

    @Test func generatedQuestionsAlwaysHaveAValidAnswer() throws {
        var generator = SeededGenerator(seed: 0x3B_0011)
        var kinds = [Question.Kind: Int]()

        for _ in 0..<10_000 {
            let question = Question.random(using: &generator)
            kinds[question.kind, default: 0] += 1
            #expect(Question.ratioTerms.contains(question.first))
            #expect(Question.ratioTerms.contains(question.second))
            #expect(Question.multipliers.contains(question.multiplier))

            // Check the answer against the numbers on screen rather than the stored ratio.
            let shown = wholeNumbers(in: question.text)
            switch question.kind {
            case .simplify:
                let answer = try #require(question.correctRatio)
                try #require(shown.count == 2)
                #expect(question.correctMissingValue == nil)
                // The ratio shown always needs simplifying, and the answer is the same ratio in lowest terms.
                #expect(TypedAnswer.greatestCommonDivisor(shown[0], shown[1]) >= 2)
                #expect(TypedAnswer.greatestCommonDivisor(answer.first, answer.second) == 1)
                #expect(shown[0] * answer.second == shown[1] * answer.first)
                #expect(ratio(question, "\(answer.first)", "\(answer.second)") == .correct)
                #expect(ratio(question, "\(shown[0])", "\(shown[1])") == .incorrect)
                if answer.first != answer.second {
                    #expect(ratio(question, "\(answer.second)", "\(answer.first)") == .incorrect)
                }

            case .share:
                let answer = try #require(question.correctRatio)
                try #require(shown.count == 3)
                #expect(question.correctMissingValue == nil)
                #expect(answer.first + answer.second == shown[0])
                #expect(answer.first * shown[2] == answer.second * shown[1])
                #expect(ratio(question, "\(answer.first)", "\(answer.second)") == .correct)
                if answer.first != answer.second {
                    #expect(ratio(question, "\(answer.second)", "\(answer.first)") == .incorrect)
                }

            case .missingFirst:
                let value = try #require(question.correctMissingValue)
                try #require(shown.count == 3)
                #expect(question.correctRatio?.first == nil)
                #expect(value * shown[2] == shown[0] * shown[1])
                #expect(missing(question, "\(value)") == .correct)
                #expect(missing(question, "\(value + 1)") == .incorrect)

            case .missingSecond:
                let value = try #require(question.correctMissingValue)
                try #require(shown.count == 3)
                #expect(question.correctRatio?.first == nil)
                #expect(shown[0] * shown[2] == value * shown[1])
                #expect(missing(question, "\(value)") == .correct)
                #expect(missing(question, "\(value + 1)") == .incorrect)
            }
        }

        // All four kinds still turn up about as often as before: a third each for simplifying and
        // sharing, and a sixth each for the two missing values.
        #expect(kinds[.simplify, default: 0] > 2_500)
        #expect(kinds[.share, default: 0] > 2_500)
        #expect(kinds[.missingFirst, default: 0] > 1_200)
        #expect(kinds[.missingSecond, default: 0] > 1_200)
    }
}

// MARK: - Probability and Ratios progression (MQ-30)

struct QuestionProgressTests {
    @Test func skipAppearsAfterTwoWrongAttempts() {
        var progress = QuestionProgress()
        #expect(!progress.showSkipButton)
        progress.recordWrongAttempt()
        #expect(!progress.showSkipButton)
        progress.recordWrongAttempt()
        #expect(progress.showSkipButton)
        progress.recordWrongAttempt()
        #expect(progress.showSkipButton)
        #expect(progress.wrongAttempts == 3)
    }

    /// MQ-30: resetQuestion didn't clear wrongAttempts or showSkipButton, so Skip was already showing
    /// on the next question.
    @Test func eachQuestionStartsAfresh() {
        var skipped = QuestionProgress()
        skipped.recordWrongAttempt()
        skipped.recordWrongAttempt()
        let didSkip = skipped.recordSkip()
        #expect(didSkip)
        skipped.reset()
        #expect(skipped == QuestionProgress())
        #expect(!skipped.showSkipButton)
        #expect(skipped.wrongAttempts == 0)
        #expect(!skipped.isAdvancing)
        skipped.recordWrongAttempt()
        #expect(!skipped.showSkipButton)

        var answered = QuestionProgress()
        answered.recordWrongAttempt()
        answered.recordWrongAttempt()
        let didScore = answered.recordCorrectAnswer()
        #expect(didScore)
        answered.reset()
        #expect(answered == QuestionProgress())
    }

    @Test func skipNeedsTwoWrongAttempts() {
        var progress = QuestionProgress()
        let skipWithNoWrongAttempts = progress.recordSkip()
        progress.recordWrongAttempt()
        let skipWithOneWrongAttempt = progress.recordSkip()
        #expect(!skipWithNoWrongAttempts)
        #expect(!skipWithOneWrongAttempt)
        #expect(!progress.isAdvancing)
    }

    /// A rewarded Skip moves on exactly one question, and a skipped question can't then be scored.
    @Test func skipWorksOnce() {
        var progress = QuestionProgress()
        progress.recordWrongAttempt()
        progress.recordWrongAttempt()
        let skips = [progress.recordSkip(), progress.recordSkip()]
        #expect(skips == [true, false])
        #expect(progress.isAdvancing)
        #expect(!progress.showSkipButton)
        let scoredAfterSkip = progress.recordCorrectAnswer()
        #expect(!scoredAfterSkip)
    }

    /// MQ-30: pressing Return again in the second before the next question appeared scored again.
    @Test func correctAnswerScoresOnce() {
        var progress = QuestionProgress()
        let scores = [progress.recordCorrectAnswer(), progress.recordCorrectAnswer()]
        #expect(scores == [true, false])
        let skippedAfterScoring = progress.recordSkip()
        #expect(!skippedAfterScoring)
        progress.recordWrongAttempt()
        #expect(progress.wrongAttempts == 0)
        #expect(!progress.showSkipButton)
    }

    @Test func skipDisappearsOnceAnswered() {
        var progress = QuestionProgress()
        progress.recordWrongAttempt()
        progress.recordWrongAttempt()
        #expect(progress.showSkipButton)
        let didScore = progress.recordCorrectAnswer()
        #expect(didScore)
        #expect(!progress.showSkipButton)
        let skippedAfterScoring = progress.recordSkip()
        #expect(!skippedAfterScoring)
    }

    /// Long random sequences of wrong answers, repeated correct answers, rewarded skips and new
    /// questions, as the Probability and Ratios views drive them. Each question is scored or skipped
    /// at most once, and Skip only works after two wrong attempts.
    @Test func randomSessionsNeverScoreOrSkipTwice() {
        var generator = SeededGenerator(seed: 0x3B_0030)
        var progress = QuestionProgress()
        var wrong = 0, scored = 0, skipped = 0, questions = 0, points = 0
        var mistakes = [String]()

        for step in 0..<50_000 {
            switch Int.random(in: 0..<5, using: &generator) {
            case 0, 1:
                if !progress.isAdvancing {
                    wrong += 1
                }
                progress.recordWrongAttempt()
            case 2:
                if progress.recordCorrectAnswer() {
                    scored += 1
                    points += 1
                }
            case 3:
                if progress.recordSkip() {
                    skipped += 1
                    if wrong < 2 {
                        mistakes.append("step \(step): skipped after \(wrong) wrong")
                    }
                }
            default:
                // The next question appears once one has been answered or skipped.
                if progress.isAdvancing {
                    progress.reset()
                    questions += 1
                    wrong = 0
                    scored = 0
                    skipped = 0
                }
            }

            if scored + skipped > 1 || progress.wrongAttempts != wrong
                || progress.showSkipButton != (!progress.isAdvancing && wrong >= 2) {
                mistakes.append("step \(step)")
            }
        }

        #expect(mistakes.isEmpty, "\(mistakes.prefix(10))")
        #expect(questions > 1_000)
        #expect(points <= questions + 1)
    }
}

// MARK: - Year 5 Volume and Statistics progression

/// One Year 5 question as the progression tests see it: how it is marked, plus an answer the
/// marking accepts and one it rejects.
private struct Year5Item {
    let isCorrect: (String) -> Bool
    let rightAnswer: String
    let wrongAnswer: String
}

private extension Year5VolumeQuestion {
    var item: Year5Item {
        let right = kind == .comparison ? (glassWithMore ?? "") : String(volume)
        let wrong = kind == .comparison ? (right == "A" ? "B" : "A") : String(volume + 1)
        return Year5Item(isCorrect: { isCorrect(answer: $0) }, rightAnswer: right, wrongAnswer: wrong)
    }
}

private extension Year5StatisticsQuestion {
    var item: Year5Item {
        let right: String
        let wrong: String
        switch kind {
        case .mean:
            // Ten numbers, so the mean is always a whole number of tenths.
            let tenths = (mean?.numerator ?? 0) * 10 / (mean?.denominator ?? 1)
            right = "\(tenths / 10).\(tenths % 10)"
            wrong = "\(tenths / 10 + 1).\(tenths % 10)"
        case .mode:
            right = mode.map { String($0) } ?? ""
            wrong = mode.map { String($0 + 1) } ?? ""
        case .highestBar:
            right = highestCategory ?? ""
            wrong = Self.categories.first { $0 != right } ?? ""
        }
        return Year5Item(isCorrect: { isCorrect(answer: $0) }, rightAnswer: right, wrongAnswer: wrong)
    }
}

enum Year5Activity: CaseIterable {
    case volume, statistics

    /// Real questions from the activity's own generator.
    fileprivate func questions(count: Int, seed: UInt64) -> [Year5Item] {
        var generator = SeededGenerator(seed: seed)
        return (0..<count).map { _ in
            switch self {
            case .volume: return Year5VolumeQuestion.random(using: &generator).item
            case .statistics: return Year5StatisticsQuestion.random(using: &generator).item
            }
        }
    }
}

/// Drives QuestionProgress as Year5VolumeView and Year5StatisticsView do. On-screen Enter and
/// keyboard Return both call checkAnswer(), a rewarded Skip calls gameData.skipQuestion, and a
/// correct answer or a skip schedules resetQuestion() a second later. Those resets wait until the
/// test lets the second pass, so every press in between lands in the transition period. Enter is
/// modelled without its .disabled(showMessage): Return is never disabled, and an earlier wrong
/// answer's feedback timer can re-enable Enter before the next question appears.
private struct Year5Session {
    private var upcoming: [Year5Item]
    private(set) var question: Year5Item
    private(set) var progress = QuestionProgress()
    var answer = ""
    private(set) var message = ""
    private(set) var points = 0
    private(set) var totalQuestionsAnswered = 0
    /// resetQuestion() calls waiting for the second to pass.
    private(set) var pendingResets = 0
    private(set) var questionNumber = 1

    init(_ questions: [Year5Item]) {
        question = questions[0]
        upcoming = Array(questions.dropFirst())
    }

    mutating func pressEnter() { checkAnswer() }
    mutating func pressReturn() { checkAnswer() }

    private mutating func checkAnswer() {
        switch progress.recordSubmission(isCorrect: question.isCorrect(answer)) {
        case .ignored:
            return
        case .correct:
            message = "Correct!"
            points += 1
            totalQuestionsAnswered += 1
            pendingResets += 1
        case .incorrect:
            message = "Incorrect. Try Again!"
        }
    }

    /// Skip is tapped and the reward is earned. Purchased users earn it straight away, so another tap
    /// can arrive before the button disappears; only the guard in the reward closure stops it.
    mutating func tapSkipAndEarnReward() {
        guard progress.recordSkip() else { return }
        pendingResets += 1
    }

    /// The second passes and every scheduled resetQuestion() runs.
    mutating func finishTransition() {
        while pendingResets > 0 {
            pendingResets -= 1
            if !upcoming.isEmpty {
                question = upcoming.removeFirst()
            }
            answer = ""
            message = ""
            progress.reset()
            questionNumber += 1
        }
    }
}

struct Year5ProgressionTests {
    private func makeSession(_ activity: Year5Activity, seed: UInt64 = 0x3B_5005) -> Year5Session {
        Year5Session(activity.questions(count: 20, seed: seed))
    }

    /// The tests below rely on these answers being marked right and wrong.
    @Test(arguments: Year5Activity.allCases)
    func everyQuestionHasARightAndAWrongAnswer(activity: Year5Activity) {
        for item in activity.questions(count: 3_000, seed: 0x3B_5001) {
            #expect(item.isCorrect(item.rightAnswer), "\(item.rightAnswer)")
            #expect(!item.isCorrect(item.wrongAnswer), "\(item.wrongAnswer)")
        }
    }

    @Test func submissionsAfterAnsweringOrSkippingAreIgnored() {
        var answered = QuestionProgress()
        let afterCorrect = [answered.recordSubmission(isCorrect: true),
                            answered.recordSubmission(isCorrect: true),
                            answered.recordSubmission(isCorrect: false)]
        #expect(afterCorrect == [.correct, .ignored, .ignored])
        #expect(answered.wrongAttempts == 0)

        var skipped = QuestionProgress()
        let beforeSkip = [skipped.recordSubmission(isCorrect: false),
                          skipped.recordSubmission(isCorrect: false)]
        #expect(beforeSkip == [.incorrect, .incorrect])
        let didSkip = skipped.recordSkip()
        #expect(didSkip)
        let afterSkip = [skipped.recordSubmission(isCorrect: true),
                         skipped.recordSubmission(isCorrect: false)]
        #expect(afterSkip == [.ignored, .ignored])
        #expect(skipped.wrongAttempts == 2)
    }

    /// Enter pressed again and again before the next question appears.
    @Test(arguments: Year5Activity.allCases)
    func repeatedEnterScoresOnce(activity: Year5Activity) {
        var session = makeSession(activity)
        session.answer = session.question.rightAnswer
        for _ in 0..<5 {
            session.pressEnter()
        }
        #expect(session.points == 1)
        #expect(session.totalQuestionsAnswered == 1)
        #expect(session.pendingResets == 1)
        #expect(session.message == "Correct!")
        session.finishTransition()
        #expect(session.questionNumber == 2)
    }

    /// Return pressed again and again, and Return and Enter mixed, before the next question appears.
    @Test(arguments: Year5Activity.allCases)
    func repeatedReturnScoresOnce(activity: Year5Activity) {
        var session = makeSession(activity)
        session.answer = session.question.rightAnswer
        session.pressReturn()
        session.pressReturn()
        session.pressEnter()
        session.pressReturn()
        session.pressEnter()
        #expect(session.points == 1)
        #expect(session.totalQuestionsAnswered == 1)
        #expect(session.pendingResets == 1)
        session.finishTransition()
        #expect(session.questionNumber == 2)
        #expect(session.points == 1)
    }

    /// The case found in review: a wrong answer, then the right one with Return, then Enter once the
    /// wrong answer's feedback has gone and re-enabled the button, still before the next question.
    @Test(arguments: Year5Activity.allCases)
    func enterAfterAnEarlierWrongAnswerScoresOnce(activity: Year5Activity) {
        var session = makeSession(activity)
        session.answer = session.question.wrongAnswer
        session.pressEnter()
        session.answer = session.question.rightAnswer
        session.pressReturn()
        session.pressEnter()
        session.pressEnter()
        #expect(session.points == 1)
        #expect(session.pendingResets == 1)
        #expect(session.progress.wrongAttempts == 1)
    }

    @Test(arguments: Year5Activity.allCases)
    func wrongAnswersNeverScore(activity: Year5Activity) {
        var session = makeSession(activity)
        session.pressEnter()                        // empty box
        session.answer = session.question.wrongAnswer
        for press in 0..<9 {
            if press.isMultiple(of: 2) {
                session.pressEnter()
            } else {
                session.pressReturn()
            }
        }
        #expect(session.points == 0)
        #expect(session.totalQuestionsAnswered == 0)
        #expect(session.pendingResets == 0)
        #expect(session.progress.wrongAttempts == 10)
        #expect(session.progress.showSkipButton)
        #expect(session.message == "Incorrect. Try Again!")
        session.finishTransition()
        #expect(session.questionNumber == 1)
    }

    /// Changing the answer to a wrong one during "Correct!" doesn't show "Incorrect" or count as a
    /// wrong attempt.
    @Test(arguments: Year5Activity.allCases)
    func editingTheAnswerDuringTheTransitionIsIgnored(activity: Year5Activity) {
        var session = makeSession(activity)
        session.answer = session.question.wrongAnswer
        session.pressEnter()
        session.answer = session.question.rightAnswer
        session.pressEnter()
        session.answer = session.question.wrongAnswer
        session.pressReturn()
        session.pressEnter()
        #expect(session.message == "Correct!")
        #expect(session.progress.wrongAttempts == 1)
        #expect(!session.progress.showSkipButton)
        #expect(session.points == 1)
    }

    /// Skip showing, then the right answer: Skip disappears, and a tap that still gets through doesn't
    /// move on a second question.
    @Test(arguments: Year5Activity.allCases)
    func skipCannotFollowACorrectAnswer(activity: Year5Activity) {
        var session = makeSession(activity)
        session.answer = session.question.wrongAnswer
        session.pressEnter()
        session.pressReturn()
        #expect(session.progress.showSkipButton)
        session.answer = session.question.rightAnswer
        session.pressEnter()
        #expect(!session.progress.showSkipButton)
        session.tapSkipAndEarnReward()
        session.tapSkipAndEarnReward()
        #expect(session.pendingResets == 1)
        #expect(session.points == 1)
        session.finishTransition()
        #expect(session.questionNumber == 2)
        #expect(session.points == 1)
    }

    /// Several Skip taps (a purchased user earns each reward straight away) move on one question, and
    /// the skipped question can't then be scored.
    @Test(arguments: Year5Activity.allCases)
    func repeatedSkipMovesOnOneQuestion(activity: Year5Activity) {
        var session = makeSession(activity)
        session.tapSkipAndEarnReward()
        session.answer = session.question.wrongAnswer
        session.pressEnter()
        session.tapSkipAndEarnReward()
        #expect(session.pendingResets == 0)
        session.pressReturn()
        for _ in 0..<4 {
            session.tapSkipAndEarnReward()
        }
        #expect(session.pendingResets == 1)
        #expect(!session.progress.showSkipButton)
        session.answer = session.question.rightAnswer
        session.pressEnter()
        session.pressReturn()
        #expect(session.points == 0)
        #expect(session.totalQuestionsAnswered == 0)
        #expect(session.pendingResets == 1)
        session.finishTransition()
        #expect(session.questionNumber == 2)
        #expect(session.points == 0)
    }

    /// After a correct answer and after a skip, the next question starts with nothing carried over.
    @Test(arguments: Year5Activity.allCases)
    func nextQuestionStartsClean(activity: Year5Activity) {
        var session = makeSession(activity)
        session.answer = session.question.wrongAnswer
        session.pressEnter()
        session.pressEnter()
        session.answer = session.question.rightAnswer
        session.pressEnter()
        session.finishTransition()
        #expect(session.progress == QuestionProgress())
        #expect(session.answer.isEmpty)
        #expect(session.message.isEmpty)
        #expect(!session.progress.showSkipButton)

        session.answer = session.question.wrongAnswer
        session.pressReturn()
        session.pressReturn()
        session.tapSkipAndEarnReward()
        session.finishTransition()
        #expect(session.questionNumber == 3)
        #expect(session.progress == QuestionProgress())
        #expect(session.answer.isEmpty)
        #expect(session.message.isEmpty)

        // One wrong attempt isn't enough for Skip, and the new question can still be scored.
        session.answer = session.question.wrongAnswer
        session.pressEnter()
        #expect(session.progress.wrongAttempts == 1)
        #expect(!session.progress.showSkipButton)
        session.answer = session.question.rightAnswer
        session.pressReturn()
        session.pressReturn()
        #expect(session.points == 2)
        session.finishTransition()
        #expect(session.questionNumber == 4)
    }

    /// Long random sequences of Enter, Return, edits and Skip taps, with the second sometimes passing
    /// in between, on real questions. Each question scores or is skipped at most once, only a right
    /// answer scores, Skip needs two wrong attempts, and every new question starts clean.
    @Test(arguments: Year5Activity.allCases)
    func randomSessionsScoreOrSkipEachQuestionAtMostOnce(activity: Year5Activity) {
        var generator = SeededGenerator(seed: 0x3B_5030)
        var session = Year5Session(activity.questions(count: 8_000, seed: 0x3B_5031))
        var advances = 0
        var mistakes = [String]()

        for step in 0..<40_000 {
            let points = session.points
            let pending = session.pendingResets
            let wrong = session.progress.wrongAttempts
            let message = session.message
            let wasAdvancing = session.progress.isAdvancing
            let question = session.questionNumber

            switch Int.random(in: 0..<8, using: &generator) {
            case 0:
                session.answer = session.question.rightAnswer
                session.pressEnter()
            case 1:
                session.answer = session.question.rightAnswer
                session.pressReturn()
            case 2:
                session.answer = session.question.wrongAnswer
                session.pressEnter()
            case 3:
                session.answer = session.question.wrongAnswer
                session.pressReturn()
            case 4:
                session.pressEnter()                // whatever is already in the box
            case 5, 6:
                session.tapSkipAndEarnReward()
            default:
                session.finishTransition()
                if pending > 0 {
                    advances += 1
                    if session.progress != QuestionProgress() || !session.answer.isEmpty
                        || !session.message.isEmpty {
                        mistakes.append("step \(step): question \(session.questionNumber) didn't start clean")
                    }
                }
            }

            let scored = session.points - points
            let skipped = session.pendingResets > pending && scored == 0
            if session.pendingResets > 1 || scored > 1 || session.questionNumber > question + 1 {
                mistakes.append("step \(step): moved on more than one question")
            }
            if scored == 1 && (wasAdvancing || !session.question.isCorrect(session.answer)) {
                mistakes.append("step \(step): scored without a first right answer")
            }
            if skipped && (wasAdvancing || wrong < QuestionProgress.wrongAttemptsBeforeSkip) {
                mistakes.append("step \(step): skipped after \(wrong) wrong")
            }
            if wasAdvancing && session.questionNumber == question
                && (session.progress.wrongAttempts != wrong || session.message != message) {
                mistakes.append("step \(step): answer marked during the transition")
            }
            if session.questionNumber != 1 + advances {
                mistakes.append("step \(step): question \(session.questionNumber) after \(advances) advances")
            }
        }

        #expect(mistakes.isEmpty, "\(mistakes.prefix(10))")
        #expect(advances > 2_000)
        #expect(session.points > 1_000)
        #expect(session.points <= advances + 1)
    }
}
