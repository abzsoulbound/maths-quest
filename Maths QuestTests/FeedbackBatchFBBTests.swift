//
//  FeedbackBatchFBBTests.swift
//  Maths QuestTests
//
//  User feedback, batch FB-B. Children reported answers marked wrong that were right, or that were only written in
//  a form the box doesn't take. This batch:
//  - Accepts the right answers: "a right angle" and "an obtuse angle" in Geometry, "a square" in Shapes, "Glass A" in
//    Volume and "Category B" in Statistics.
//  - Asks again, the way a blank answer is asked for, without scoring, counting towards Skip or playing a sound, for
//    answers in the wrong form: one Time or Fractions box left empty, "1/2" or "2:3" typed into one box, "24cm" where
//    the unit has a wheel or is already written, and "diamond" for the square drawn on its corner.
//  None of the asked-again forms can be marked right, and every right answer is still right.
//
//  Batch FB-D later asked for one Ratio box left empty too, and added a hint about the turned square. Those tests
//  are in FeedbackBatchFBDTests.swift; the ones here that they changed say so.
//

import Foundation
import Testing
@testable import Maths_Quest

// MARK: - The shared rules

struct FBBAnswerFormatTests {
    @Test func oneBoxEmpty() {
        for (first, second) in [("3", ""), ("", "30"), (" 3 ", " "), ("\n", "0"), ("abc", "")] {
            #expect(AnswerFormat.isOneBoxEmpty(first, second), "\"\(first)\" \"\(second)\"")
        }
        for (first, second) in [("", ""), (" ", "\n"), ("3", "30"), ("0", "0"), ("abc", "x")] {
            #expect(!AnswerFormat.isOneBoxEmpty(first, second), "\"\(first)\" \"\(second)\"")
        }
    }

    @Test func twoNumbersInOneBox() {
        for box in ["1/2", " 1 / 2 ", "2:3", "2 : 3", "12/24", "0/5", "10:1"] {
            #expect(AnswerFormat.hasTwoNumbersInOneBox(box), "\"\(box)\"")
            #expect(AnswerFormat.hasTwoNumbersInOneBox("", box), "\"\(box)\" second")
            #expect(AnswerFormat.hasTwoNumbersInOneBox(box, "2"), "\"\(box)\" first")
        }
        for box in ["", " ", "1", "12", "1/", "/2", ":3", "1/2/3", "1:2:3", "a/b", "1.5/2", "½", "1 2", "1-2", "1//2",
                    "-1/2", "1/2cm"] {
            #expect(!AnswerFormat.hasTwoNumbersInOneBox(box), "\"\(box)\"")
        }
        #expect(!AnswerFormat.hasTwoNumbersInOneBox("1", "2"))
        #expect(!AnswerFormat.hasTwoNumbersInOneBox())
    }

    @Test func aNumberWithAUnit() {
        let accepted = ["24cm", "24 cm", " 24cm ", "24CM", "24 Cm.", "28 cm²", "28cm2", "28 cm^2", "28 sq cm", "28 sq. cm",
                        "28 square cm", "28 cm squared", "125 cm³", "125cm3", "125 cubic cm", "125 cm cubed", "3 kg",
                        "500g", "2 metres", "2 meters", "1 metre", "7 millimetres", "4 km", "2 l", "250 ml", "5 litres",
                        "6 grams", "3 kilograms", "1.5 m", "1,000 ml", "12 centimeters"]
        for answer in accepted {
            #expect(AnswerFormat.isNumberWithUnit(answer), "\"\(answer)\"")
        }
        let rejected = ["", " ", "24", "24.", "cm", "cm24", "24 inches", "24 ft", "24 cmx", "24 c m", "twenty cm",
                        "24 cm cm", "24cm 5", "-24cm", "24 cm²²", "24 %", "24 seconds", "24mins", "24 hours", "A",
                        "glass A", "1/2", "24 acute"]
        for answer in rejected {
            #expect(!AnswerFormat.isNumberWithUnit(answer), "\"\(answer)\"")
        }
    }

    @Test func anArticleIsLeftOutOnlyWhenSomethingFollowsIt() {
        #expect(AnswerFormat.withoutArticle(["a", "right", "angle"]) == ["right", "angle"])
        #expect(AnswerFormat.withoutArticle(["an", "obtuse"]) == ["obtuse"])
        #expect(AnswerFormat.withoutArticle(["a"]) == ["a"])
        #expect(AnswerFormat.withoutArticle(["an"]) == ["an"])
        #expect(AnswerFormat.withoutArticle([]) == [])
        #expect(AnswerFormat.withoutArticle(["right"]) == ["right"])
        #expect(AnswerFormat.withoutArticle(["the", "right"]) == ["the", "right"])
        // Only one article goes.
        #expect(AnswerFormat.withoutArticle(["a", "a", "right"]) == ["a", "right"])
    }

    @Test func aLetterAfterAWord() {
        #expect(AnswerFormat.letter(in: "Glass A", after: "glass") == "A")
        #expect(AnswerFormat.letter(in: " glass b ", after: "glass") == "B")
        #expect(AnswerFormat.letter(in: "GLASSB", after: "glass") == "B")
        #expect(AnswerFormat.letter(in: "B", after: "glass") == "B")
        #expect(AnswerFormat.letter(in: "glass", after: "glass") == "")
        #expect(AnswerFormat.letter(in: "glass C", after: "glass") == "C")
        #expect(AnswerFormat.letter(in: "glass B.", after: "glass") == "B.")
        #expect(AnswerFormat.letter(in: "glasses B", after: "glass") == "ES B")
        #expect(AnswerFormat.letter(in: "the glass B", after: "glass") == "THE GLASS B")
    }

    /// The new messages are short and can be read aloud as they are.
    @Test func theMessages() {
        let messages = [AnswerFormat.fillInBothBoxes, AnswerFormat.oneNumberPerBox, AnswerFormat.numberThenUnit,
                        AnswerFormat.justTheNumber, AnswerFormat.turnedSquare]
        #expect(Set(messages).count == messages.count)
        for message in messages {
            #expect(message.hasSuffix("."))
            #expect(message.split(separator: " ").count <= 8, "\(message)")
            #expect(!message.contains("Incorrect") && !message.contains("Correct"))
        }
    }
}

// MARK: - Geometry: "a right angle", and "24cm"

struct FBBGeometryTests {
    typealias Question = Year4GeometryQuestion

    static let angles: [Question] = Question.angles.map {
        Question(question: 3, shapeType: 4, sides: [5, 5, 5, 5], angleMeasure: $0, unitType: "cm")
    }

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

    @Test func anArticleIsAcceptedForEveryAngle() {
        for question in Self.angles {
            let type = question.angleType
            let article = type == "right" ? "a" : "an"
            for answer in ["\(article) \(type) angle", "\(article) \(type)", "\(article.capitalized) \(type) angle.",
                           " \(article)  \(type)  angle ", "\(article) \(type)-angled", "a \(type) angle"] {
                #expect(question.evaluate(answer: answer, unit: "") == .correct, "\(question.angleMeasure)°: \(answer)")
            }
            // As before.
            for answer in [type, "\(type) angle", "\(type.capitalized)."] {
                #expect(question.evaluate(answer: answer, unit: "") == .correct, "\(question.angleMeasure)°: \(answer)")
            }
        }
    }

    @Test func aWrongAngleIsStillWrongWithAnArticle() {
        for question in Self.angles {
            for type in ["acute", "right", "obtuse"] where type != question.angleType {
                for answer in ["a \(type) angle", "an \(type)", "A \(type)."] {
                    #expect(question.evaluate(answer: answer, unit: "") == .incorrect, "\(question.angleMeasure)°: \(answer)")
                }
            }
            let type = question.angleType
            for answer in ["a", "an", "a angle", "an angle", "the \(type) angle", "a a \(type)", "a \(type) angle angle",
                           "a straight angle", "a reflex angle", "a 90", "a \(type) triangle", "\(type) a"] {
                #expect(question.evaluate(answer: answer, unit: "") == .incorrect, "\(question.angleMeasure)°: \(answer)")
            }
        }
    }

    /// The hint for a wrong angle is the same as before, whatever was typed.
    @Test func theAngleHintIsUnchanged() {
        let angleHint = SpokenText("Compare the angle with a square corner (a right angle).")
        for question in Self.angles {
            for type in ["acute", "right", "obtuse"] where type != question.angleType {
                let response = (answer: "a \(type) angle", unit: "")
                #expect(question.hint(after: response) == angleHint, "\(question.angleMeasure)°")
            }
        }
    }

    @Test func aUnitTypedInIsAskedForAgain() {
        for question in Self.rectangles {
            let number = question.question == 1 ? question.perimeter : question.area ?? 0
            let unit = question.correctUnit ?? ""
            let typed = ["\(number)\(question.unitType)", "\(number) \(question.unitType)", "\(number) \(unit)",
                         "\(number)\(question.unitType)2", "\(number) sq \(question.unitType)", "\(number + 1)cm"]
            for answer in typed {
                #expect(question.hasUnitTypedIn(answer: answer), "\(question.figureDescription) \(answer)")
                // Still never right, whatever the wheel says.
                #expect(question.evaluate(answer: answer, unit: unit) == .incorrect)
                #expect(question.evaluate(answer: answer, unit: "") == .incorrect)
            }
            // The number alone is marked as before.
            #expect(!question.hasUnitTypedIn(answer: "\(number)"))
            #expect(question.evaluate(answer: "\(number)", unit: unit) == .correct)
            for answer in ["", " ", "abc", "cm", "\(number + 1)", "+\(number)", "\(number).5"] {
                #expect(!question.hasUnitTypedIn(answer: answer), "\(answer)")
            }
        }
    }

    @Test func anglesAreNotAskedAboutUnits() {
        for question in Self.angles {
            for answer in ["90cm", "45 cm", "a right angle", "right"] {
                #expect(!question.hasUnitTypedIn(answer: answer))
            }
        }
    }

    @Test func theViewAsksAgainBeforeMarking() throws {
        let check = try FBBSource.function("private func checkAnswer()", inView: "Year4GeometryView")
        try FBBSource.checkAsksAgain(in: check, guardText: "guard !current.hasUnitTypedIn(answer: answerString)",
                                     message: "AnswerFormat.numberThenUnit", marking: "current.evaluate(answer:")
    }
}

// MARK: - Measurement: "24cm"

struct FBBMeasurementTests {
    /// Every question: each conversion, and each ruler length.
    static let questions: [Year3MeasurementQuestion] = {
        var questions: [Year3MeasurementQuestion] = []
        for group in Year3MeasurementQuestion.unitGroups.indices {
            let count = Year3MeasurementQuestion.unitGroups[group].count
            for from in 0..<count - 1 {
                for to in from + 1..<count {
                    for amount in Year3MeasurementQuestion.amounts {
                        questions.append(Year3MeasurementQuestion(kind: .convert, group: group, from: from, to: to,
                                                                  amount: amount, objectLength: 1))
                    }
                }
            }
        }
        for length in Year3MeasurementQuestion.objectLengths {
            questions.append(Year3MeasurementQuestion(kind: .measure, group: 0, from: 1, to: 1, amount: 1,
                                                      objectLength: length))
        }
        return questions
    }()

    /// "24cm" was already asked for again, as "Please enter a valid number!". Only the message changes.
    @Test func aNumberWithAUnitIsNotANumberAsBefore() {
        #expect(Self.questions.count == 5 * 10 + 10)
        for question in Self.questions {
            let number = question.kind == .convert ? question.convertedAmount : question.objectLength
            let unit = question.kind == .convert ? question.toUnit : "cm"
            for answer in ["\(number)\(unit)", "\(number) \(unit)", "\(number)\(unit.uppercased())"] {
                #expect(AnswerFormat.isNumberWithUnit(answer), "\(answer)")
                #expect(question.evaluate(answer: answer, unit: unit) == .notANumber, "\(question.text) \(answer)")
            }
            #expect(question.evaluate(answer: "\(number)", unit: unit) == .correct)
        }
    }

    @Test func theViewOnlyChangesTheMessage() throws {
        let check = try FBBSource.function("private func checkAnswer()", inView: "Year3MeasurementView")
        let notANumber = try FBBSource.position(of: "case .notANumber:", in: check)
        let unitCheck = try FBBSource.position(of: "AnswerFormat.isNumberWithUnit(answerString)", in: check)
        let usual = try FBBSource.position(of: "responseMessage = \"Please enter a valid number!\"", in: check)
        let next = try FBBSource.position(of: "case ", in: check, after: notANumber + 5)
        #expect(notANumber < unitCheck && unitCheck < usual && usual < next)
        let branch = FBBSource.slice(check, from: notANumber, to: next)
        #expect(branch.contains("AnswerFormat.numberThenUnit") && branch.contains("AnswerFormat.justTheNumber"))
        #expect(!branch.contains("recordWrongAttempt") && !branch.contains("points") && !branch.contains("playSound"))
    }
}

// MARK: - Time: one box left empty

struct FBBTimeTests {
    /// Start times and durations across the day, and every hour and five minutes on the clock.
    static let twoBoxQuestions: [Year3TimeQuestion] = {
        var questions: [Year3TimeQuestion] = []
        for startHour in stride(from: 0, through: 23, by: 1) {
            for startMinute in [0, 5, 30, 45, 55] {
                for hours in Year3TimeQuestion.durationHours {
                    for minutes in [0, 15, 50] {
                        questions.append(Year3TimeQuestion(kind: .timeAfter(hours: hours, minutes: minutes,
                                                                            startHour: startHour, startMinute: startMinute)))
                    }
                }
            }
        }
        for hour in 0...23 {
            for minute in stride(from: 0, through: 55, by: 5) {
                questions.append(Year3TimeQuestion(kind: .readClock(hour: hour, minute: minute)))
            }
        }
        return questions
    }()

    @Test func oneEmptyBoxIsAskedForAgain() {
        for question in Self.twoBoxQuestions {
            let answer = question.answer
            for (hours, minutes) in [("\(answer.hours)", ""), ("", "\(answer.minutes)"), ("\(answer.hours)", " "),
                                     ("", "00"), ("3", ""), ("", "30")] {
                #expect(question.needsBothBoxes(hours: hours, minutes: minutes), "\(question.text) \(hours):\(minutes)")
                // Never right, as before.
                #expect(question.evaluate(hours: hours, minutes: minutes) == .incorrect)
            }
        }
    }

    @Test func bothBoxesAreMarkedAsBefore() {
        for question in Self.twoBoxQuestions {
            let answer = question.answer
            let right = (hours: "\(answer.hours)", minutes: String(format: "%02d", answer.minutes))
            #expect(!question.needsBothBoxes(hours: right.hours, minutes: right.minutes))
            #expect(question.evaluate(hours: right.hours, minutes: right.minutes) == .correct, "\(question.text)")
            #expect(!question.needsBothBoxes(hours: "", minutes: ""))
            #expect(question.evaluate(hours: "", minutes: "") == .unanswered)
            #expect(!question.needsBothBoxes(hours: "99", minutes: "99"))
        }
    }

    /// Changing minutes into hours and minutes still takes "2" and nothing as 2 hours exactly, and the other kinds
    /// have one box or none.
    @Test func otherKindsAreNotAffected() {
        var others: [Year3TimeQuestion] = []
        for minutes in Year3TimeQuestion.minutesToConvert {
            others.append(Year3TimeQuestion(kind: .toHoursAndMinutes(minutes: minutes)))
        }
        for hours in Year3TimeQuestion.hoursToConvert {
            others.append(Year3TimeQuestion(kind: .toMinutes(hours: hours, minutes: 15)))
        }
        others.append(Year3TimeQuestion(kind: .setClock(hour: 15, minute: 30)))
        for question in others {
            for (hours, minutes) in [("2", ""), ("", "30"), ("", ""), ("2", "30")] {
                #expect(!question.needsBothBoxes(hours: hours, minutes: minutes))
            }
        }
        let twoHours = Year3TimeQuestion(kind: .toHoursAndMinutes(minutes: 120))
        #expect(twoHours.evaluate(hours: "2", minutes: "") == .correct)
    }

    @Test func theViewAsksAgainBeforeMarking() throws {
        let check = try FBBSource.function("private func checkAnswer()", inView: "Year3TimeView")
        try FBBSource.checkAsksAgain(in: check,
                                     guardText: "guard !current.needsBothBoxes(hours: hoursanswer, minutes: minutesanswer)",
                                     message: "AnswerFormat.fillInBothBoxes", marking: "current.evaluate(hours:")
    }
}

// MARK: - Fractions, Probability and Ratio: "1/2" in one box

struct FBBTwoBoxTests {
    @Test func fractionsAskBeforeMarking() throws {
        let check = try FBBSource.function("private func checkAnswer()", inView: "Year3FractionsView")
        let blank = try FBBSource.position(of: "guard !isBlank", in: check)
        let twoNumbers = try FBBSource.position(of: "AnswerFormat.hasTwoNumbersInOneBox(numeratorString, denominatorString)",
                                                in: check)
        let oneEmpty = try FBBSource.position(of: "AnswerFormat.isOneBoxEmpty(numeratorString, denominatorString)", in: check)
        let marking = try FBBSource.position(of: "progress.recordSubmission(", in: check)
        #expect(blank < twoNumbers && twoNumbers < oneEmpty && oneEmpty < marking)
        let guards = FBBSource.slice(check, from: twoNumbers, to: marking)
        #expect(guards.contains("AnswerFormat.oneNumberPerBox") && guards.contains("AnswerFormat.fillInBothBoxes"))
        #expect(guards.components(separatedBy: "return").count - 1 == 2)
        #expect(!guards.contains("recordWrongAttempt") && !guards.contains("points") && !guards.contains("playSound"))
        // Only the simplifying question has two boxes.
        #expect(check.contains("if question == 1 {\n            if AnswerFormat.hasTwoNumbersInOneBox"))
    }

    /// Every simplified fraction has two whole numbers, so neither asked-again form was ever right.
    @Test func fractionsAnswersHaveTwoBoxes() throws {
        let view = try FBBSource.view("Year3FractionsView")
        for answer in ["1/2", "1/3", "2/3"] {
            #expect(view.contains("\"\(answer)\""))
            let parts = answer.split(separator: "/").map(String.init)
            #expect(!AnswerFormat.hasTwoNumbersInOneBox(parts[0], parts[1]))
            #expect(!AnswerFormat.isOneBoxEmpty(parts[0], parts[1]))
        }
    }

    static let probabilities: [Year6ProbabilityQuestion] = [
        .die(faces: 6, target: 2), .die(faces: 4, target: 4), .spinner(sections: 8, blue: 3), .coin(flips: 1),
        .marbles(total: 10, red: 5), .cards(total: 20, aces: 4)
    ]

    /// "1/2" in one box, or one box left empty, was already asked for again. Only the message changes.
    @Test func probabilityFormsAreInvalidAsBefore() {
        for question in Self.probabilities {
            let p = question.probability
            for (top, bottom) in [("\(p.numerator)/\(p.denominator)", ""), ("", "\(p.numerator)/\(p.denominator)"),
                                  ("\(p.numerator)", ""), ("", "\(p.denominator)"),
                                  ("\(p.numerator)/\(p.denominator)", "\(p.denominator)")] {
                #expect(question.evaluate(numerator: top, denominator: bottom) == .invalidInput, "\(top) \(bottom)")
            }
            #expect(question.evaluate(numerator: "\(p.numerator)", denominator: "\(p.denominator)") == .correct)
        }
    }

    @Test func probabilityOnlyChangesTheMessage() throws {
        let check = try FBBSource.function("private func checkAnswer()", inView: "Year6ProbabilityView")
        let invalid = try FBBSource.position(of: "case .invalidInput:", in: check)
        let next = try FBBSource.position(of: "case .correct:", in: check)
        let branch = FBBSource.slice(check, from: invalid, to: next)
        #expect(branch.contains("AnswerFormat.hasTwoNumbersInOneBox(numerator, denominator)"))
        #expect(branch.contains("AnswerFormat.isOneBoxEmpty(numerator, denominator)"))
        #expect(branch.contains("\"Please enter valid numbers.\""))
        #expect(!branch.contains("recordWrongAttempt") && !branch.contains("points") && !branch.contains("playSound"))
    }

    static let ratios: [Year6RatioQuestion] = [Year6RatioQuestion.Kind.simplify, .share, .missingFirst, .missingSecond]
        .flatMap { kind in
            Year6RatioQuestion.ratioTerms.flatMap { first in
                Year6RatioQuestion.multipliers.map { multiplier in
                    Year6RatioQuestion(kind: kind, first: first, second: first % 3 + 1, multiplier: multiplier)
                }
            }
        }

    @Test func ratioTwoNumbersInOneBoxIsAskedForAgain() {
        for question in Self.ratios {
            guard let ratio = question.correctRatio else {
                #expect(!question.hasTwoNumbersInOneBox(first: "2:3", second: "2/3"))
                continue
            }
            for (first, second) in [("\(ratio.first):\(ratio.second)", ""), ("", "\(ratio.first):\(ratio.second)"),
                                    ("\(ratio.first)/\(ratio.second)", ""), ("\(ratio.first) : \(ratio.second)", "\(ratio.second)")] {
                #expect(question.hasTwoNumbersInOneBox(first: first, second: second), "\(question.text) \(first) \(second)")
                #expect(question.evaluate(first: first, second: second, missing: "") != .correct)
            }
            #expect(!question.hasTwoNumbersInOneBox(first: "\(ratio.first)", second: "\(ratio.second)"))
            #expect(question.evaluate(first: "\(ratio.first)", second: "\(ratio.second)", missing: "") == .correct)
            #expect(!question.hasTwoNumbersInOneBox(first: "\(ratio.first)", second: ""))
        }
    }

    /// One ratio box left empty is still marked incorrect, with the same 9C hint, if it is marked. Since batch FB-D
    /// the screen asks for both boxes before marking, so it isn't counted and the hint doesn't show
    /// (`FBDRatioTests`).
    @Test func ratioOneBoxEmptyIsMarkedAsBefore() {
        for question in Self.ratios {
            guard let ratio = question.correctRatio else { continue }
            let response = (first: "\(ratio.first)", second: "", missing: "")
            #expect(question.evaluate(first: response.first, second: response.second, missing: "") == .incorrect)
            #expect(question.mistake(in: response) == .oneBoxEmpty)
            #expect(question.hint(after: response).text.hasPrefix("Fill in both parts of the ratio."))
            #expect(question.hasOneBoxEmpty(first: response.first, second: response.second))
        }
    }

    @Test func ratioAsksBeforeMarking() throws {
        let check = try FBBSource.function("private func checkAnswer()", inView: "Year6RatiosView")
        try FBBSource.checkAsksAgain(in: check,
                                     guardText: "guard !current.hasTwoNumbersInOneBox(first: answerRatio1, second: answerRatio2)",
                                     message: "AnswerFormat.oneNumberPerBox", marking: "current.evaluate(first:")
    }
}

// MARK: - Volume and Statistics: "Glass A", "Category B" and "125cm³"

struct FBBLetterAnswerTests {
    static func glasses(_ a: Int, _ b: Int) -> Year5VolumeQuestion {
        Year5VolumeQuestion(kind: .comparison, length: 0, width: 0, height: 0, glassAMillilitres: a, glassBMillilitres: b)
    }

    @Test func theGlassCanBeNamed() {
        let bHasMore = Self.glasses(1500, 2350)
        let aHasMore = Self.glasses(2400, 2350)
        for answer in ["Glass B", "glass b", "GLASS B", " Glass B ", "glassB", "Glass  B", "B"] {
            #expect(bHasMore.isCorrect(answer: answer), "\(answer)")
            #expect(!aHasMore.isCorrect(answer: answer), "\(answer)")
        }
        for answer in ["Glass A", "glass a", "glassA", "A"] {
            #expect(aHasMore.isCorrect(answer: answer), "\(answer)")
            #expect(!bHasMore.isCorrect(answer: answer), "\(answer)")
        }
    }

    @Test func otherGlassAnswersAreStillWrong() {
        for question in [Self.glasses(1500, 2350), Self.glasses(2400, 2350)] {
            for answer in ["glass", "glass C", "glass A or B", "glass AB", "glass B.", "glasses B", "the glass B",
                           "glass 2350", "Glass Β", "cup B", "B glass", "glass glass B", ""] {
                #expect(!question.isCorrect(answer: answer), "\(answer)")
            }
        }
        // Equal glasses still have no right answer.
        #expect(!Self.glasses(2000, 2000).isCorrect(answer: "Glass A"))
        #expect(!Self.glasses(2000, 2000).isCorrect(answer: "Glass B"))
    }

    @Test func aUnitTypedInForASolidIsAskedForAgain() {
        for question in FBAVolumeCommaTests.solids {
            let volume = question.volume
            for answer in ["\(volume)cm³", "\(volume) cm3", "\(volume) cubic cm", "\(volume) cm cubed", "\(volume)CM³"] {
                #expect(question.needsJustTheNumber(answer: answer), "\(question.figureDescription) \(answer)")
                #expect(!question.isCorrect(answer: answer))
            }
            #expect(!question.needsJustTheNumber(answer: "\(volume)"))
            #expect(question.isCorrect(answer: "\(volume)"))
            #expect(!question.needsJustTheNumber(answer: "1,000"))
        }
        #expect(!Self.glasses(1500, 2350).needsJustTheNumber(answer: "2350 ml"))
    }

    @Test func theVolumeViewAsksAgainBeforeMarking() throws {
        let check = try FBBSource.function("private func checkAnswer()", inView: "Year5VolumeView")
        let comma = try FBBSource.position(of: "guard !current.needsWritingWithoutAComma(answer: answerString)", in: check)
        let unit = try FBBSource.position(of: "guard !current.needsJustTheNumber(answer: answerString)", in: check)
        #expect(comma < unit)
        try FBBSource.checkAsksAgain(in: check, guardText: "guard !current.needsJustTheNumber(answer: answerString)",
                                     message: "AnswerFormat.justTheNumber", marking: "progress.recordSubmission(")
    }

    static func chart(_ bars: [String: Int]) -> Year5StatisticsQuestion {
        Year5StatisticsQuestion(kind: .highestBar, numbers: [], bars: bars)
    }

    @Test func theCategoryCanBeNamed() {
        for leader in Year5StatisticsQuestion.categories {
            var bars: [String: Int] = [:]
            for category in Year5StatisticsQuestion.categories { bars[category] = category == leader ? 9 : 3 }
            let question = Self.chart(bars)
            #expect(question.highestCategory == leader)
            for answer in ["Category \(leader)", "category \(leader.lowercased())", "CATEGORY\(leader)", leader] {
                #expect(question.isCorrect(answer: answer), "\(answer)")
            }
            for other in Year5StatisticsQuestion.categories where other != leader {
                #expect(!question.isCorrect(answer: "Category \(other)"))
            }
            for answer in ["category", "Category E", "Category \(leader).", "categories \(leader)", "the category \(leader)",
                           "Category A or B", "bar \(leader)", "9"] {
                #expect(!question.isCorrect(answer: answer), "\(answer)")
            }
        }
    }
}

// MARK: - Shapes: "a square", and the square on its corner

struct FBBShapeTests {
    static let nameQuestions = Year2ShapeQuestion.figures.indices.map { Year2ShapeQuestion(kind: .name, figureIndex: $0) }

    @Test func anArticleIsAccepted() {
        for question in Self.nameQuestions {
            let name = question.figure.name
            for answer in ["a \(name)", "an \(name)", "A \(name.capitalized).", " a  \(name) ", name, "\(name.uppercased())!"] {
                #expect(question.evaluate(answer) == .correct, "\(name): \(answer)")
            }
        }
    }

    @Test func aWrongNameIsStillWrong() {
        for question in Self.nameQuestions {
            let name = question.figure.name
            for other in Year2ShapeQuestion.figures.map(\.name) where other != name {
                #expect(question.evaluate("a \(other)") == .incorrect, "\(name): a \(other)")
            }
            for answer in ["a", "an", "the \(name)", "a \(name)s", "a a \(name)", "\(name) a", "a shape", "diamond"] {
                #expect(question.evaluate(answer) == .incorrect, "\(name): \(answer)")
            }
        }
    }

    @Test func diamondForTheSquareIsAskedForAgain() throws {
        let square = try #require(Self.nameQuestions.first { $0.figure.name == "square" })
        for answer in ["diamond", "Diamond", "a diamond", "Rhombus.", "a rhombus", " DIAMOND "] {
            #expect(square.asksAgainAboutTheTurnedSquare(answer), "\(answer)")
            #expect(square.evaluate(answer) == .incorrect)
        }
        for answer in ["square", "a square", "", "diamonds", "kite", "rectangle"] {
            #expect(!square.asksAgainAboutTheTurnedSquare(answer), "\(answer)")
        }
        // Only the square, and only when it is to be named.
        for question in Self.nameQuestions where question.figure.name != "square" {
            #expect(!question.asksAgainAboutTheTurnedSquare("diamond"))
        }
        let squareIndex = try #require(Year2ShapeQuestion.figures.firstIndex { $0.name == "square" })
        for kind in [Year2ShapeQuestion.Kind.sides, .corners] {
            #expect(!Year2ShapeQuestion(kind: kind, figureIndex: squareIndex).asksAgainAboutTheTurnedSquare("diamond"))
        }
    }

    /// Counting sides and corners is unchanged.
    @Test func numbersAreNotAffected() {
        for (index, figure) in Year2ShapeQuestion.figures.enumerated() {
            #expect(Year2ShapeQuestion(kind: .sides, figureIndex: index).evaluate("\(figure.straightSides)") == .correct)
            #expect(Year2ShapeQuestion(kind: .corners, figureIndex: index).evaluate("\(figure.corners)") == .correct)
            #expect(Year2ShapeQuestion(kind: .sides, figureIndex: index).evaluate("a \(figure.straightSides)") == .incorrect)
        }
    }

    @Test func theViewAsksAgainBeforeMarking() throws {
        let check = try FBBSource.function("private func checkAnswer()", inView: "Year2ShapesView")
        // Batch FB-D shows what a square is with the message. `FBDShapeTests` checks that it is that hint and nothing
        // else.
        try FBBSource.checkAsksAgain(in: check, guardText: "guard !current.asksAgainAboutTheTurnedSquare(answerString)",
                                     message: "AnswerFormat.turnedSquare", marking: "current.evaluate(answerString)",
                                     allowing: ["hint ="])
    }
}

// MARK: - Generated questions

/// Whatever the generators ask, the right answer is still right and is never asked for again.
struct FBBGeneratedQuestionTests {
    @Test func rightAnswersAreNeverAskedForAgain() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<2000 {
            let geometry = Year4GeometryQuestion.random(using: &generator)
            if let unit = geometry.correctUnit {
                let number = geometry.question == 1 ? geometry.perimeter : geometry.area ?? 0
                #expect(!geometry.hasUnitTypedIn(answer: "\(number)"))
                #expect(geometry.evaluate(answer: "\(number)", unit: unit) == .correct)
            } else {
                #expect(geometry.evaluate(answer: geometry.angleType == "right" ? "a right angle" : "an \(geometry.angleType) angle",
                                          unit: "") == .correct)
            }

            let time = Year3TimeQuestion.random(using: &generator)
            let answer = time.answer
            #expect(!time.needsBothBoxes(hours: "\(answer.hours)", minutes: "\(answer.minutes)"))

            let shape = Year2ShapeQuestion.random(using: &generator)
            if shape.kind == .name {
                #expect(!shape.asksAgainAboutTheTurnedSquare(shape.figure.name))
                #expect(shape.evaluate("a \(shape.figure.name)") == .correct)
            }

            let ratio = Year6RatioQuestion.random(using: &generator)
            if let parts = ratio.correctRatio {
                #expect(!ratio.hasTwoNumbersInOneBox(first: "\(parts.first)", second: "\(parts.second)"))
            }

            let volume = Year5VolumeQuestion.random(using: &generator)
            if volume.kind == .comparison {
                if let glass = volume.glassWithMore {
                    #expect(volume.isCorrect(answer: "Glass \(glass)"))
                }
            } else {
                #expect(!volume.needsJustTheNumber(answer: "\(volume.volume)"))
            }

            let statistics = Year5StatisticsQuestion.random(using: &generator)
            if statistics.kind == .highestBar, let category = statistics.highestCategory {
                #expect(statistics.isCorrect(answer: "Category \(category)"))
            }
        }
    }
}

// MARK: - Source

private enum FBBSourceError: Error {
    case missing(String)
}

private enum FBBSource {
    static let projectFolder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static func view(_ name: String) throws -> String {
        let source = try String(contentsOf: projectFolder.appendingPathComponent("Maths Quest/ContentView.swift"),
                                encoding: .utf8)
        guard let start = source.range(of: "\nstruct \(name): View {"),
              let end = source.range(of: "\n}\n", range: start.upperBound..<source.endIndex) else {
            throw FBBSourceError.missing(name)
        }
        return String(source[start.lowerBound..<end.upperBound])
    }

    static func function(_ opening: String, inView name: String) throws -> String {
        let body = try view(name)
        guard let start = body.range(of: "    " + opening),
              let end = body.range(of: "\n    }\n", range: start.upperBound..<body.endIndex) else {
            throw FBBSourceError.missing("\(name).\(opening)")
        }
        return String(body[start.lowerBound..<end.upperBound])
    }

    static func position(of needle: String, in text: String, after offset: Int = 0) throws -> Int {
        let from = text.index(text.startIndex, offsetBy: offset)
        guard let range = text.range(of: needle, range: from..<text.endIndex) else {
            throw FBBSourceError.missing(needle)
        }
        return text.distance(from: text.startIndex, to: range.lowerBound)
    }

    static func slice(_ text: String, from start: Int, to end: Int) -> Substring {
        text[text.index(text.startIndex, offsetBy: start)..<text.index(text.startIndex, offsetBy: end)]
    }

    /// The guard comes after the check that the question is still open and before marking, shows its message and
    /// returns, and gives no points, plays no sound, sets no hint and counts nothing towards Skip. `allowing` lets
    /// a guard set what it is allowed to, such as the turned square's hint.
    static func checkAsksAgain(in check: String, guardText: String, message: String, marking: String,
                               allowing: Set<String> = [],
                               sourceLocation: SourceLocation = #_sourceLocation) throws {
        let open = try position(of: "guard !progress.isAdvancing else { return }", in: check)
        let asks = try position(of: guardText, in: check)
        let shown = try position(of: "responseMessage = " + message, in: check, after: asks)
        let marked = try position(of: marking, in: check, after: asks)
        #expect(open < asks && asks < shown && shown < marked, sourceLocation: sourceLocation)
        let body = slice(check, from: asks, to: marked)
        #expect(body.contains("showFeedback()") && body.contains("return"), sourceLocation: sourceLocation)
        for forbidden in ["points", "playSound", "recordWrongAttempt", "recordSubmission", "hint =", "totalQuestionsAnswered"]
            where !allowing.contains(forbidden) {
            #expect(!body.contains(forbidden), "\(forbidden)", sourceLocation: sourceLocation)
        }
    }
}
