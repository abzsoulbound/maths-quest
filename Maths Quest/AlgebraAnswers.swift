//
//  AlgebraAnswers.swift
//  Maths Quest
//
//  Stage 9C Batch 2: Year 6 Algebra answers that are asked for again rather than marked wrong.
//  - B2-3: the right answer written in a way algebra doesn't use: a times sign before x ("19 × x"), a number after
//    the x ("x19"), or a decimal point in a whole-number value of x ("12.0").
//  - B2-4: any other answer equal to the right one but not in its simplest form, such as "10x + 9x", "15x + 3 + 3" or
//    "x = 19 − 7". It needs simplifying further.
//  Like a blank answer, these score nothing, play no sound, don't count towards Skip and bring no hint. Only an answer
//  that isn't right reaches these checks, and only one equal to the right answer is asked for again, so a wrong
//  answer is still marked wrong.
//

import Foundation

/// A fraction in lowest terms, with a denominator above 0. Anything too big to hold gives nil rather than trapping.
struct ExactNumber: Equatable {
    let numerator: Int
    let denominator: Int

    static let zero = ExactNumber(whole: 0)

    init(whole: Int) {
        numerator = whole
        denominator = 1
    }

    init?(_ numerator: Int, over denominator: Int) {
        guard denominator != 0, numerator != .min, denominator != .min else { return nil }
        let divisor = TypedAnswer.greatestCommonDivisor(numerator, denominator)
        let sign = denominator < 0 ? -1 : 1
        self.numerator = sign * numerator / divisor
        self.denominator = sign * denominator / divisor
    }

    var negated: ExactNumber? {
        ExactNumber(-numerator, over: denominator)
    }

    func adding(_ other: ExactNumber) -> ExactNumber? {
        guard let left = Self.product(numerator, other.denominator),
              let right = Self.product(other.numerator, denominator),
              let bottom = Self.product(denominator, other.denominator) else { return nil }
        let (top, overflow) = left.addingReportingOverflow(right)
        return overflow ? nil : ExactNumber(top, over: bottom)
    }

    func multiplied(by other: ExactNumber) -> ExactNumber? {
        guard let top = Self.product(numerator, other.numerator),
              let bottom = Self.product(denominator, other.denominator) else { return nil }
        return ExactNumber(top, over: bottom)
    }

    func divided(by other: ExactNumber) -> ExactNumber? {
        guard other.numerator != 0,
              let top = Self.product(numerator, other.denominator),
              let bottom = Self.product(denominator, other.numerator) else { return nil }
        return ExactNumber(top, over: bottom)
    }

    private static func product(_ first: Int, _ second: Int) -> Int? {
        let (result, overflow) = first.multipliedReportingOverflow(by: second)
        return overflow ? nil : result
    }
}

/// The value ax + b of what was typed, worked out exactly, so "10x + 9x" is 19x and "3(5x + 2)" is 15x + 6.
///
/// It reads whole numbers and decimals, x, + and −, multiplying with ×, * or ·, or by writing two things next to each
/// other (3x, 3(5x + 2), (5x + 2)x), dividing by a number with ÷ or /, and brackets. Things written next to each other
/// are multiplied first, as in algebra, so "6 ÷ 2x" divides by 2x. Nothing else is read: not x², a number straight
/// after an x or a bracket ("x19"), dividing by x, or anything that multiplies x by x. Text it can't read has no value,
/// so it's never asked for again: it's marked as before.
struct AlgebraValue: Equatable {
    let coefficient: ExactNumber
    let constant: ExactNumber

    init(coefficient: ExactNumber, constant: ExactNumber) {
        self.coefficient = coefficient
        self.constant = constant
    }

    init?(reading text: String) {
        var reader = Reader(text)
        guard let value = reader.readAll() else { return nil }
        self = value
    }

    /// True if this is exactly the expression, such as 19x + 0 for 19x.
    func equals(_ expression: LinearExpression) -> Bool {
        coefficient == ExactNumber(whole: expression.coefficient) && constant == ExactNumber(whole: expression.constant)
    }

    fileprivate static let x = AlgebraValue(coefficient: ExactNumber(whole: 1), constant: .zero)

    fileprivate var negated: AlgebraValue? {
        guard let coefficient = coefficient.negated, let constant = constant.negated else { return nil }
        return AlgebraValue(coefficient: coefficient, constant: constant)
    }

    fileprivate func adding(_ other: AlgebraValue) -> AlgebraValue? {
        guard let coefficient = coefficient.adding(other.coefficient),
              let constant = constant.adding(other.constant) else { return nil }
        return AlgebraValue(coefficient: coefficient, constant: constant)
    }

    /// (ax + b)(cx + d), only if a or c is 0, so that there's no x × x.
    fileprivate func multiplied(by other: AlgebraValue) -> AlgebraValue? {
        guard coefficient == .zero || other.coefficient == .zero,
              let first = coefficient.multiplied(by: other.constant),
              let second = constant.multiplied(by: other.coefficient),
              let coefficient = first.adding(second),
              let constant = constant.multiplied(by: other.constant) else { return nil }
        return AlgebraValue(coefficient: coefficient, constant: constant)
    }

    /// Only by a number other than 0.
    fileprivate func divided(by other: AlgebraValue) -> AlgebraValue? {
        guard other.coefficient == .zero,
              let coefficient = coefficient.divided(by: other.constant),
              let constant = constant.divided(by: other.constant) else { return nil }
        return AlgebraValue(coefficient: coefficient, constant: constant)
    }

    /// Reads a sum of terms; a term is factors multiplied or divided; a factor is things written next to each other;
    /// each thing is a number, x or a bracket, with any signs in front.
    private struct Reader {
        private let characters: [Character]
        private var index = 0

        init(_ text: String) {
            characters = text.lowercased().filter { !$0.isWhitespace }.map { character in
                switch character {
                // Some keyboards type a minus sign or a dash instead of a hyphen.
                case "−", "–", "—": "-"
                case "×", "·": "*"
                case "÷": "/"
                default: character
                }
            }
        }

        /// The whole text as one value. Very long text isn't read, which keeps the brackets from going too deep.
        mutating func readAll() -> AlgebraValue? {
            guard !characters.isEmpty, characters.count <= 100, let value = sum(), index == characters.count else {
                return nil
            }
            return value
        }

        private var next: Character? {
            index < characters.count ? characters[index] : nil
        }

        private mutating func sum() -> AlgebraValue? {
            guard var value = term() else { return nil }
            while let sign = next, sign == "+" || sign == "-" {
                index += 1
                guard let term = term(),
                      let added = sign == "+" ? value.adding(term) : term.negated.flatMap(value.adding) else {
                    return nil
                }
                value = added
            }
            return value
        }

        private mutating func term() -> AlgebraValue? {
            guard var value = factor() else { return nil }
            while let operation = next, operation == "*" || operation == "/" {
                index += 1
                guard let factor = factor(),
                      let result = operation == "*" ? value.multiplied(by: factor) : value.divided(by: factor) else {
                    return nil
                }
                value = result
            }
            return value
        }

        /// "3x", "3(5x + 2)" and "(5x + 2)x": an x or a bracket written straight after something multiplies it.
        private mutating func factor() -> AlgebraValue? {
            guard var value = signed() else { return nil }
            while next == "x" || next == "(" {
                guard let item = item(), let product = value.multiplied(by: item) else { return nil }
                value = product
            }
            return value
        }

        private mutating func signed() -> AlgebraValue? {
            switch next {
            case "+":
                index += 1
                return signed()
            case "-":
                index += 1
                return signed()?.negated
            default:
                return item()
            }
        }

        private mutating func item() -> AlgebraValue? {
            switch next {
            case "x":
                index += 1
                return AlgebraValue.x
            case "(":
                index += 1
                guard let inside = sum(), next == ")" else { return nil }
                index += 1
                return inside
            default:
                return number()
            }
        }

        /// Digits with at most one decimal point among or after them: "12", "12.0", "12.", ".5".
        private mutating func number() -> AlgebraValue? {
            let start = index
            var seenPoint = false
            while let character = next, (character.isASCII && character.isNumber) || (character == "." && !seenPoint) {
                seenPoint = seenPoint || character == "."
                index += 1
            }
            guard let decimal = TypedAnswer.exactDecimal(String(characters[start..<index])),
                  let number = ExactNumber(decimal.numerator, over: decimal.denominator) else { return nil }
            return AlgebraValue(coefficient: .zero, constant: number)
        }
    }
}

extension Year6AlgebraQuestion {
    /// What was typed, in small letters, without spaces, and with a minus sign or dash as "-".
    static func cleaned(_ text: String) -> String {
        String(text.lowercased().filter { !$0.isWhitespace }.map { $0 == "−" || $0 == "–" ? "-" : $0 })
    }

    /// Solve: what was typed for x, without "x=" in front or "=x" after it. `text` is already `cleaned(_:)`.
    static func valueOfX(in text: String) -> String {
        var typed = text
        if typed.hasPrefix("x=") {
            typed.removeFirst(2)
        } else if typed.hasSuffix("=x") {
            typed.removeLast(2)
        }
        return typed
    }

    /// B2-3 and B2-4: the message for an answer that's asked for again, or nil if it's marked. Always nil for a right
    /// answer, a blank one, or one that isn't equal to the right answer.
    func askedAgain(_ text: String) -> AskedAgainMessage? {
        guard evaluate(text) == .incorrect else { return nil }
        return writtenDifferently(text) ?? needsSimplifying(text)
    }

    /// The x term in the examples the messages give, which is never the answer's own: 2x, or 3x when the answer is 2x.
    private var exampleCoefficient: Int {
        answer.coefficient == 2 ? 3 : 2
    }

    /// B2-3: the right answer written in a way algebra doesn't use.
    private func writtenDifferently(_ text: String) -> AskedAgainMessage? {
        let typed = Self.cleaned(text)
        let example = exampleCoefficient
        switch kind {
        case .solve:
            // "12.0" or "12." for 12, after any "x =" and a plus sign.
            var value = Self.valueOfX(in: typed)
            if value.hasPrefix("+") {
                value.removeFirst()
            }
            let parts = value.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 2, TypedAnswer.wholeNumber(String(parts[0])) == second,
                  parts[1].allSatisfy({ $0 == "0" }) else { return nil }
            return AskedAgainMessage(message: SpokenText("Write x as a whole number, without a decimal point."))
        case .simplify, .expand:
            if writesTimesSign(typed) {
                return AskedAgainMessage(message: SpokenText(
                    "In algebra, leave out the × sign. Write \(example)x, not \(example) × x.",
                    spoken: "In algebra, leave out the times sign. Write \(example)x, not \(example) times x."))
            }
            // "19.0x" or "15x + 6.0": a decimal point and only 0s after it, in a number that makes exactly the answer.
            let wholeNumbers = typed.replacingOccurrences(of: #"(?<=[0-9])\.0*(?![0-9])"#, with: "",
                                                          options: .regularExpression)
            if wholeNumbers != typed, LinearExpression(simplified: wholeNumbers) == answer {
                return AskedAgainMessage(message: SpokenText("Write each number as a whole number, without a decimal point."))
            }
            // "x19" read as "19x", only when that makes exactly the answer and there's no other number after an x.
            guard let range = typed.range(of: #"x[0-9]+"#, options: .regularExpression),
                  typed.range(of: #"x[0-9]+"#, options: .regularExpression, range: range.upperBound..<typed.endIndex) == nil,
                  LinearExpression(simplified: typed.replacingCharacters(in: range, with: typed[range].dropFirst() + "x"))
                    == answer else { return nil }
            return AskedAgainMessage(message: SpokenText("In algebra, write the number before the x, like \(example)x."))
        }
    }

    /// B2-3: "19 × x" or "15*x + 6": the right answer with a times sign between a number and x. Only a sign there can
    /// be left out, so "3 × 5x + 3 × 2" isn't read as "35x + 32".
    private func writesTimesSign(_ typed: String) -> Bool {
        let characters = Array(typed)
        let signs = characters.indices.filter { "×*·".contains(characters[$0]) }
        guard !signs.isEmpty, signs.allSatisfy({ index in
            index > 0 && index + 1 < characters.count && characters[index - 1].isNumber && characters[index + 1] == "x"
        }) else { return false }
        return LinearExpression(simplified: typed.filter { !"×*·".contains($0) }) == answer
    }

    /// B2-4: equal to the answer, but not in its simplest form. The question typed back gets its own message.
    private func needsSimplifying(_ text: String) -> AskedAgainMessage? {
        let typed = Self.cleaned(text)
        if kind == .solve {
            return solveNeedsSimplifying(typed)
        }
        guard let value = AlgebraValue(reading: typed), value.equals(answer) else { return nil }
        let equal = SpokenText("That's equal, but it needs simplifying further.")
        switch kind {
        case .solve:
            return nil
        case .simplify:
            let questionTypedBack = [expression, "\(Self.term(second)) + \(Self.term(first))"].map(Self.cleaned)
            if questionTypedBack.contains(typed) {
                return AskedAgainMessage(message: SpokenText("That's the question. It needs simplifying."),
                                         detail: SpokenText("Put the x terms together into one x term."))
            }
            return AskedAgainMessage(message: equal,
                                     detail: SpokenText("Write it as one x term, like \(exampleCoefficient)x."))
        case .expand:
            if typed == Self.cleaned(expression) {
                return AskedAgainMessage(message: SpokenText("That's the question. It needs expanding."),
                                         detail: SpokenText("Multiply each part inside the bracket by \(multiplier)."))
            }
            // 2x + 3 is never an answer: the answers' x terms are 2x only when the number outside is 2, which makes
            // their numbers even.
            return AskedAgainMessage(message: equal,
                                     detail: SpokenText("Write it as an x term plus a number, like 2x + 3.",
                                                        spoken: "Write it as an x term plus a number, like 2x plus 3."))
        }
    }

    /// B2-4 for Solve: a sum equal to the answer, such as "19 − 7" or "x = 19 − 7", or an equation that's true only
    /// when x is the answer, such as the question typed back or "2x = 24".
    private func solveNeedsSimplifying(_ typed: String) -> AskedAgainMessage? {
        let workItOut = SpokenText("Work it out, so x is a single number.")
        let equal = SpokenText("That's equal, but it needs simplifying further.")
        let sides = typed.split(separator: "=", omittingEmptySubsequences: false).map(String.init)
        guard sides.count <= 2 else { return nil }
        guard sides.count == 2 else {
            guard let value = AlgebraValue(reading: typed), value.equals(answer) else { return nil }
            return AskedAgainMessage(message: equal, detail: workItOut)
        }
        // left = right is true only for x = second when left − right is cx + d with c not 0 and c × second + d = 0.
        guard let left = AlgebraValue(reading: sides[0]), let right = AlgebraValue(reading: sides[1]),
              let difference = right.negated.flatMap(left.adding), difference.coefficient != .zero,
              difference.coefficient.multiplied(by: ExactNumber(whole: second))?.adding(difference.constant) == .zero
        else { return nil }
        let addedToX = ["x+\(first)", "\(first)+x"]
        if sides.contains("\(first + second)"), sides.contains(where: addedToX.contains) {
            return AskedAgainMessage(message: SpokenText("That's the question. Work out what x is."),
                                     detail: SpokenText("Take \(first) away from both sides, so x is on its own."))
        }
        if sides.contains("x"), left.coefficient == .zero || right.coefficient == .zero {
            return AskedAgainMessage(message: equal, detail: workItOut)
        }
        return AskedAgainMessage(message: SpokenText("That's true, but it needs simplifying further."), detail: workItOut)
    }
}
