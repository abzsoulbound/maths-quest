import Foundation

/// Answers that are written in the wrong form rather than wrong, from user feedback (batch FB-B).
///
/// Each one is asked for again with a message, the way a blank answer is: it scores nothing, it doesn't count towards
/// Skip, and it plays no sound. None of them can ever be marked right, so no wrong answer becomes right. The answers
/// that are right, such as "a right angle" or "Glass A", are accepted where they are marked, using `withoutArticle(_:)`
/// and `letter(in:after:)`.
enum AnswerFormat {
    /// Time and Fractions: one of two boxes is empty.
    static let fillInBothBoxes = "Fill in both boxes."
    /// Fractions, Ratio and Probability: "1/2" or "2:3" typed into one box, which an iPad keyboard allows.
    static let oneNumberPerBox = "Put each number in its own box."
    /// Geometry and Measurement conversions, where the unit has its own wheel: "24cm".
    static let numberThenUnit = "Type just the number, then pick the unit."
    /// Volume and Measurement's ruler, where the unit is already written next to the box: "125cm³".
    static let justTheNumber = "Type just the number."
    /// Shapes: "diamond" or "rhombus" for the square, which is drawn standing on a corner.
    static let turnedSquare = "Imagine it turned to sit on one side."

    /// Exactly one of the two boxes has something in it.
    static func isOneBoxEmpty(_ first: String, _ second: String) -> Bool {
        TypedAnswer.isBlank(first) != TypedAnswer.isBlank(second)
    }

    /// "1/2", "2:3" or "2 : 3" in any one of the boxes: two whole numbers where one was asked for.
    static func hasTwoNumbersInOneBox(_ boxes: String...) -> Bool {
        boxes.contains { $0.range(of: #"^\s*[0-9]+\s*[/:]\s*[0-9]+\s*$"#, options: .regularExpression) != nil }
    }

    /// The units the activities use, as abbreviations or words, British or American.
    private static let unit = #"(mm|cm|m|km|g|kg|ml|l|millimet(re|er)s?|centimet(re|er)s?|met(re|er)s?|kilomet(re|er)s?"#
        + #"|grams?|kilograms?|millilit(re|er)s?|lit(re|er)s?)"#

    /// A number with a unit after it: "24cm", "24 cm", "28 cm²", "28cm2", "28 sq cm", "125 cubic cm", "3 kg",
    /// "2 metres". Capitals don't matter. A number alone, or a unit alone, isn't.
    static func isNumberWithUnit(_ answer: String) -> Bool {
        let pattern = #"^\s*[0-9][0-9.,]*\s*(sq\.?\s*|square\s+|cubic\s+)?"# + unit
            + #"\s*(²|³|2|3|\^2|\^3|\s+squared|\s+cubed)?\s*\.?\s*$"#
        return answer.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// The words without a leading "a" or "an", if something follows it: "a right angle" is "right angle", but "a"
    /// alone stays "a".
    static func withoutArticle(_ words: [String]) -> [String] {
        guard words.count > 1, words[0] == "a" || words[0] == "an" else { return words }
        return Array(words.dropFirst())
    }

    /// The answer in capitals, without the word in front of it, if it starts with that word: "Glass a" is "A" after
    /// "glass", and so is "glassA". Anything else is only trimmed and put in capitals, so "glass C" is still "C"
    /// and wrong, "glass" alone is "", and "B." is still "B.".
    static func letter(in answer: String, after word: String) -> String {
        let text = answer.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let prefix = word.uppercased()
        guard text.hasPrefix(prefix) else { return text }
        return String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
