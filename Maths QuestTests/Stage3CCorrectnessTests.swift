//
//  Stage3CCorrectnessTests.swift
//  Maths QuestTests
//
//  Regression tests for Year 1 Counting, Year 2 Multiplication, Division and Shapes, Year 3
//  Measurement and its ruler, Year 4 Decimals and Money, and Year 6 Algebra. Each MQ-xx comment
//  names the old defect, and where the old marking was a formula the test runs that formula to show
//  what it got wrong. Everything here is pure maths and state, so it runs without the simulator UI,
//  StoreKit or Firebase.
//

import Foundation
import SwiftUI
import Testing
@testable import Maths_Quest

/// The whole numbers in a question's text, in order.
private func numbersShown(in text: String) -> [Int] {
    text.split(whereSeparator: { !($0.isASCII && $0.isNumber) }).compactMap { Int($0) }
}

/// The numbers in a question's text as typed, such as ["2.5", "3"] in "What is 2.5 × 3?".
private func decimalsShown(in text: String) -> [String] {
    text.split(whereSeparator: { $0 == " " || $0 == "?" })
        .map { $0.hasPrefix("£") ? String($0.dropFirst()) : String($0) }
        .filter { $0.first?.isNumber == true }
}

// MARK: - Typed decimals

struct DecimalEntryTests {
    private func number(_ numerator: Int, _ denominator: Int, places: Int) -> TypedAnswer.DecimalEntry {
        .number(numerator: numerator, denominator: denominator, decimalPlaces: places)
    }

    @Test func blankText() {
        for text in ["", " ", "\n", " \t "] {
            #expect(TypedAnswer.decimalEntry(text) == .blank, "\(text)")
            #expect(TypedAnswer.isBlank(text), "\(text)")
        }
        #expect(!TypedAnswer.isBlank("0"))
        #expect(!TypedAnswer.isBlank(" x "))
    }

    /// The exact value, and the decimal places as typed so "2.5" and "2.50" can be told apart.
    @Test func numbersKeepTheirDecimalPlaces() {
        let cases: [(String, TypedAnswer.DecimalEntry)] = [
            ("2", number(2, 1, places: 0)),
            ("2.5", number(5, 2, places: 1)),
            ("2.50", number(5, 2, places: 2)),
            ("2.500", number(5, 2, places: 3)),
            ("2,5", number(5, 2, places: 1)),
            ("2,50", number(5, 2, places: 2)),
            (" 2.50 ", number(5, 2, places: 2)),
            ("02.50", number(5, 2, places: 2)),
            (".5", number(1, 2, places: 1)),
            ("5.", number(5, 1, places: 0)),
            ("0", number(0, 1, places: 0)),
            ("0.00", number(0, 1, places: 2)),
            ("1000", number(1000, 1, places: 0)),
            // These can only be decimal commas: a thousands group has exactly three digits after
            // the comma and doesn't start with 0.
            ("1,5000", number(3, 2, places: 4)),
            ("0,500", number(1, 2, places: 3)),
            ("1234,500", number(2469, 2, places: 3)),
        ]
        for (text, entry) in cases {
            #expect(TypedAnswer.decimalEntry(text) == entry, "\(text)")
        }
    }

    /// "1,500" is 1500 with a thousands separator and 1.5 with a decimal comma.
    @Test func ambiguousCommas() {
        for text in ["1,500", "12,500", "999,999", "1,000", " 2,500 "] {
            #expect(TypedAnswer.decimalEntry(text) == .ambiguousComma, "\(text)")
        }
    }

    @Test func textThatIsNotANumber() {
        let rejected = ["abc", ".", ",", "-2.5", "+2.5", "2.5.0", "1e3", "£2.50", "2 .5", "½", "2.5x",
                        "1,500,000", "1,500.5", "99999999999999999999", "0.0000000000000000001"]
        for text in rejected {
            #expect(TypedAnswer.decimalEntry(text) == .notANumber, "\(text)")
        }
    }
}

// MARK: - Year 1 Counting (MQ-22)

struct Year1CountingQuestionTests {
    /// MQ-22: every question counted from 1 to 10, but Year 1 pupils "count to and across 100,
    /// forwards and backwards, beginning with 0 or 1, or from any given number". Questions now run
    /// ten numbers in a row from anywhere between 0 and 100.
    @Test func questionsCoverZeroToOneHundred() {
        var generator = SeededGenerator(seed: 0x3C_0101)
        var shown = Set<Int>()
        var missing = Set<Int>()
        for _ in 0..<20_000 {
            let question = Year1CountingQuestion.random(using: &generator)
            let numbers = question.numbers
            #expect(numbers.count == 10)
            #expect(numbers == Array(numbers[0]...numbers[0] + 9))
            #expect(numbers.allSatisfy { (0...100).contains($0) })
            #expect(numbers[question.missingIndex] == question.missingNumber)
            #expect(question.evaluate(String(question.missingNumber)) == .correct)
            shown.formUnion(numbers)
            missing.insert(question.missingNumber)
        }
        #expect(shown == Set(0...100))
        #expect(missing == Set(0...100))
    }

    @Test func marking() {
        let question = Year1CountingQuestion(start: 37, missingIndex: 4)
        #expect(question.numbers == Array(37...46))
        #expect(question.missingNumber == 41)
        for answer in ["41", " 41 ", "041"] {
            #expect(question.evaluate(answer) == .correct, "\(answer)")
        }
        for answer in ["40", "42", "14", "4", "4 1", "41.5", "-41", "forty-one", "4l", "99999999999999999999"] {
            #expect(question.evaluate(answer) == .incorrect, "\(answer)")
        }
        for answer in ["", " ", "\n"] {
            #expect(question.evaluate(answer) == .unanswered, "\(answer)")
        }

        #expect(Year1CountingQuestion(start: 0, missingIndex: 0).evaluate("0") == .correct)
        #expect(Year1CountingQuestion(start: 91, missingIndex: 9).evaluate("100") == .correct)
        #expect(Year1CountingQuestion(start: 91, missingIndex: 9).evaluate("10") == .incorrect)
    }
}

// MARK: - Year 2 Multiplication (MQ-22)

struct Year2MultiplicationQuestionTests {
    /// MQ-22: both numbers came from 0..<10, so ×10 never appeared while ×0, ×3, ×4, ×6, ×7, ×8 and
    /// ×9 did. Year 2 pupils "recall and use multiplication and division facts for the 2, 5 and 10
    /// multiplication tables", so every fact from 2, 5 and 10 times 1 to 10 now appears, either way round.
    @Test func everyTwoFiveAndTenTimesTableFact() {
        var generator = SeededGenerator(seed: 0x3C_0201)
        var facts = Set<[Int]>()
        for _ in 0..<20_000 {
            let question = Year2MultiplicationQuestion.random(using: &generator)
            let tables = Year2MultiplicationQuestion.tables
            let firstIsTable = tables.contains(question.first) && (1...10).contains(question.second)
            let secondIsTable = tables.contains(question.second) && (1...10).contains(question.first)
            #expect(firstIsTable || secondIsTable, "\(question.text)")
            #expect(question.product == question.first * question.second)
            #expect(numbersShown(in: question.text) == [question.first, question.second])
            #expect(question.evaluate(String(question.product)) == .correct)
            facts.insert([question.first, question.second])
        }

        var expected = Set<[Int]>()
        for table in [2, 5, 10] {
            for number in 1...10 {
                expected.insert([table, number])
                expected.insert([number, table])
            }
        }
        #expect(facts == expected)
        #expect(facts.contains([10, 10]))
        #expect(!facts.contains { $0.contains(0) })
    }

    @Test func marking() {
        let question = Year2MultiplicationQuestion(first: 7, second: 5)
        #expect(question.text == "7 × 5")
        for answer in ["35", " 35 ", "035"] {
            #expect(question.evaluate(answer) == .correct, "\(answer)")
        }
        for answer in ["36", "12", "75", "7x5", "35.5", "-35", "thirty-five", "99999999999999999999"] {
            #expect(question.evaluate(answer) == .incorrect, "\(answer)")
        }
        #expect(question.evaluate("") == .unanswered)
        #expect(question.evaluate("  ") == .unanswered)
    }
}

// MARK: - Year 2 Division (MQ-27)

struct Year2DivisionQuestionTests {
    private func checkInvariants(_ question: Year2DivisionQuestion) {
        #expect(question.divisor != 0)
        #expect(Year2DivisionQuestion.divisors.contains(question.divisor))
        #expect((1...10).contains(question.quotient))
        #expect(question.dividend == question.divisor * question.quotient)
        #expect(question.dividend % question.divisor == 0)
        #expect(question.dividend / question.divisor == question.quotient)
        #expect(numbersShown(in: question.text) == [question.dividend, question.divisor])
        #expect(question.evaluate(String(question.quotient)) == .correct)
    }

    /// MQ-27: the first question came from 2..<10 and later ones from 1..<10, and the number being
    /// divided was only worked out in onAppear and resetQuestion, starting as 0. Every question is
    /// now one of the 30 facts in the 2, 5 and 10 tables, made the same way each time, so it always
    /// has a whole-number answer and never divides by 0.
    @Test func everyQuestionIsATimesTableFact() {
        var generator = SeededGenerator(seed: 0x3C_0202)
        var facts = Set<[Int]>()
        for _ in 0..<10_000 {
            let question = Year2DivisionQuestion.random(using: &generator)
            checkInvariants(question)
            facts.insert([question.dividend, question.divisor])
        }
        #expect(facts.count == 30)
    }

    /// The view's first question and every later one both come from random().
    @Test func unseededQuestionsFollowTheSameRules() {
        for _ in 0..<2_000 {
            checkInvariants(Year2DivisionQuestion.random())
        }
    }

    @Test func marking() {
        let question = Year2DivisionQuestion(divisor: 5, quotient: 7)
        #expect(question.text == "35 ÷ 5")
        for answer in ["7", " 7 ", "07"] {
            #expect(question.evaluate(answer) == .correct, "\(answer)")
        }
        for answer in ["35", "5", "0", "8", "175", "7.5", "-7", "seven", "99999999999999999999"] {
            #expect(question.evaluate(answer) == .incorrect, "\(answer)")
        }
        #expect(question.evaluate("") == .unanswered)
    }
}

// MARK: - Year 2 Shapes (MQ-26)

struct Year2ShapeQuestionTests {
    /// MQ-26: a circle was marked as having 1 side. Year 2 pupils describe "the number of sides" of
    /// 2-D shapes, where a side is a straight edge, so the question now asks for straight sides and a
    /// circle has 0 of them and 0 corners.
    @Test func aCircleHasNoStraightSidesOrCorners() throws {
        let circle = try #require(Year2ShapeQuestion.figures.firstIndex { $0.name == "circle" })

        let sides = Year2ShapeQuestion(kind: .sides, figureIndex: circle)
        #expect(sides.text == "How many straight sides does this shape have?")
        #expect(sides.evaluate("0") == .correct)
        #expect(sides.evaluate("1") == .incorrect)

        let corners = Year2ShapeQuestion(kind: .corners, figureIndex: circle)
        #expect(corners.text == "How many corners does this shape have?")
        #expect(corners.evaluate("0") == .correct)
        #expect(corners.evaluate("1") == .incorrect)
    }

    /// The polygon drawn has the number of sides and corners the answer expects.
    @Test func polygonsMatchTheirDrawings() {
        for figure in Year2ShapeQuestion.figures where figure.name != "circle" {
            #expect(figure.straightSides >= 3, "\(figure.name)")
            #expect(figure.corners == figure.straightSides, "\(figure.name)")

            var moves = 0
            var lines = 0
            var closes = 0
            ShapeMaker(sides: figure.straightSides).path(in: CGRect(x: 0, y: 0, width: 100, height: 100)).forEach { element in
                switch element {
                case .move: moves += 1
                case .line: lines += 1
                case .closeSubpath: closes += 1
                default: break
                }
            }
            #expect(moves == 1 && lines == figure.straightSides - 1 && closes == 1, "\(figure.name)")
        }
        #expect(Year2ShapeQuestion.figures.map(\.name) == ["circle", "triangle", "square", "pentagon", "hexagon", "octagon"])
    }

    @Test func marking() throws {
        let hexagon = try #require(Year2ShapeQuestion.figures.firstIndex { $0.name == "hexagon" })
        let sides = Year2ShapeQuestion(kind: .sides, figureIndex: hexagon)
        for answer in ["6", " 6 ", "06"] {
            #expect(sides.evaluate(answer) == .correct, "\(answer)")
        }
        for answer in ["5", "8", "six", "6.5", "hexagon", "99999999999999999999"] {
            #expect(sides.evaluate(answer) == .incorrect, "\(answer)")
        }

        let name = Year2ShapeQuestion(kind: .name, figureIndex: hexagon)
        #expect(name.text == "What is this shape called?")
        for answer in ["hexagon", "Hexagon", "HEXAGON", " hexagon ", "hexa gon"] {
            #expect(name.evaluate(answer) == .correct, "\(answer)")
        }
        for answer in ["hexagons", "pentagon", "octagon", "6", "hex"] {
            #expect(name.evaluate(answer) == .incorrect, "\(answer)")
        }
        for question in [sides, name] {
            #expect(question.evaluate("") == .unanswered)
            #expect(question.evaluate(" ") == .unanswered)
        }
    }

    @Test func everyShapeAndQuestionAppears() {
        var generator = SeededGenerator(seed: 0x3C_0203)
        var seen = Set<String>()
        for _ in 0..<5_000 {
            let question = Year2ShapeQuestion.random(using: &generator)
            #expect(Year2ShapeQuestion.figures.indices.contains(question.figureIndex))
            seen.insert("\(question.figure.name) \(question.kind)")
        }
        #expect(seen.count == Year2ShapeQuestion.figures.count * 3)
    }
}

// MARK: - Year 3 Measurement (MQ-22, MQ-33)

struct Year3MeasurementQuestionTests {
    private func measuring(_ length: Int) -> Year3MeasurementQuestion {
        Year3MeasurementQuestion(kind: .measure, group: 0, from: 0, to: 1, amount: 1, objectLength: length)
    }

    /// How many of the second unit make one of the first.
    private let factors: [[String]: Int] = [
        ["m", "cm"]: 100, ["m", "mm"]: 1000, ["cm", "mm"]: 10, ["kg", "g"]: 1000, ["l", "ml"]: 1000,
    ]

    /// MQ-22: the units included km, mg and kl. Year 3 pupils "measure, compare, add and subtract:
    /// lengths (m/cm/mm); mass (kg/g); volume/capacity (l/ml)". Kilometres come in Years 4 and 5,
    /// and milligrams and kilolitres aren't in the primary curriculum.
    @Test func onlyYearThreeUnits() {
        var generator = SeededGenerator(seed: 0x3C_0301)
        var conversions = Set<[String]>()
        var lengths = Set<Int>()
        for _ in 0..<10_000 {
            let question = Year3MeasurementQuestion.random(using: &generator)
            #expect(Set(question.units).isSubset(of: ["m", "cm", "mm", "kg", "g", "l", "ml"]))
            #expect(question.from < question.to)
            #expect((1...10).contains(question.amount))
            #expect(question.text == "Convert \(question.amount) \(question.fromUnit) into \(question.toUnit)")
            let factor = factors[[question.fromUnit, question.toUnit]] ?? 0
            #expect(question.convertedAmount == question.amount * factor)
            conversions.insert([question.fromUnit, question.toUnit])
            lengths.insert(question.objectLength)
        }
        #expect(conversions == Set(factors.keys))
        #expect(lengths == Set(1...10))
    }

    /// MQ-33: the measurement was rounded toward zero, so 4.9 and 4.5 were accepted for a 4 cm bar.
    @Test func measurementsAreExact() {
        let oldAccepts = { (answer: String) -> Bool in
            Double(answer).map { Int(exactly: $0.rounded(.towardZero)) == 4 } ?? false
        }
        #expect(oldAccepts("4.9"))
        #expect(oldAccepts("4.5"))

        let bar = measuring(4)
        for answer in ["4", "4.0", "4.00", "04", "4,0", " 4 "] {
            #expect(bar.evaluate(answer: answer, unit: "") == .correct, "\(answer)")
        }
        for answer in ["4.9", "4.5", "4.1", "3.9", "5", "40", "0.4", "14"] {
            #expect(bar.evaluate(answer: answer, unit: "") == .incorrect, "\(answer)")
        }
        // A measurement is always in centimetres, so the unit picker doesn't matter.
        #expect(bar.evaluate(answer: "4", unit: "m") == .correct)
    }

    @Test func conversionsNeedTheRightNumberAndUnit() {
        let question = Year3MeasurementQuestion(kind: .convert, group: 0, from: 0, to: 2, amount: 3, objectLength: 1)
        #expect(question.text == "Convert 3 m into mm")
        #expect(question.convertedAmount == 3000)
        for answer in ["3000", "3000.0", "03000", " 3000 "] {
            #expect(question.evaluate(answer: answer, unit: "mm") == .correct, "\(answer)")
        }
        #expect(question.evaluate(answer: "3000", unit: "cm") == .incorrect)
        #expect(question.evaluate(answer: "3000", unit: "m") == .incorrect)
        #expect(question.evaluate(answer: "3000", unit: "") == .incorrect)
        for answer in ["300", "3", "30000", "3000.5", "2999"] {
            #expect(question.evaluate(answer: answer, unit: "mm") == .incorrect, "\(answer)")
        }
    }

    /// Blank and malformed answers get a message rather than a wrong attempt, as before.
    @Test func invalidAnswersAreNotMarked() {
        let conversion = Year3MeasurementQuestion(kind: .convert, group: 1, from: 0, to: 1, amount: 3, objectLength: 1)
        #expect(conversion.evaluate(answer: "3,000", unit: "g") == .ambiguousComma)
        for question in [measuring(4), conversion] {
            for answer in ["", " ", "\n"] {
                #expect(question.evaluate(answer: answer, unit: "g") == .unanswered, "\(answer)")
            }
            for answer in ["four", "-4", "4cm", "4 cm", "3000g", "1e3", "4.0.0", "99999999999999999999"] {
                #expect(question.evaluate(answer: answer, unit: "g") == .notANumber, "\(answer)")
            }
        }
    }

    @Test func everyGeneratedQuestionHasOneAnswer() {
        var generator = SeededGenerator(seed: 0x3C_0302)
        for _ in 0..<5_000 {
            let question = Year3MeasurementQuestion.random(using: &generator)
            let expected = question.kind == .convert ? question.convertedAmount : question.objectLength
            let unit = question.kind == .convert ? question.toUnit : ""
            #expect(question.evaluate(answer: String(expected), unit: unit) == .correct)
            #expect(question.evaluate(answer: String(expected + 1), unit: unit) == .incorrect)
            #expect(question.evaluate(answer: String(expected - 1), unit: unit) == .incorrect)
            if question.kind == .convert {
                for other in question.units where other != question.toUnit {
                    #expect(question.evaluate(answer: String(expected), unit: other) == .incorrect)
                }
            }
        }
    }
}

// MARK: - Year 3 ruler (MQ-33)

/// Points per centimetre (the screen width / 20) on an iPhone 17 Pro, an iPhone SE, an 11-inch iPad
/// Pro and a 13-inch iPad Pro, in portrait.
private let rulerScales: [CGFloat] = [402 / 20, 375 / 20, 834 / 20, 1032 / 20]

private func isWhole(_ value: CGFloat) -> Bool {
    abs(value - value.rounded()) < 1e-9
}

private func isClose(_ a: CGFloat, _ b: CGFloat) -> Bool {
    abs(a - b) < 1e-9
}

struct RulerPlacementTests {
    @Test(arguments: rulerScales)
    func everyBarFitsTheRuler(scale: CGFloat) {
        for length in 1...10 {
            let placement = RulerPlacement(objectLength: length, scale: scale)
            #expect(placement.minOffset < placement.maxOffset)
            #expect(isClose(placement.leftEdgeMark(at: placement.minOffset), 0))
            #expect(isClose(placement.leftEdgeMark(at: placement.maxOffset) + CGFloat(length), 15))
            #expect(placement.clamped(-10_000) == placement.minOffset)
            #expect(placement.clamped(10_000) == placement.maxOffset)
        }
    }

    /// Wherever the bar is let go, it settles with both ends on whole centimetres, on the ruler,
    /// at the nearest such place.
    @Test(arguments: rulerScales)
    func snappingPutsBothEndsOnWholeCentimetres(scale: CGFloat) {
        for length in 1...10 {
            let placement = RulerPlacement(objectLength: length, scale: scale)
            for offset in stride(from: placement.minOffset - 3 * scale, through: placement.maxOffset + 3 * scale, by: scale / 7) {
                let snapped = placement.snapped(offset)
                let mark = placement.leftEdgeMark(at: snapped)
                #expect(isWhole(mark))
                #expect(mark >= -1e-9 && mark + CGFloat(length) <= 15 + 1e-9)
                #expect(abs(snapped - placement.clamped(offset)) <= scale / 2 + 1e-9)
            }
        }
    }

    @Test(arguments: rulerScales)
    func eachBarStartsOnWholeCentimetresNearTheMiddle(scale: CGFloat) {
        for length in 1...10 {
            let placement = RulerPlacement(objectLength: length, scale: scale)
            #expect(isWhole(placement.leftEdgeMark(at: placement.startOffset)))
            #expect(abs(placement.startOffset) <= scale / 2 + 1e-9)
            #expect(placement.clamped(placement.startOffset) == placement.startOffset)
        }
    }

    /// The bar moves exactly as far as the finger, and not at all until the finger moves.
    @Test(arguments: rulerScales)
    func theBarFollowsTheFinger(scale: CGFloat) {
        for length in 1...10 {
            let placement = RulerPlacement(objectLength: length, scale: scale)
            let start = placement.startOffset
            #expect(placement.offset(afterDragging: 0, from: start) == start)
            for translation in [-2 * scale, -scale / 2, scale / 3, scale, 2 * scale] {
                let expected = placement.clamped(start + translation)
                #expect(isClose(placement.offset(afterDragging: translation, from: start), expected))
                if (placement.minOffset...placement.maxOffset).contains(start + translation) {
                    #expect(isClose(placement.offset(afterDragging: translation, from: start), start + translation))
                }
            }
            #expect(placement.offset(afterDragging: -10_000, from: start) == placement.minOffset)
            #expect(placement.offset(afterDragging: 10_000, from: start) == placement.maxOffset)
        }
    }

    /// MQ-33: reaching either end locked the bar for good, even into the next question. Now the bar
    /// stops at the end and moves again as soon as the finger comes back, in the same drag or the next.
    @Test(arguments: rulerScales)
    func reachingAnEndDoesNotLockTheBar(scale: CGFloat) {
        for length in 1...10 {
            let placement = RulerPlacement(objectLength: length, scale: scale)

            // One drag past the left end and back to where it began.
            var start = placement.startOffset
            var offset = start
            for translation in stride(from: 0, through: -20 * scale, by: -scale / 3) {
                offset = placement.offset(afterDragging: translation, from: start)
            }
            #expect(offset == placement.minOffset)
            offset = placement.offset(afterDragging: 0, from: start)
            #expect(offset == start)

            // A drag to the left end, then a new drag to the right.
            offset = placement.snapped(placement.offset(afterDragging: -10_000, from: start))
            #expect(isClose(placement.leftEdgeMark(at: offset), 0))
            start = offset
            offset = placement.snapped(placement.offset(afterDragging: 3 * scale, from: start))
            #expect(isClose(placement.leftEdgeMark(at: offset), 3))

            // The same at the right end.
            start = offset
            offset = placement.snapped(placement.offset(afterDragging: 10_000, from: start))
            #expect(isClose(placement.leftEdgeMark(at: offset) + CGFloat(length), 15))
            start = offset
            offset = placement.snapped(placement.offset(afterDragging: -scale, from: start))
            #expect(isClose(placement.leftEdgeMark(at: offset) + CGFloat(length), 14))
        }
    }

    /// Dragged so its left end is near any mark, the bar settles with its ends on that mark and the
    /// mark its length further on, so the ruler always reads the bar's true length.
    @Test(arguments: rulerScales)
    func theRulerReadsTheBarsLength(scale: CGFloat) {
        for length in 1...10 {
            let placement = RulerPlacement(objectLength: length, scale: scale)
            let start = placement.startOffset
            let startMark = placement.leftEdgeMark(at: start)
            for mark in 0...(15 - length) {
                for nudge in [-0.45, -0.2, 0, 0.2, 0.45] as [CGFloat] {
                    let translation = (CGFloat(mark) - startMark + nudge) * scale
                    let dropped = placement.snapped(placement.offset(afterDragging: translation, from: start))
                    let left = placement.leftEdgeMark(at: dropped)
                    #expect(isClose(left, CGFloat(mark)), "\(length) cm to \(mark) by \(nudge)")
                    #expect(isClose(left + CGFloat(length), CGFloat(mark + length)))
                }
            }
        }
    }

    /// MQ-33: the old drag set the offset to the touch's x inside the bar minus half the screen
    /// width. That isn't where the finger is, so the bar jumped left as soon as it was touched, and
    /// any bar of 5 cm or less landed at or past the left end, where it locked.
    @Test(arguments: rulerScales)
    func oldDragJumpedToTheLeftEndAndLocked(scale: CGFloat) {
        let screenWidth = scale * 20
        for length in 1...5 {
            let placement = RulerPlacement(objectLength: length, scale: scale)
            for touchX in stride(from: 0, through: CGFloat(length) * scale, by: scale / 4) {
                let oldOffset = touchX - screenWidth / 2
                #expect(oldOffset <= placement.minOffset + 1e-9)
            }
            #expect(placement.offset(afterDragging: 0, from: placement.startOffset) == placement.startOffset)
        }
    }

    /// MQ-33: the old snapping rounded the bar's centre to a whole centimetre, which leaves both ends
    /// of a 2, 4, 6, 8 or 10 cm bar on half-centimetre marks.
    @Test(arguments: rulerScales)
    func oldSnappingPutEvenBarsOnHalfCentimetres(scale: CGFloat) {
        for length in stride(from: 2, through: 10, by: 2) {
            let placement = RulerPlacement(objectLength: length, scale: scale)
            for centimetres in -2...2 {
                let oldSnapped = (CGFloat(centimetres) * scale / scale).rounded() * scale
                let oldMark = placement.leftEdgeMark(at: oldSnapped)
                #expect(isClose(oldMark - oldMark.rounded(.down), 0.5))
                #expect(isWhole(placement.leftEdgeMark(at: placement.snapped(oldSnapped))))
            }
        }
    }
}

// MARK: - Year 4 Decimals (MQ-28)

struct Year4DecimalsQuestionTests {
    /// MQ-28: answers were rounded to one decimal place before comparing, so 2.54 and 2.45 were
    /// both accepted for 2.5. The question doesn't ask for rounding, so answers are now exact.
    @Test func answersAreExact() {
        let oldAccepts = { (answer: String) -> Bool in
            guard let typed = Double(answer.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
            return (typed * 10).rounded() / 10 == ((1.2 + 1.3) * 10).rounded() / 10
        }
        #expect(oldAccepts("2.54"))
        #expect(oldAccepts("2.45"))
        #expect(!oldAccepts("2,5"))

        let question = Year4DecimalsQuestion(kind: .add, first: 12, second: 13, multiplier: 1)
        #expect(question.text == "What is 1.2 + 1.3?")
        for answer in ["2.5", "2.50", "2.500", "2,5", "2,50", " 2.5 ", "02.5"] {
            #expect(question.evaluate(answer) == .correct, "\(answer)")
        }
        for answer in ["2.54", "2.45", "2.51", "2.49", "2.6", "2.4", "25", "0.25", "2", "3"] {
            #expect(question.evaluate(answer) == .incorrect, "\(answer)")
        }
    }

    @Test func wholeNumberAnswers() {
        let question = Year4DecimalsQuestion(kind: .multiply, first: 25, second: 0, multiplier: 4)
        #expect(question.text == "What is 2.5 × 4?")
        for answer in ["10", "10.0", "10.00", "10,0", "010"] {
            #expect(question.evaluate(answer) == .correct, "\(answer)")
        }
        for answer in ["1", "100", "10.1", "1.0"] {
            #expect(question.evaluate(answer) == .incorrect, "\(answer)")
        }
    }

    /// Tenths are added, subtracted and multiplied as whole numbers, so 0.1 + 0.2 is exactly 0.3
    /// and 0.7 × 3 is exactly 2.1, which Double arithmetic gets wrong.
    @Test func noFloatingPointErrors() {
        let doubleSum = 0.1 + 0.2
        let doubleProduct = 0.7 * 3
        #expect(doubleSum != 0.3)
        #expect(doubleProduct != 2.1)

        let sum = Year4DecimalsQuestion(kind: .add, first: 1, second: 2, multiplier: 1)
        #expect(sum.evaluate("0.3") == .correct)
        #expect(sum.evaluate("\(doubleSum)") == .incorrect)

        let product = Year4DecimalsQuestion(kind: .multiply, first: 7, second: 0, multiplier: 3)
        #expect(product.text == "What is 0.7 × 3?")
        #expect(product.evaluate("2.1") == .correct)
        #expect(product.evaluate("\(doubleProduct)") == .incorrect)

        let difference = Year4DecimalsQuestion(kind: .subtract, first: 3, second: 1, multiplier: 1)
        #expect(difference.text == "What is 0.3 - 0.1?")
        #expect(difference.evaluate("0.2") == .correct)
    }

    /// "1,500" could be 1500 or 1.5, so it gets a message rather than being marked. Other text is
    /// marked wrong, as before.
    @Test func invalidAnswers() {
        let question = Year4DecimalsQuestion(kind: .add, first: 10, second: 5, multiplier: 1)
        #expect(question.evaluate("1,500") == .ambiguousComma)
        #expect(question.evaluate("") == .unanswered)
        #expect(question.evaluate("  ") == .unanswered)
        for answer in ["abc", "-1.5", "1.5.0", "1e1", "1.5x", "99999999999999999999"] {
            #expect(question.evaluate(answer) == .incorrect, "\(answer)")
        }
    }

    @Test func numbersAreShownWithOneDecimalPlace() {
        #expect(Year4DecimalsQuestion.decimal(0) == "0.0")
        #expect(Year4DecimalsQuestion.decimal(5) == "0.5")
        #expect(Year4DecimalsQuestion.decimal(40) == "4.0")
        #expect(Year4DecimalsQuestion.decimal(100) == "10.0")
        #expect(Year4DecimalsQuestion.decimal(1000) == "100.0")
    }

    @Test func generatedQuestions() {
        var generator = SeededGenerator(seed: 0x3C_0401)
        var kinds = Set<String>()
        for _ in 0..<10_000 {
            let question = Year4DecimalsQuestion.random(using: &generator)
            kinds.insert("\(question.kind)")
            #expect((0...100).contains(question.first))
            #expect((0...100).contains(question.second))
            #expect((1...10).contains(question.multiplier))
            #expect(question.answerInTenths >= 0)

            let shown = decimalsShown(in: question.text)
            #expect(shown.count == 2)
            if shown.count == 2 {
                #expect(TypedAnswer.isNumber(shown[0], equalTo: question.first, over: 10))
                let secondNumber = question.kind == .multiply ? question.multiplier * 10 : question.second
                #expect(TypedAnswer.isNumber(shown[1], equalTo: secondNumber, over: 10))
            }

            switch question.kind {
            case .add:
                #expect(question.answerInTenths == question.first + question.second)
            case .subtract:
                #expect(question.first >= question.second)
                #expect(question.answerInTenths == question.first - question.second)
            case .multiply:
                #expect(question.answerInTenths == question.first * question.multiplier)
            }

            let answer = question.answerInTenths
            #expect(question.evaluate(Year4DecimalsQuestion.decimal(answer)) == .correct)
            #expect(question.evaluate(Year4DecimalsQuestion.decimal(answer) + "0") == .correct)
            #expect(question.evaluate(Year4DecimalsQuestion.decimal(answer) + "1") == .incorrect)
            #expect(question.evaluate(Year4DecimalsQuestion.decimal(answer + 1)) == .incorrect)
            if answer > 0 {
                #expect(question.evaluate(Year4DecimalsQuestion.decimal(answer - 1)) == .incorrect)
            }
            if answer % 10 == 0 {
                #expect(question.evaluate(String(answer / 10)) == .correct)
            }
        }
        #expect(kinds.count == 3)
    }
}

// MARK: - Year 4 Money (MQ-29)

struct Year4MoneyQuestionTests {
    private func adding(_ first: Int, _ second: Int) -> Year4MoneyQuestion {
        Year4MoneyQuestion(kind: .add, first: first, second: second, pennies: 0)
    }

    @Test func amountsAreShownInPoundsAndPence() {
        #expect(Year4MoneyQuestion.pounds(0) == "0.00")
        #expect(Year4MoneyQuestion.pounds(5) == "0.05")
        #expect(Year4MoneyQuestion.pounds(50) == "0.50")
        #expect(Year4MoneyQuestion.pounds(250) == "2.50")
        #expect(Year4MoneyQuestion.pounds(1000) == "10.00")
        #expect(Year4MoneyQuestion.pounds(2000) == "20.00")
    }

    /// MQ-29: the answer and the right amount were both rounded to two decimal places with
    /// String(format: "%.2f") before comparing, so 2.499 and 2.501 were accepted for £2.50.
    @Test func wrongAmountsAreNeverCorrect() {
        let oldAccepts = { (answer: String) -> Bool in
            guard let typed = Double(answer.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
            return String(format: "%.2f", typed) == String(format: "%.2f", 1.25 + 1.25)
        }
        #expect(oldAccepts("2.499"))
        #expect(oldAccepts("2.501"))

        let question = adding(125, 125)
        #expect(question.text == "Add £1.25 and £1.25")
        for answer in ["2.499", "2.501", "2.51", "2.49", "3.50", "250", "25.00", "0.25"] {
            #expect(question.evaluate(answer) == .incorrect, "\(answer)")
        }
    }

    /// MQ-29: any answer with no decimal point, or fewer than two decimal places, got the "2 decimal
    /// places" message whatever its value, so a wrong answer such as 3 was never marked wrong. The
    /// message is now only for the right amount written another way.
    @Test func formattingFeedbackIsOnlyForTheRightAmount() {
        let oldAsksForTwoPlaces = { (answer: String) -> Bool in
            !answer.contains(".") || (answer.split(separator: ".").last?.count ?? 0) < 2
        }
        #expect(oldAsksForTwoPlaces("3"))
        #expect(oldAsksForTwoPlaces("3.9"))

        let question = adding(125, 125)
        for answer in ["3", "3.9", "2.6", "2", "3.0"] {
            #expect(question.evaluate(answer) == .incorrect, "\(answer)")
        }
        for answer in ["2.5", "£2.5", "2,5", "2.500", "£2.500"] {
            #expect(question.evaluate(answer) == .needsTwoDecimalPlaces, "\(answer)")
        }
    }

    @Test func rightAmountsInPoundsAndPence() {
        let question = adding(125, 125)
        for answer in ["2.50", "£2.50", " £2.50 ", "£ 2.50", "2,50", "£2,50", "02.50"] {
            #expect(question.evaluate(answer) == .correct, "\(answer)")
        }

        // Whole pounds can be written without pence.
        let whole = adding(250, 250)
        for answer in ["5", "£5", "5.00", "£5.00", "05"] {
            #expect(whole.evaluate(answer) == .correct, "\(answer)")
        }
        #expect(whole.evaluate("5.0") == .needsTwoDecimalPlaces)
        #expect(whole.evaluate("5.000") == .needsTwoDecimalPlaces)
        #expect(whole.evaluate("500") == .incorrect)
        #expect(whole.evaluate("50") == .incorrect)

        let nothing = Year4MoneyQuestion(kind: .subtract, first: 300, second: 300, pennies: 0)
        #expect(nothing.text == "Subtract £3.00 from £3.00")
        for answer in ["0", "£0", "0.00", "£0.00"] {
            #expect(nothing.evaluate(answer) == .correct, "\(answer)")
        }
    }

    @Test func convertingPenniesToPounds() {
        let few = Year4MoneyQuestion(kind: .convert, first: 0, second: 0, pennies: 7)
        #expect(few.text == "Convert 7p to pounds")
        #expect(few.evaluate("0.07") == .correct)
        #expect(few.evaluate("£0.07") == .correct)
        #expect(few.evaluate("0.7") == .incorrect)
        #expect(few.evaluate("0.70") == .incorrect)
        #expect(few.evaluate("7") == .incorrect)

        let many = Year4MoneyQuestion(kind: .convert, first: 0, second: 0, pennies: 300)
        #expect(many.evaluate("3") == .correct)
        #expect(many.evaluate("3.00") == .correct)
        #expect(many.evaluate("3.0") == .needsTwoDecimalPlaces)
        #expect(many.evaluate("300") == .incorrect)
    }

    /// Blank, malformed and ambiguous answers get a message rather than a wrong attempt.
    @Test func invalidAnswersAreNotMarked() {
        let question = adding(125, 125)
        for answer in ["", " ", "£", " £ "] {
            #expect(question.evaluate(answer) == .unanswered, "\(answer)")
        }
        for answer in ["abc", "-2.50", "££2.50", "£-2.50", "2.50p", "2.50£", "1e3", "2.5.0", "99999999999999999999"] {
            #expect(question.evaluate(answer) == .notANumber, "\(answer)")
        }
        for answer in ["1,500", "£2,500"] {
            #expect(question.evaluate(answer) == .ambiguousComma, "\(answer)")
        }
    }

    @Test func generatedQuestions() {
        var generator = SeededGenerator(seed: 0x3C_0402)
        var kinds = Set<String>()
        for _ in 0..<10_000 {
            let question = Year4MoneyQuestion.random(using: &generator)
            kinds.insert("\(question.kind)")
            #expect((0...1000).contains(question.first))
            #expect((0...1000).contains(question.second))
            #expect((0...1000).contains(question.pennies))
            #expect(question.answerInPence >= 0)

            switch question.kind {
            case .add:
                let shown = decimalsShown(in: question.text)
                #expect(shown == [Year4MoneyQuestion.pounds(question.first), Year4MoneyQuestion.pounds(question.second)])
                #expect(question.answerInPence == question.first + question.second)
            case .subtract:
                let shown = decimalsShown(in: question.text)
                #expect(shown == [Year4MoneyQuestion.pounds(question.second), Year4MoneyQuestion.pounds(question.first)])
                #expect(question.first >= question.second)
                #expect(question.answerInPence == question.first - question.second)
            case .convert:
                #expect(numbersShown(in: question.text) == [question.pennies])
                #expect(question.answerInPence == question.pennies)
            }

            let answer = question.answerInPence
            let written = Year4MoneyQuestion.pounds(answer)
            #expect(question.evaluate(written) == .correct)
            #expect(question.evaluate("£" + written) == .correct)
            #expect(question.evaluate(written + "0") == .needsTwoDecimalPlaces)
            #expect(question.evaluate(Year4MoneyQuestion.pounds(answer + 1)) == .incorrect)
            if answer > 0 {
                #expect(question.evaluate(Year4MoneyQuestion.pounds(answer - 1)) == .incorrect)
            }
            if answer % 100 == 0 {
                #expect(question.evaluate(String(answer / 100)) == .correct)
            }
        }
        #expect(kinds.count == 3)
    }
}

// MARK: - Year 6 Algebra (MQ-21)

struct LinearExpressionTests {
    private func parsed(_ text: String) -> [Int]? {
        LinearExpression(simplified: text).map { [$0.coefficient, $0.constant] }
    }

    /// Terms in either order, with or without spaces, signs and capitals.
    @Test func simplifiedExpressions() {
        let accepted: [(String, [Int])] = [
            ("15x+6", [15, 6]), ("15x + 6", [15, 6]), ("6 + 15x", [15, 6]), ("+6+15x", [15, 6]),
            ("15X + 6", [15, 6]), (" 15 x + 6 ", [15, 6]), ("015x + 06", [15, 6]),
            ("15x - 6", [15, -6]), ("-6 + 15x", [15, -6]), ("15x − 6", [15, -6]), ("15x – 6", [15, -6]),
            ("x", [1, 0]), ("19x", [19, 0]), ("+19x", [19, 0]), ("-x + 3", [-1, 3]), ("3 - x", [-1, 3]),
            ("7", [0, 7]), ("-7", [0, -7]),
            ("\(Int.max)x", [Int.max, 0]), ("-\(Int.max)", [0, -Int.max]),
        ]
        for (text, expression) in accepted {
            #expect(parsed(text) == expression, "\(text)")
        }
        #expect(LinearExpression(simplified: "6 + 15x") == LinearExpression(simplified: "15x + 6"))
        #expect(LinearExpression(simplified: "15x - 6") != LinearExpression(simplified: "15x + 6"))
    }

    /// Unsimplified answers, other notation and numbers too large for Int are all rejected.
    @Test func everythingElseIsRejected() {
        let rejected = ["", " ", "+", "-", "x + x", "7x + 12x", "15x + 6 + 0", "15x + 0", "0x + 6", "0",
                        "15x + 3 + 3", "15*x + 6", "15·x + 6", "3(5x + 2)", "15x + 6 = 0", "1.5x", "15y + 6",
                        "x^2", "19x²", "15xx", "x15", "15x6", "6x15", "15x++6", "15x+-6", "15x +", "++6",
                        "fifteen x", "99999999999999999999x", "15x + 99999999999999999999", "\(Int.min)"]
        for text in rejected {
            #expect(parsed(text) == nil, "\(text)")
        }
    }
}

struct Year6AlgebraQuestionTests {
    /// True if the expression shows "1x" as a term, rather than "x".
    private func showsACoefficientOfOne(_ expression: String) -> Bool {
        let characters = Array(expression)
        for index in characters.indices.dropLast() where characters[index] == "1" && characters[index + 1] == "x" {
            if index == 0 || !characters[index - 1].isNumber {
                return true
            }
        }
        return false
    }

    /// MQ-21: answers were compared as text with the spaces removed, so 6 + 15x was marked wrong
    /// for 3(5x + 2), although it's the same expression. Answers are now read as algebra.
    @Test func expandedTermsCanBeInEitherOrder() {
        let oldAccepts = { (answer: String) -> Bool in
            answer.replacingOccurrences(of: " ", with: "").lowercased() == "15x+6"
        }
        #expect(oldAccepts("15x + 6"))
        #expect(!oldAccepts("6 + 15x"))

        let question = Year6AlgebraQuestion(kind: .expand, first: 5, second: 2, multiplier: 3)
        #expect(question.expression == "3(5x + 2)")
        for answer in ["15x + 6", "15x+6", "6 + 15x", "6+15x", "15X + 6", "+15x + 6", " 15x + 6 "] {
            #expect(question.evaluate(answer) == .correct, "\(answer)")
        }
    }

    /// Signs, coefficients and constants all have to be right, and the answer fully simplified.
    @Test func wrongExpansionsAreRejected() {
        let question = Year6AlgebraQuestion(kind: .expand, first: 5, second: 2, multiplier: 3)
        let wrong = ["15x - 6", "-15x + 6", "-6 + 15x", "6x + 15", "15 + 6x", "15x", "6", "15x + 2", "5x + 6",
                     "5x + 2", "16x + 6", "15x + 7", "21x", "21", "3(5x + 2)", "15x + 3 + 3", "15x + 6 + 0",
                     "x15 + 6", "15x + 6 = 0", "15y + 6", "15", "x"]
        for answer in wrong {
            #expect(question.evaluate(answer) == .incorrect, "\(answer)")
        }
        #expect(question.evaluate("") == .unanswered)
        #expect(question.evaluate("  ") == .unanswered)
    }

    @Test func simplifyingCollectsLikeTerms() {
        let question = Year6AlgebraQuestion(kind: .simplify, first: 7, second: 12, multiplier: 2)
        #expect(question.expression == "7x + 12x")
        for answer in ["19x", "19X", " 19x ", "+19x"] {
            #expect(question.evaluate(answer) == .correct, "\(answer)")
        }
        for answer in ["19", "x19", "7x + 12x", "12x + 7x", "19x + 0", "84x", "19x²", "-19x", "x", "19y"] {
            #expect(question.evaluate(answer) == .incorrect, "\(answer)")
        }

        let ones = Year6AlgebraQuestion(kind: .simplify, first: 1, second: 1, multiplier: 2)
        #expect(ones.expression == "x + x")
        #expect(ones.evaluate("2x") == .correct)
        #expect(ones.evaluate("x2") == .incorrect)
        #expect(ones.evaluate("2") == .incorrect)
    }

    @Test func solvingTheEquation() {
        let question = Year6AlgebraQuestion(kind: .solve, first: 7, second: 12, multiplier: 2)
        #expect(question.expression == "x + 7 = 19")
        // Updated deliberately in Stage 9C Batch 2 (B2-2): "12 = x" and "+12" say the same thing as "x = 12", so
        // they're now accepted. Everything else is unchanged.
        for answer in ["12", " 12 ", "012", "x = 12", "x=12", "X = 12", "12 = x", "+12"] {
            #expect(question.evaluate(answer) == .correct, "\(answer)")
        }
        for answer in ["19", "7", "26", "-12", "12.5", "x", "x =", "12x", "x = 19", "99999999999999999999"] {
            #expect(question.evaluate(answer) == .incorrect, "\(answer)")
        }
        #expect(question.evaluate("") == .unanswered)
    }

    /// MQ-21: the expressions were introduced as "Simplify this equation" and "Expand this equation".
    /// Only the first question is an equation, and only it has an equals sign.
    @Test func equationsAndExpressionsAreNamedCorrectly() {
        var generator = SeededGenerator(seed: 0x3C_0601)
        var kinds = Set<String>()
        for _ in 0..<5_000 {
            let question = Year6AlgebraQuestion.random(using: &generator)
            kinds.insert("\(question.kind)")
            switch question.kind {
            case .solve:
                #expect(question.instruction == "Solve for x in this equation")
                #expect(question.expression.filter { $0 == "=" }.count == 1)
            case .simplify:
                #expect(question.instruction == "Simplify this expression")
                #expect(!question.expression.contains("="))
            case .expand:
                #expect(question.instruction == "Expand this expression")
                #expect(!question.expression.contains("="))
            }
        }
        #expect(kinds.count == 3)
    }

    /// The old questions showed 1x and 1(…). Numbers stay in 1..<20 and the multiplier in 2...4, and
    /// the numbers shown are the ones the answer is worked out from.
    @Test func generatedQuestions() {
        var generator = SeededGenerator(seed: 0x3C_0602)
        for _ in 0..<10_000 {
            let question = Year6AlgebraQuestion.random(using: &generator)
            #expect((1..<20).contains(question.first))
            #expect((1..<20).contains(question.second))
            #expect((2...4).contains(question.multiplier))
            #expect(!showsACoefficientOfOne(question.expression), "\(question.expression)")

            let shown = numbersShown(in: question.expression)
            let answer = question.answer
            switch question.kind {
            case .solve:
                #expect(shown == [question.first, question.first + question.second])
                #expect(answer == LinearExpression(coefficient: 0, constant: question.second))
                #expect(question.evaluate(String(question.second)) == .correct)
                #expect(question.evaluate("x = \(question.second)") == .correct)
                #expect(question.evaluate(String(question.first + question.second)) == .incorrect)
            case .simplify:
                #expect(shown == [question.first, question.second].filter { $0 != 1 })
                #expect(answer == LinearExpression(coefficient: question.first + question.second, constant: 0))
                #expect(question.evaluate("\(question.first + question.second)x") == .correct)
                #expect(question.evaluate(String(question.first + question.second)) == .incorrect)
            case .expand:
                #expect(shown == [question.multiplier] + [question.first].filter { $0 != 1 } + [question.second])
                let coefficient = question.multiplier * question.first
                let constant = question.multiplier * question.second
                #expect(answer == LinearExpression(coefficient: coefficient, constant: constant))
                let term = coefficient == 1 ? "x" : "\(coefficient)x"
                #expect(question.evaluate("\(term) + \(constant)") == .correct)
                #expect(question.evaluate("\(constant) + \(term)") == .correct)
                #expect(question.evaluate("\(term) - \(constant)") == .incorrect)
                #expect(question.evaluate("\(question.first)x + \(question.second)") == .incorrect)
            }
        }
    }
}

// MARK: - Progression in the Stage 3C activities

/// What one press of Enter or Return does, with the view's own messages.
private enum Stage3CMark: Equatable {
    case correct, incorrect
    /// A message without marking the answer, such as "Please enter an answer!".
    case feedback(String)
}

/// One question as the progression tests see it: how it is marked, an answer the marking accepts,
/// one it rejects, and answers that only get a message.
private struct Stage3CItem {
    let mark: (String) -> Stage3CMark
    let rightAnswer: String
    let wrongAnswer: String
    let unmarkedAnswers: [String]
}

private let enterAnAnswer = Stage3CMark.feedback("Please enter an answer!")

private extension Year1CountingQuestion {
    var item: Stage3CItem {
        Stage3CItem(mark: {
            switch evaluate($0) {
            case .correct: return .correct
            case .incorrect: return .incorrect
            case .unanswered: return enterAnAnswer
            }
        }, rightAnswer: String(missingNumber), wrongAnswer: String(missingNumber + 1), unmarkedAnswers: ["", " "])
    }
}

private extension Year2MultiplicationQuestion {
    var item: Stage3CItem {
        Stage3CItem(mark: {
            switch evaluate($0) {
            case .correct: return .correct
            case .incorrect: return .incorrect
            case .unanswered: return enterAnAnswer
            }
        }, rightAnswer: String(product), wrongAnswer: String(product + 1), unmarkedAnswers: ["", " "])
    }
}

private extension Year2DivisionQuestion {
    var item: Stage3CItem {
        Stage3CItem(mark: {
            switch evaluate($0) {
            case .correct: return .correct
            case .incorrect: return .incorrect
            case .unanswered: return enterAnAnswer
            }
        }, rightAnswer: String(quotient), wrongAnswer: String(quotient + 1), unmarkedAnswers: ["", " "])
    }
}

private extension Year2ShapeQuestion {
    var item: Stage3CItem {
        let right: String
        let wrong: String
        switch kind {
        case .sides:
            right = String(figure.straightSides)
            wrong = String(figure.straightSides + 1)
        case .corners:
            right = String(figure.corners)
            wrong = String(figure.corners + 1)
        case .name:
            right = figure.name
            wrong = Self.figures[(figureIndex + 1) % Self.figures.count].name
        }
        return Stage3CItem(mark: {
            switch evaluate($0) {
            case .correct: return .correct
            case .incorrect: return .incorrect
            case .unanswered: return enterAnAnswer
            }
        }, rightAnswer: right, wrongAnswer: wrong, unmarkedAnswers: ["", " "])
    }
}

private extension Year3MeasurementQuestion {
    /// The right unit is picked, so only the typed number varies.
    var item: Stage3CItem {
        let expected = kind == .convert ? convertedAmount : objectLength
        let unit = kind == .convert ? toUnit : ""
        return Stage3CItem(mark: {
            switch evaluate(answer: $0, unit: unit) {
            case .correct: return .correct
            case .incorrect: return .incorrect
            case .unanswered: return enterAnAnswer
            case .notANumber: return .feedback("Please enter a valid number!")
            case .ambiguousComma: return .feedback("Write it without a comma.")
            }
        }, rightAnswer: String(expected), wrongAnswer: String(expected + 1), unmarkedAnswers: ["", "abc", "1,000"])
    }
}

private extension Year4DecimalsQuestion {
    var item: Stage3CItem {
        Stage3CItem(mark: {
            switch evaluate($0) {
            case .correct: return .correct
            case .incorrect: return .incorrect
            case .unanswered: return enterAnAnswer
            case .ambiguousComma: return .feedback("Use a decimal point.")
            }
        }, rightAnswer: Self.decimal(answerInTenths), wrongAnswer: Self.decimal(answerInTenths + 1),
           unmarkedAnswers: ["", " ", "1,500"])
    }
}

private extension Year4MoneyQuestion {
    var item: Stage3CItem {
        let right = Self.pounds(answerInPence)
        return Stage3CItem(mark: {
            switch evaluate($0) {
            case .correct: return .correct
            case .incorrect: return .incorrect
            case .unanswered: return enterAnAnswer
            case .notANumber: return .feedback("Please enter a number!")
            case .needsTwoDecimalPlaces: return .feedback("Make sure to write your answer with 2 decimal places. E.g. £1.23")
            case .ambiguousComma: return .feedback("Use a decimal point.")
            }
        }, rightAnswer: right, wrongAnswer: Self.pounds(answerInPence + 1),
           unmarkedAnswers: ["", "£", "abc", "1,500", right + "0"])
    }
}

private extension Year6AlgebraQuestion {
    var item: Stage3CItem {
        let right: String
        let wrong: String
        switch kind {
        case .solve:
            right = String(second)
            wrong = String(second + 1)
        case .simplify:
            right = "\(first + second)x"
            wrong = "\(first + second + 1)x"
        case .expand:
            right = "\(multiplier * first)x + \(multiplier * second)"
            wrong = "\(multiplier * first)x - \(multiplier * second)"
        }
        return Stage3CItem(mark: {
            switch evaluate($0) {
            case .correct: return .correct
            case .incorrect: return .incorrect
            case .unanswered: return enterAnAnswer
            }
        }, rightAnswer: right, wrongAnswer: wrong, unmarkedAnswers: ["", " "])
    }
}

enum Stage3CActivity: CaseIterable {
    case year1Counting, year2Multiplication, year2Division, year2Shapes
    case year3Measurement, year4Decimals, year4Money, year6Algebra

    /// Real questions from the activity's own generator.
    fileprivate func questions(count: Int, seed: UInt64) -> [Stage3CItem] {
        var generator = SeededGenerator(seed: seed)
        return (0..<count).map { _ in
            switch self {
            case .year1Counting: return Year1CountingQuestion.random(using: &generator).item
            case .year2Multiplication: return Year2MultiplicationQuestion.random(using: &generator).item
            case .year2Division: return Year2DivisionQuestion.random(using: &generator).item
            case .year2Shapes: return Year2ShapeQuestion.random(using: &generator).item
            case .year3Measurement: return Year3MeasurementQuestion.random(using: &generator).item
            case .year4Decimals: return Year4DecimalsQuestion.random(using: &generator).item
            case .year4Money: return Year4MoneyQuestion.random(using: &generator).item
            case .year6Algebra: return Year6AlgebraQuestion.random(using: &generator).item
            }
        }
    }

    /// Questions from random(), which each view uses for its first question and every later one.
    fileprivate func unseededQuestions(count: Int) -> [Stage3CItem] {
        (0..<count).map { _ in
            switch self {
            case .year1Counting: return Year1CountingQuestion.random().item
            case .year2Multiplication: return Year2MultiplicationQuestion.random().item
            case .year2Division: return Year2DivisionQuestion.random().item
            case .year2Shapes: return Year2ShapeQuestion.random().item
            case .year3Measurement: return Year3MeasurementQuestion.random().item
            case .year4Decimals: return Year4DecimalsQuestion.random().item
            case .year4Money: return Year4MoneyQuestion.random().item
            case .year6Algebra: return Year6AlgebraQuestion.random().item
            }
        }
    }
}

/// Drives QuestionProgress as the Stage 3C views do. checkAnswer() ignores Enter and Return once the
/// question has been answered or skipped, shows a message without a wrong attempt for a blank or
/// badly written answer, and otherwise marks it. A correct answer or a rewarded Skip schedules
/// resetQuestion() a second later, which waits here until finishTransition(), so every press in
/// between lands in the transition. Enter is modelled without its .disabled(showMessage), as Return
/// is never disabled.
private struct Stage3CSession {
    private var upcoming: [Stage3CItem]
    private(set) var question: Stage3CItem
    private(set) var progress = QuestionProgress()
    var answer = ""
    private(set) var message = ""
    private(set) var points = 0
    private(set) var totalQuestionsAnswered = 0
    /// resetQuestion() calls waiting for the second to pass.
    private(set) var pendingResets = 0
    private(set) var questionNumber = 1

    init(_ questions: [Stage3CItem]) {
        question = questions[0]
        upcoming = Array(questions.dropFirst())
    }

    mutating func pressEnter() { checkAnswer() }
    mutating func pressReturn() { checkAnswer() }

    private mutating func checkAnswer() {
        guard !progress.isAdvancing else { return }

        switch question.mark(answer) {
        case let .feedback(text):
            message = text
        case .correct:
            guard progress.recordCorrectAnswer() else { return }
            message = "Correct!"
            points += 1
            totalQuestionsAnswered += 1
            pendingResets += 1
        case .incorrect:
            message = "Incorrect. Try Again!"
            progress.recordWrongAttempt()
        }
    }

    /// Skip is tapped and the reward is earned.
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

struct Stage3CProgressionTests {
    private func makeSession(_ activity: Stage3CActivity, seed: UInt64 = 0x3C_9005) -> Stage3CSession {
        Stage3CSession(activity.questions(count: 20, seed: seed))
    }

    /// The tests below rely on these answers being marked right, wrong and not at all.
    @Test(arguments: Stage3CActivity.allCases)
    func everyQuestionHasARightAWrongAndAnUnmarkedAnswer(activity: Stage3CActivity) {
        let questions = activity.questions(count: 3_000, seed: 0x3C_9001) + activity.unseededQuestions(count: 500)
        for item in questions {
            #expect(item.mark(item.rightAnswer) == .correct, "\(item.rightAnswer)")
            #expect(item.mark(item.wrongAnswer) == .incorrect, "\(item.wrongAnswer)")
            for answer in item.unmarkedAnswers {
                #expect(item.mark(answer) != .correct && item.mark(answer) != .incorrect, "\(answer)")
            }
        }
    }

    /// Enter pressed again and again before the next question appears.
    @Test(arguments: Stage3CActivity.allCases)
    func repeatedEnterScoresOnce(activity: Stage3CActivity) {
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
        #expect(session.points == 1)
    }

    /// Return pressed again and again, and Return and Enter mixed, before the next question appears.
    @Test(arguments: Stage3CActivity.allCases)
    func repeatedReturnScoresOnce(activity: Stage3CActivity) {
        var session = makeSession(activity)
        session.answer = session.question.rightAnswer
        session.pressReturn()
        session.pressReturn()
        session.pressEnter()
        session.pressReturn()
        #expect(session.points == 1)
        #expect(session.totalQuestionsAnswered == 1)
        #expect(session.pendingResets == 1)
        session.finishTransition()
        #expect(session.questionNumber == 2)
    }

    @Test(arguments: Stage3CActivity.allCases)
    func enterAfterAnEarlierWrongAnswerScoresOnce(activity: Stage3CActivity) {
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

    @Test(arguments: Stage3CActivity.allCases)
    func wrongAnswersNeverScore(activity: Stage3CActivity) {
        var session = makeSession(activity)
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
        #expect(session.progress.wrongAttempts == 9)
        #expect(session.progress.showSkipButton)
        #expect(session.message == "Incorrect. Try Again!")
    }

    /// Blank and badly written answers, such as £2.5 for £2.50, get their message without counting
    /// as wrong attempts, so they never bring up Skip, and the question can still be scored.
    @Test(arguments: Stage3CActivity.allCases)
    func unmarkedAnswersAreNotWrongAttempts(activity: Stage3CActivity) {
        var session = makeSession(activity)
        for answer in session.question.unmarkedAnswers {
            session.answer = answer
            session.pressEnter()
            session.pressReturn()
            #expect(session.message != "Incorrect. Try Again!", "\(answer)")
            #expect(!session.message.isEmpty, "\(answer)")
        }
        #expect(session.progress.wrongAttempts == 0)
        #expect(!session.progress.showSkipButton)
        session.answer = session.question.rightAnswer
        session.pressEnter()
        #expect(session.points == 1)
        #expect(session.message == "Correct!")
    }

    /// Changing the answer during "Correct!" doesn't show another message or count as a wrong attempt.
    @Test(arguments: Stage3CActivity.allCases)
    func editingTheAnswerDuringTheTransitionIsIgnored(activity: Stage3CActivity) {
        var session = makeSession(activity)
        session.answer = session.question.wrongAnswer
        session.pressEnter()
        session.answer = session.question.rightAnswer
        session.pressEnter()
        session.answer = session.question.wrongAnswer
        session.pressReturn()
        for answer in session.question.unmarkedAnswers {
            session.answer = answer
            session.pressEnter()
        }
        #expect(session.message == "Correct!")
        #expect(session.progress.wrongAttempts == 1)
        #expect(!session.progress.showSkipButton)
        #expect(session.points == 1)
    }

    @Test(arguments: Stage3CActivity.allCases)
    func skipCannotFollowACorrectAnswer(activity: Stage3CActivity) {
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
        session.finishTransition()
        #expect(session.questionNumber == 2)
        #expect(session.points == 1)
    }

    @Test(arguments: Stage3CActivity.allCases)
    func repeatedSkipMovesOnOneQuestion(activity: Stage3CActivity) {
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
        session.answer = session.question.rightAnswer
        session.pressEnter()
        #expect(session.points == 0)
        #expect(session.totalQuestionsAnswered == 0)
        session.finishTransition()
        #expect(session.questionNumber == 2)
        #expect(session.points == 0)
    }

    @Test(arguments: Stage3CActivity.allCases)
    func nextQuestionStartsClean(activity: Stage3CActivity) {
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

        session.answer = session.question.wrongAnswer
        session.pressReturn()
        session.pressReturn()
        session.tapSkipAndEarnReward()
        session.finishTransition()
        #expect(session.questionNumber == 3)
        #expect(session.progress == QuestionProgress())

        session.answer = session.question.wrongAnswer
        session.pressEnter()
        #expect(session.progress.wrongAttempts == 1)
        #expect(!session.progress.showSkipButton)
        session.answer = session.question.rightAnswer
        session.pressReturn()
        #expect(session.points == 2)
        session.finishTransition()
        #expect(session.questionNumber == 4)
    }

    /// Long random sequences of Enter, Return, edits and Skip taps on real questions. Each question
    /// scores or is skipped at most once, only a right answer scores, unmarked answers never count
    /// as wrong attempts, and Skip needs two wrong attempts.
    @Test(arguments: Stage3CActivity.allCases)
    func randomSessionsScoreOrSkipEachQuestionAtMostOnce(activity: Stage3CActivity) {
        var generator = SeededGenerator(seed: 0x3C_9030)
        var session = Stage3CSession(activity.questions(count: 6_000, seed: 0x3C_9031))
        var advances = 0
        var mistakes = [String]()

        for step in 0..<20_000 {
            let points = session.points
            let wrong = session.progress.wrongAttempts
            let wasAdvancing = session.progress.isAdvancing
            let question = session.questionNumber
            var typed: Stage3CMark?

            switch Int.random(in: 0..<7, using: &generator) {
            case 0, 1:
                session.answer = session.question.rightAnswer
                typed = .correct
            case 2, 3:
                session.answer = session.question.wrongAnswer
                typed = .incorrect
            case 4:
                session.answer = session.question.unmarkedAnswers.randomElement(using: &generator)!
                typed = enterAnAnswer
            case 5:
                session.tapSkipAndEarnReward()
                if session.progress.isAdvancing && !wasAdvancing && wrong < QuestionProgress.wrongAttemptsBeforeSkip {
                    mistakes.append("step \(step): skipped after \(wrong) wrong attempts")
                }
            default:
                if session.pendingResets > 0 {
                    advances += session.pendingResets
                }
                session.finishTransition()
            }

            if let typed {
                if Bool.random(using: &generator) {
                    session.pressEnter()
                } else {
                    session.pressReturn()
                }
                let scored = session.points - points
                let counted = session.progress.wrongAttempts - wrong
                if scored > 1 || (scored == 1 && (typed != .correct || wasAdvancing)) {
                    mistakes.append("step \(step): scored \(scored) for \(typed)")
                }
                if counted != 0 && (typed != .incorrect || wasAdvancing) {
                    mistakes.append("step \(step): wrong attempts changed by \(counted) for \(typed)")
                }
            }
            if session.pendingResets > 1 {
                mistakes.append("step \(step): question \(question) advanced \(session.pendingResets) times")
            }
        }
        #expect(mistakes.isEmpty, "\(mistakes.prefix(5))")
        #expect(advances > 1_000)
        #expect(session.points <= session.questionNumber)
    }
}
