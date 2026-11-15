//
//  Explanations.swift
//  Maths Quest
//
//  Stage 9C: what an activity says after an answer, beyond "Correct!" and "Incorrect. Try Again!".
//  - After a counted wrong answer, a hint: the mistake, when the answer shows which one it was, or else a way to work
//    the question out. A hint never gives the answer, unless the answer is a number the question already shows.
//  - After a right answer, the finished number sentence under "Correct!", such as "4 × 5 = 20".
//  - After Skip, a worked solution: the question worked out in a few short steps, then the answer.
//
//  Every piece is worked out from the question's own numbers, separately from how the answer is checked, and has the
//  words VoiceOver reads alongside the words shown. The views only show what these return. Batch 1 covers Year 2
//  Multiplication, Year 2 Division, Year 4 Geometry and Year 6 Ratio; every other activity is unchanged.
//

import Foundation

/// Words as they're shown, and as VoiceOver reads them: "4 × 5 = 20" is read "4 times 5 equals 20", so VoiceOver
/// doesn't have to name the signs.
struct SpokenText: Equatable {
    let text: String
    let spoken: String

    init(_ text: String, spoken: String? = nil) {
        self.text = text
        self.spoken = spoken ?? text
    }
}

/// A question worked out after Skip: a few short numbered steps, then the answer on its own line.
struct WorkedSolution: Equatable {
    let steps: [SpokenText]
    /// "The answer is 20."
    let answer: SpokenText
}

/// A question that can explain itself. `Response` is what the child entered: one answer box, two, or a number and a
/// unit.
protocol ExplainedQuestion {
    associatedtype Response
    /// What to show after a counted wrong answer. Never the answer.
    func hint(after response: Response) -> SpokenText
    /// What to show after Skip.
    var workedSolution: WorkedSolution { get }
    /// The line under "Correct!".
    var correctLine: SpokenText { get }
}

/// Shared wording.
enum ExplanationWording {
    /// "The answer is 20." The words are the same shown and read, except where `spoken` says otherwise.
    static func answer(_ text: String, spoken: String? = nil) -> SpokenText {
        SpokenText("The answer is \(text).", spoken: "The answer is \(spoken ?? text).")
    }

    /// "fives" for 5, as counting in fives is said in class. The written form is "5s".
    static func pluralName(of number: Int) -> String {
        switch number {
        case 2: "twos"
        case 5: "fives"
        case 10: "tens"
        default: "\(number)s"
        }
    }

    /// "five" for 5, as in "One five makes 5".
    static func name(of number: Int) -> String {
        switch number {
        case 2: "two"
        case 5: "five"
        case 10: "ten"
        default: "\(number)"
        }
    }

    /// "5, 10, 15, 20": counting in `step` up to `count` of them.
    static func countingSequence(in step: Int, count: Int) -> String {
        (1...max(count, 1)).map { String($0 * step) }.joined(separator: ", ")
    }

    /// "group" or "groups".
    static func groups(_ count: Int) -> String {
        count == 1 ? "group" : "groups"
    }
}

// MARK: - Year 2 Multiplication

extension Year2MultiplicationQuestion: ExplainedQuestion {
    /// A wrong answer that shows what went wrong.
    enum Mistake: Equatable {
        /// The two numbers added, such as 9 for 4 × 5.
        case added
        /// One group too many or too few, such as 15 or 25 for 4 × 5.
        case oneGroupOut
    }

    /// The number to count in: the times table the question comes from, or the larger number when both are in the
    /// 2, 5 or 10 times tables, so there are fewer numbers to count.
    var countingStep: Int {
        switch (Self.tables.contains(first), Self.tables.contains(second)) {
        case (true, true): max(first, second)
        case (true, false): first
        default: second
        }
    }

    /// How many groups of `countingStep` make the product.
    var groupCount: Int {
        product / countingStep
    }

    /// "4 × 5 means 4 groups of 5." When the groups are written second, as in 5 × 4, multiplication is turned round
    /// first, as Year 2 learns it can be: "5 × 4 is the same as 4 × 5: 4 groups of 5."
    var meaning: SpokenText {
        let step = countingStep
        let count = groupCount
        let groups = "\(count) \(ExplanationWording.groups(count)) of \(step)"
        if first == count {
            return SpokenText("\(first) × \(second) means \(groups).",
                              spoken: "\(first) times \(second) means \(groups).")
        }
        return SpokenText("\(first) × \(second) is the same as \(count) × \(step): \(groups).",
                          spoken: "\(first) times \(second) is the same as \(count) times \(step): \(groups).")
    }

    /// The mistake `typed` shows, if any. Checked only once the answer is known to be wrong, so a right answer is
    /// never called a mistake. Adding is checked first: where adding and being a group out give the same number,
    /// as 6 does for 2 × 4, both messages are true of the question.
    func mistake(in typed: String) -> Mistake? {
        guard let number = TypedAnswer.wholeNumber(typed), number != product else { return nil }
        if number == first + second {
            return .added
        }
        if groupCount >= 2, number > 0, number == product - countingStep || number == product + countingStep {
            return .oneGroupOut
        }
        return nil
    }

    func hint(after typed: String) -> SpokenText {
        let step = countingStep
        let count = groupCount
        switch mistake(in: typed) {
        case .added:
            return SpokenText("× means groups of, not adding. \(meaning.text)",
                              spoken: "Times means groups of, not adding. \(meaning.spoken)")
        case .oneGroupOut:
            return SpokenText("Close. Count the groups again: you need \(count) groups of \(step).")
        case nil:
            break
        }
        if count == 1 {
            return meaning
        }
        let countIn = SpokenText("Count in \(step)s.", spoken: "Count in \(ExplanationWording.pluralName(of: step)).")
        if first == count {
            return SpokenText("\(count) groups of \(step). \(countIn.text)",
                              spoken: "\(count) groups of \(step). \(countIn.spoken)")
        }
        return SpokenText("\(first) × \(second) is the same as \(count) × \(step). \(countIn.text)",
                          spoken: "\(first) times \(second) is the same as \(count) times \(step). \(countIn.spoken)")
    }

    var workedSolution: WorkedSolution {
        let step = countingStep
        let count = groupCount
        let counting = count == 1
            ? SpokenText("1 group of \(step) is \(step).")
            : SpokenText("Count in \(step)s: \(ExplanationWording.countingSequence(in: step, count: count)).",
                         spoken: "Count in \(ExplanationWording.pluralName(of: step)): "
                             + "\(ExplanationWording.countingSequence(in: step, count: count)).")
        return WorkedSolution(steps: [meaning, counting], answer: ExplanationWording.answer(String(count * step)))
    }

    var correctLine: SpokenText {
        SpokenText("\(first) × \(second) = \(product)", spoken: "\(first) times \(second) equals \(product)")
    }
}

// MARK: - Year 2 Division

extension Year2DivisionQuestion: ExplainedQuestion {
    enum Mistake: Equatable {
        /// The two numbers multiplied, such as 100 for 20 ÷ 5.
        case multiplied
    }

    /// The mistake `typed` shows, if any. Checked only once the answer is known to be wrong.
    func mistake(in typed: String) -> Mistake? {
        guard let number = TypedAnswer.wholeNumber(typed), number != quotient else { return nil }
        return number == dividend * divisor ? .multiplied : nil
    }

    func hint(after typed: String) -> SpokenText {
        switch mistake(in: typed) {
        case .multiplied:
            return SpokenText("÷ means sharing or grouping, not multiplying. The answer is smaller than \(dividend).",
                              spoken: "Divided by means sharing or grouping, not multiplying. "
                                  + "The answer is smaller than \(dividend).")
        case nil:
            let name = ExplanationWording.pluralName(of: divisor)
            return SpokenText("How many \(divisor)s make \(dividend)? Count in \(divisor)s.",
                              spoken: "How many \(name) make \(dividend)? Count in \(name).")
        }
    }

    var workedSolution: WorkedSolution {
        let steps: [SpokenText]
        if quotient == 1 {
            steps = [SpokenText("One \(divisor) makes \(dividend).",
                                spoken: "One \(ExplanationWording.name(of: divisor)) makes \(dividend).")]
        } else {
            let sequence = ExplanationWording.countingSequence(in: divisor, count: quotient)
            let name = ExplanationWording.pluralName(of: divisor)
            steps = [
                SpokenText("Count in \(divisor)s until you reach \(dividend): \(sequence).",
                           spoken: "Count in \(name) until you reach \(dividend): \(sequence)."),
                SpokenText("That is \(sequence.split(separator: ",").count) \(name).")
            ]
        }
        return WorkedSolution(steps: steps, answer: ExplanationWording.answer(String(dividend / divisor)))
    }

    var correctLine: SpokenText {
        SpokenText("\(dividend) ÷ \(divisor) = \(quotient)", spoken: "\(dividend) divided by \(divisor) equals \(quotient)")
    }
}

// MARK: - Year 4 Geometry

extension Year4GeometryQuestion: ExplainedQuestion {
    /// The number typed, and the unit picked on the wheel ("" while it still says "Unit").
    typealias Response = (answer: String, unit: String)

    enum Mistake: Equatable {
        /// The area given for the perimeter of a rectangle, such as 28 for 7 cm × 4 cm.
        case gaveArea
        /// The perimeter given for the area, such as 22 for 7 cm × 4 cm.
        case gavePerimeter
        /// Two sides of a rectangle added, such as 11 for 7 cm × 4 cm: half the perimeter, or adding for the area.
        case addedTwoSides
        /// The right number, with no unit picked.
        case noUnit
        /// The right number, with the wrong unit picked.
        case wrongUnit
    }

    /// The sides added up, worked out here rather than taken from `perimeter`.
    private var sideTotal: Int {
        sides.reduce(0, +)
    }

    /// Length × width, for a rectangle only.
    private var rectangleArea: Int? {
        shapeType == 4 && sides.count == 4 ? sides[0] * sides[1] : nil
    }

    /// "centimetres" for cm.
    private var unitName: String {
        Self.unitNames[unitType]?.1 ?? unitType
    }

    /// "22 cm" for a perimeter, "28 cm²" for an area, and how each is read.
    private func measurement(_ number: Int, squared: Bool) -> SpokenText {
        squared
            ? SpokenText("\(number) \(unitType)²", spoken: "\(number) square \(unitName)")
            : SpokenText("\(number) \(unitType)", spoken: "\(number) \(unitName)")
    }

    /// "7 + 4 + 7 + 4", and "7 plus 4 plus 7 plus 4".
    private var sideSum: SpokenText {
        SpokenText(sides.map(String.init).joined(separator: " + "),
                   spoken: sides.map(String.init).joined(separator: " plus "))
    }

    /// The mistake `response` shows, if any. Checked in a fixed order, after the right answer is ruled out: the right
    /// number with the wrong unit, then the other measurement (area for perimeter, perimeter for area), then two sides
    /// added. So a 4 cm × 4 cm square, whose area and perimeter are both 16, is never told 16 is the other one, and
    /// 4 for the perimeter of a 2 cm × 2 cm square is "the area" rather than "two sides".
    func mistake(in response: Response) -> Mistake? {
        guard question == 1 || question == 2, let number = TypedAnswer.wholeNumber(response.answer) else { return nil }
        let isPerimeter = question == 1
        let expected = isPerimeter ? sideTotal : rectangleArea
        if number == expected {
            let unit = isPerimeter ? unitType : unitType + "²"
            guard response.unit != unit else { return nil }
            return response.unit.isEmpty ? .noUnit : .wrongUnit
        }
        guard let area = rectangleArea else { return nil }
        if isPerimeter, number == area {
            return .gaveArea
        }
        if !isPerimeter, number == sideTotal {
            return .gavePerimeter
        }
        if number == sides[0] + sides[1] {
            return .addedTwoSides
        }
        return nil
    }

    func hint(after response: Response) -> SpokenText {
        switch question {
        case 1:
            switch mistake(in: response) {
            case .gaveArea:
                return SpokenText("That is the area. Perimeter is the distance all the way round: add every side.")
            case .addedTwoSides:
                return SpokenText("Add all 4 sides, not only 2.")
            case .noUnit:
                return SpokenText("Pick a unit as well. Perimeter is a length: use the same unit as the sides.")
            case .wrongUnit:
                return SpokenText("Perimeter is a length. Use the same unit as the sides.")
            case .gavePerimeter, nil:
                return SpokenText(shapeType == 4
                    ? "Perimeter is the distance all the way round. Add all 4 sides."
                    : "Perimeter is the distance all the way round. Add every side.")
            }
        case 2:
            switch mistake(in: response) {
            case .gavePerimeter:
                return SpokenText("That is the perimeter. Area is the space inside: multiply length by width.")
            case .addedTwoSides:
                return SpokenText("For area, multiply the sides. Do not add them.")
            case .noUnit:
                return SpokenText("Pick a unit as well. Area is measured in square units, with a small ².",
                                  spoken: "Pick a unit as well. Area is measured in square units, with a small 2.")
            case .wrongUnit:
                return SpokenText("Area is measured in square units. Pick the one that matches the sides.")
            case .gaveArea, nil:
                return SpokenText("Area is the space inside. Multiply the length by the width.")
            }
        default:
            // The same whatever the angle, so it can't give the answer away. The question lists Acute, Right and
            // Obtuse, so "a right angle" doesn't either.
            return SpokenText("Compare the angle with a square corner (a right angle).")
        }
    }

    var workedSolution: WorkedSolution {
        switch question {
        case 1:
            let total = measurement(sideTotal, squared: false)
            let steps: [SpokenText]
            if shapeType == 4 {
                let listed = sides.dropLast().map(String.init).joined(separator: ", ") + " and \(sides.last ?? 0)"
                steps = [
                    SpokenText("The sides are \(listed) \(unitType).", spoken: "The sides are \(listed) \(unitName)."),
                    SpokenText("\(sideSum.text) = \(sideTotal).", spoken: "\(sideSum.spoken) equals \(sideTotal).")
                ]
            } else {
                steps = [SpokenText("Add the sides: \(sideSum.text) = \(sideTotal).",
                                    spoken: "Add the sides: \(sideSum.spoken) equals \(sideTotal).")]
            }
            return WorkedSolution(steps: steps, answer: ExplanationWording.answer(total.text, spoken: total.spoken))
        case 2:
            let area = rectangleArea ?? 0
            let total = measurement(area, squared: true)
            let steps = [
                SpokenText("Area = length × width.", spoken: "Area equals length times width."),
                SpokenText("\(sides[0]) × \(sides[1]) = \(area).", spoken: "\(sides[0]) times \(sides[1]) equals \(area).")
            ]
            return WorkedSolution(steps: steps, answer: ExplanationWording.answer(total.text, spoken: total.spoken))
        default:
            let comparison: String
            let answer: String
            switch angleMeasure {
            case ..<90:
                comparison = "This angle is smaller than a right angle."
                answer = "acute"
            case 90:
                comparison = "This angle is exactly a square corner."
                answer = "a right angle"
            default:
                comparison = "This angle is bigger than a right angle and smaller than a straight line."
                answer = "obtuse"
            }
            return WorkedSolution(steps: [SpokenText("A right angle is a square corner."), SpokenText(comparison)],
                                  answer: ExplanationWording.answer(answer))
        }
    }

    var correctLine: SpokenText {
        switch question {
        case 1:
            let total = measurement(sideTotal, squared: false)
            return SpokenText("\(sideSum.text) = \(total.text)", spoken: "\(sideSum.spoken) equals \(total.spoken)")
        case 2:
            let total = measurement(rectangleArea ?? 0, squared: true)
            return SpokenText("\(sides[0]) × \(sides[1]) = \(total.text)",
                              spoken: "\(sides[0]) times \(sides[1]) equals \(total.spoken)")
        default:
            switch angleMeasure {
            case ..<90: return SpokenText("This angle is acute.")
            case 90: return SpokenText("This is a right angle.")
            default: return SpokenText("This angle is obtuse.")
            }
        }
    }
}

// MARK: - Year 6 Ratio

extension Year6RatioQuestion: ExplainedQuestion {
    /// The two ratio boxes, and the missing-number box. Only the boxes the question shows are read.
    typealias Response = (first: String, second: String, missing: String)

    enum Mistake: Equatable {
        /// Only one of the two ratio boxes filled in.
        case oneBoxEmpty
        /// The right numbers the wrong way round, such as 3 : 2 for 8 : 12.
        case reversed
        /// The ratio from the question typed back.
        case sameAsQuestion
        /// An equal ratio that can be simplified more, such as 4 : 6 for 8 : 12.
        case notSimplest
        /// The ratio itself given as the shares, such as 3 : 4 for "Divide 35 in the ratio 3 : 4".
        case gaveRatio
        /// A missing number found by adding the difference rather than multiplying, such as 11 for ___ : 12 = 2 : 3.
        case added
    }

    /// The two numbers the question shows on the left: "8 : 12" in "Simplify the ratio 8 : 12" and in
    /// "___ : 12 = 2 : 3", which hides the first.
    private var scaled: (first: Int, second: Int) {
        (first * multiplier, second * multiplier)
    }

    /// The number shared out: 35 in "Divide 35 in the ratio 3 : 4".
    private var total: Int {
        (first + second) * multiplier
    }

    /// The highest common factor of the two numbers to simplify, worked out here by Euclid's method rather than taken
    /// from how the answer is checked.
    private var highestCommonFactor: Int {
        var (larger, smaller) = (max(scaled.first, scaled.second), min(scaled.first, scaled.second))
        while smaller != 0 {
            (larger, smaller) = (smaller, larger % smaller)
        }
        return larger
    }

    /// The answer as two numbers, for a question answered with a ratio.
    private var ratioAnswer: (first: Int, second: Int)? {
        switch kind {
        case .simplify:
            let factor = highestCommonFactor
            return (scaled.first / factor, scaled.second / factor)
        case .share:
            return (first * multiplier, second * multiplier)
        case .missingFirst, .missingSecond:
            return nil
        }
    }

    /// "2 : 3", and "2 to 3", which VoiceOver doesn't read as a time.
    private static func ratio(_ first: Int, _ second: Int) -> SpokenText {
        SpokenText("\(first) : \(second)", spoken: SpokenMaths.ratio("\(first)", "\(second)"))
    }

    /// The mistake `response` shows, if any, checked after the right answer is ruled out. Reversed answers are only
    /// named when the two numbers differ, so 1 : 1 is never "the wrong way round".
    func mistake(in response: Response) -> Mistake? {
        if let answer = ratioAnswer {
            let firstBlank = TypedAnswer.isBlank(response.first)
            if firstBlank != TypedAnswer.isBlank(response.second) {
                return .oneBoxEmpty
            }
            guard let typedFirst = TypedAnswer.wholeNumber(response.first),
                  let typedSecond = TypedAnswer.wholeNumber(response.second),
                  (typedFirst, typedSecond) != answer else { return nil }
            if answer.first != answer.second, (typedFirst, typedSecond) == (answer.second, answer.first) {
                return .reversed
            }
            if kind == .simplify {
                if (typedFirst, typedSecond) == scaled {
                    return .sameAsQuestion
                }
                // Equal to the question's ratio, and smaller: divided, but not by the highest common factor.
                if typedFirst > 0, typedSecond > 0, typedFirst < scaled.first,
                   typedFirst * scaled.second == typedSecond * scaled.first {
                    return .notSimplest
                }
            } else if (typedFirst, typedSecond) == (first, second) {
                return .gaveRatio
            }
            return nil
        }

        guard let typed = TypedAnswer.wholeNumber(response.missing) else { return nil }
        switch kind {
        case .missingFirst:
            let answer = scaled.first
            return typed != answer && typed == first + (scaled.second - second) ? .added : nil
        default:
            let answer = scaled.second
            return typed != answer && typed == second + (scaled.first - first) ? .added : nil
        }
    }

    func hint(after response: Response) -> SpokenText {
        let found = mistake(in: response)
        let reversed = SpokenText("The numbers are the wrong way round. Keep them in the same order as the question.")
        switch kind {
        case .simplify:
            let strategy = "Find the biggest number that divides into both \(scaled.first) and \(scaled.second)."
            switch found {
            case .reversed:
                return reversed
            case .sameAsQuestion:
                return SpokenText("That is the ratio from the question. \(strategy)")
            case .notSimplest:
                let typed = Self.ratio(TypedAnswer.wholeNumber(response.first) ?? 0,
                                       TypedAnswer.wholeNumber(response.second) ?? 0)
                let question = Self.ratio(scaled.first, scaled.second)
                let rest = ", but it can be simplified more. Look for a bigger number that divides both."
                return SpokenText("\(typed.text) is equal to \(question.text)\(rest)",
                                  spoken: "\(typed.spoken) is equal to \(question.spoken)\(rest)")
            case .oneBoxEmpty:
                return SpokenText("Fill in both parts of the ratio. \(strategy)")
            default:
                return SpokenText(strategy)
            }
        case .share:
            let strategy = "Add the numbers in the ratio to find how many equal parts there are."
            switch found {
            case .reversed:
                return reversed
            case .gaveRatio:
                return SpokenText("That is the ratio. Work out how much one part is worth.")
            case .oneBoxEmpty:
                return SpokenText("Fill in both parts of the ratio. \(strategy)")
            default:
                return SpokenText(strategy)
            }
        case .missingFirst:
            let question = "What do you multiply \(second) by to get \(scaled.second)?"
            return SpokenText(found == .added
                ? "Ratios grow by multiplying, not adding. \(question)"
                : "\(question) Do the same to \(first).")
        case .missingSecond:
            let question = "What do you multiply \(first) by to get \(scaled.first)?"
            return SpokenText(found == .added
                ? "Ratios grow by multiplying, not adding. \(question)"
                : "\(question) Do the same to \(second).")
        }
    }

    var workedSolution: WorkedSolution {
        switch kind {
        case .simplify:
            let factor = highestCommonFactor
            let (answerFirst, answerSecond) = (scaled.first / factor, scaled.second / factor)
            let answer = Self.ratio(answerFirst, answerSecond)
            return WorkedSolution(steps: [
                SpokenText("The highest common factor of \(scaled.first) and \(scaled.second) is \(factor)."),
                SpokenText("\(scaled.first) ÷ \(factor) = \(answerFirst) and \(scaled.second) ÷ \(factor) = \(answerSecond).",
                           spoken: "\(scaled.first) divided by \(factor) equals \(answerFirst) and "
                               + "\(scaled.second) divided by \(factor) equals \(answerSecond).")
            ], answer: ExplanationWording.answer(answer.text, spoken: answer.spoken))
        case .share:
            let parts = first + second
            let onePart = total / parts
            let (shareFirst, shareSecond) = (first * onePart, second * onePart)
            let answer = Self.ratio(shareFirst, shareSecond)
            return WorkedSolution(steps: [
                SpokenText("\(first) + \(second) = \(parts) parts.", spoken: "\(first) plus \(second) equals \(parts) parts."),
                SpokenText("\(total) ÷ \(parts) = \(onePart), so one part is \(onePart).",
                           spoken: "\(total) divided by \(parts) equals \(onePart), so one part is \(onePart)."),
                SpokenText("\(first) × \(onePart) = \(shareFirst) and \(second) × \(onePart) = \(shareSecond).",
                           spoken: "\(first) times \(onePart) equals \(shareFirst) and "
                               + "\(second) times \(onePart) equals \(shareSecond).")
            ], answer: ExplanationWording.answer(answer.text, spoken: answer.spoken))
        case .missingFirst:
            let factor = scaled.second / second
            let answer = first * factor
            return WorkedSolution(steps: [
                SpokenText("\(second) × \(factor) = \(scaled.second), so the ratio was multiplied by \(factor).",
                           spoken: "\(second) times \(factor) equals \(scaled.second), so the ratio was multiplied by \(factor)."),
                SpokenText("\(first) × \(factor) = \(answer).", spoken: "\(first) times \(factor) equals \(answer).")
            ], answer: ExplanationWording.answer(String(answer)))
        case .missingSecond:
            let factor = scaled.first / first
            let answer = second * factor
            return WorkedSolution(steps: [
                SpokenText("\(first) × \(factor) = \(scaled.first), so the ratio was multiplied by \(factor).",
                           spoken: "\(first) times \(factor) equals \(scaled.first), so the ratio was multiplied by \(factor)."),
                SpokenText("\(second) × \(factor) = \(answer).", spoken: "\(second) times \(factor) equals \(answer).")
            ], answer: ExplanationWording.answer(String(answer)))
        }
    }

    var correctLine: SpokenText {
        let question = Self.ratio(scaled.first, scaled.second)
        switch kind {
        case .simplify:
            let factor = highestCommonFactor
            let answer = Self.ratio(scaled.first / factor, scaled.second / factor)
            return SpokenText("\(question.text) = \(answer.text)", spoken: "\(question.spoken) equals \(answer.spoken)")
        case .share:
            let terms = Self.ratio(first, second)
            let shares = Self.ratio(first * multiplier, second * multiplier)
            return SpokenText("\(total) shared in the ratio \(terms.text) is \(shares.text)",
                              spoken: "\(total) shared in the ratio \(terms.spoken) is \(shares.spoken)")
        case .missingFirst, .missingSecond:
            let terms = Self.ratio(first, second)
            return SpokenText("\(question.text) = \(terms.text)", spoken: "\(question.spoken) equals \(terms.spoken)")
        }
    }
}
