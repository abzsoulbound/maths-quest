//
//  Stage6DCurriculumTests.swift
//  Maths QuestTests
//
//  Stage 6D: question wording, boundary values and marking found in the final gameplay and
//  curriculum check. Everything here is pure logic or reads ContentView.swift, so it runs without
//  the simulator UI, StoreKit or Firebase. Random questions come from SeededGenerator, so a
//  failure can be reproduced.
//

import Foundation
import Testing
@testable import Maths_Quest

// MARK: - Wording

/// "1 are blue", "flipped 1 times" and the like, in any question text.
private let singularMistakes = try! Regex(
    #"\b1 (are|times|faces|marbles|cards|aces|hours|minutes|pennies|sections)\b"#
)

private func numbersShown(in text: String) -> [Int] {
    text.split(whereSeparator: { !($0.isASCII && $0.isNumber) }).compactMap { Int($0) }
}

struct Stage6DWordingTests {
    @Test func probabilityQuestionsUseSingularsAndSayHowTheDieIsNumbered() {
        typealias Question = Year6ProbabilityQuestion
        #expect(Question.spinner(sections: 6, blue: 1).text
                == "A spinner has 6 equal sections. 1 is blue. What is the probability of landing on blue?")
        #expect(Question.marbles(total: 9, red: 1).text
                == "A bag contains 9 marbles. 1 is red. What is the probability of drawing a red marble?")
        #expect(Question.cards(total: 7, aces: 1).text
                == "A stack of 7 cards has 1 ace. What is the probability of drawing an ace?")
        #expect(Question.coin(flips: 1).text
                == "A fair coin is flipped once. What is the probability of getting heads every time?")
        #expect(Question.coin(flips: 2).text
                == "A fair coin is flipped twice. What is the probability of getting heads every time?")
        // A 5-faced die is a real (if unusual) fair die. Saying how it's numbered, and that each number is equally
        // likely (Stage 6E), makes 1/5 the only reading.
        #expect(Question.die(faces: 5, target: 2).text
                == "A fair die has 5 faces, numbered 1 to 5. Each number is equally likely to be rolled. "
                + "What is the probability of rolling a 2?")
        #expect(Question.die(faces: 5, target: 2).evaluate(numerator: "1", denominator: "5") == .correct)
    }

    @Test func everyGeneratedProbabilityQuestionReadsCorrectly() {
        var generator = SeededGenerator(seed: 0x6D01)
        for _ in 0..<20_000 {
            let question = Year6ProbabilityQuestion.random(using: &generator)
            #expect(!question.text.contains(singularMistakes), "\(question.text)")
            if case let .die(faces, target) = question {
                #expect(question.text.contains("numbered 1 to \(faces)."))
                #expect((1...faces).contains(target))
            }
        }
    }

    @Test func penniesAreWrittenAsPence() {
        let one = Year4MoneyQuestion(kind: .convert, first: 0, second: 0, pennies: 1)
        #expect(one.text == "Convert 1p to pounds")
        #expect(one.evaluate("0.01") == .correct)
        let most = Year4MoneyQuestion(kind: .convert, first: 0, second: 0, pennies: 1000)
        #expect(most.text == "Convert 1000p to pounds")
        #expect(most.evaluate("10.00") == .correct)
        #expect(most.evaluate("10") == .correct)

        var generator = SeededGenerator(seed: 0x6D02)
        var converts = 0
        for _ in 0..<20_000 {
            let question = Year4MoneyQuestion.random(using: &generator)
            guard question.kind == .convert else { continue }
            converts += 1
            // "Convert 0p to pounds" isn't a real question.
            #expect(Year4MoneyQuestion.penceToConvert.contains(question.pennies))
            #expect(question.pennies > 0)
            #expect(question.text == "Convert \(question.pennies)p to pounds")
        }
        #expect(converts > 5_000)
    }

    /// Every activity with question text, sampled widely: no "1 are", "1 times", "1 hours" and so on.
    @Test func noGeneratedQuestionHasASingularPluralMistake() {
        var generator = SeededGenerator(seed: 0x6D03)
        var texts = [String]()
        for _ in 0..<3_000 {
            texts.append(Year2MultiplicationQuestion.random(using: &generator).text)
            texts.append(Year2DivisionQuestion.random(using: &generator).text)
            texts.append(Year2ShapeQuestion.random(using: &generator).text)
            texts.append(Year3MeasurementQuestion.random(using: &generator).text)
            texts.append(Year3TimeQuestion.random(using: &generator).text)
            texts.append(Year4DecimalsQuestion.random(using: &generator).text)
            texts.append(Year4MoneyQuestion.random(using: &generator).text)
            texts.append(Year5StatisticsQuestion.random(using: &generator).text)
            texts.append(Year5VolumeQuestion.random(using: &generator).text)
            let algebra = Year6AlgebraQuestion.random(using: &generator)
            texts.append(algebra.instruction + " " + algebra.expression)
            texts.append(Year6ProbabilityQuestion.random(using: &generator).text)
            texts.append(Year6RatioQuestion.random(using: &generator).text)
        }
        for text in texts {
            #expect(!text.contains(singularMistakes), "\(text)")
            #expect(!text.contains("pennies"), "\(text)")
            #expect(!text.contains("analog "), "\(text)")
        }
    }
}

// MARK: - Year 3 Time

struct Stage6DTimeTests {
    typealias Question = Year3TimeQuestion

    @Test func durationsAreWrittenWithoutZerosOrPluralMistakes() {
        #expect(Question.duration(hours: 1, minutes: 1) == "1 hour and 1 minute")
        #expect(Question.duration(hours: 2, minutes: 0) == "2 hours")
        #expect(Question.duration(hours: 0, minutes: 45) == "45 minutes")
        #expect(Question(kind: .toMinutes(hours: 3, minutes: 0)).text == "Convert 3 hours into minutes")
        #expect(Question(kind: .toMinutes(hours: 1, minutes: 30)).text == "Convert 1 hour and 30 minutes into minutes")
        #expect(Question(kind: .timeAfter(hours: 0, minutes: 5, startHour: 7, startMinute: 5)).text
                == "What is the time 5 minutes after 07:05?")
        #expect(Question(kind: .setClock(hour: 15, minute: 30)).text == "Show 15:30 on this analogue clock.")
        #expect(Question(kind: .timeAfter(hours: 1, minutes: 0, startHour: 9, startMinute: 0)).instructions
                == "Answer using the 24-hour clock.")
        // The layout UI test looks for this question by its first words.
        #expect(Question(kind: .readClock(hour: 3, minute: 0)).text == "What time is shown on this clock?")
    }

    @Test func hoursAndMinutesIntoMinutes() {
        let question = Question(kind: .toMinutes(hours: 2, minutes: 15))
        #expect(question.answer.minutes == 135)
        for typed in ["135", " 135 ", "0135"] {
            #expect(question.evaluate(hours: "", minutes: typed) == .correct, "\(typed)")
        }
        for typed in ["134", "2:15", "1.35", "-135", "135 minutes"] {
            #expect(question.evaluate(hours: "", minutes: typed) == .incorrect, "\(typed)")
        }
        #expect(question.evaluate(hours: "", minutes: " ") == .unanswered)
    }

    @Test func minutesIntoHoursAndMinutes() {
        let question = Question(kind: .toHoursAndMinutes(minutes: 135))
        #expect(question.evaluate(hours: "2", minutes: "15") == .correct)
        #expect(question.evaluate(hours: "02", minutes: "15") == .correct)
        #expect(question.evaluate(hours: "1", minutes: "75") == .incorrect)
        #expect(question.evaluate(hours: "2", minutes: "") == .incorrect)
        #expect(question.evaluate(hours: "", minutes: "135") == .incorrect)
        #expect(question.evaluate(hours: "", minutes: "") == .unanswered)

        // A whole number of hours: the minutes can be 0 or left empty.
        let exact = Question(kind: .toHoursAndMinutes(minutes: 120))
        #expect(exact.evaluate(hours: "2", minutes: "0") == .correct)
        #expect(exact.evaluate(hours: "2", minutes: "00") == .correct)
        #expect(exact.evaluate(hours: "2", minutes: "") == .correct)
        #expect(exact.evaluate(hours: "1", minutes: "60") == .incorrect)
    }

    @Test func timeAfterIsAnsweredInTwentyFourHourTime() {
        let morning = Question(kind: .timeAfter(hours: 2, minutes: 30, startHour: 7, startMinute: 45))
        #expect(morning.answer == (10, 15))
        #expect(morning.evaluate(hours: "10", minutes: "15") == .correct)

        let afternoon = Question(kind: .timeAfter(hours: 3, minutes: 0, startHour: 11, startMinute: 0))
        #expect(afternoon.evaluate(hours: "14", minutes: "00") == .correct)
        #expect(afternoon.evaluate(hours: "14", minutes: "0") == .correct)
        // 2 PM written in 12-hour time isn't the 24-hour answer asked for.
        #expect(afternoon.evaluate(hours: "2", minutes: "00") == .incorrect)

        // Past midnight wraps round to the next day.
        let lateNight = Question(kind: .timeAfter(hours: 2, minutes: 0, startHour: 22, startMinute: 30))
        #expect(lateNight.answer == (0, 30))
        #expect(lateNight.evaluate(hours: "00", minutes: "30") == .correct)
        #expect(lateNight.evaluate(hours: "0", minutes: "30") == .correct)
        #expect(lateNight.evaluate(hours: "24", minutes: "30") == .incorrect)
        #expect(lateNight.evaluate(hours: "", minutes: "30") == .incorrect)
        #expect(lateNight.evaluate(hours: "", minutes: "") == .unanswered)

        let lastMinute = Question(kind: .timeAfter(hours: 0, minutes: 1, startHour: 23, startMinute: 59))
        #expect(lastMinute.answer == (0, 0))
        #expect(lastMinute.evaluate(hours: "00", minutes: "00") == .correct)
    }

    @Test func readingTheClockIsAnsweredInTwelveHourTime() {
        let pastMidnight = Question(kind: .readClock(hour: 0, minute: 5))
        #expect(pastMidnight.evaluate(hours: "12", minutes: "05") == .correct)
        #expect(pastMidnight.evaluate(hours: "12", minutes: "5") == .correct)
        #expect(pastMidnight.evaluate(hours: "0", minutes: "05") == .incorrect)

        let afternoon = Question(kind: .readClock(hour: 15, minute: 30))
        #expect(afternoon.evaluate(hours: "3", minutes: "30") == .correct)
        #expect(afternoon.evaluate(hours: "15", minutes: "30") == .incorrect)
        #expect(afternoon.evaluate(hours: "", minutes: "") == .unanswered)
    }

    @Test func settingTheClockMatchesTheFaceNotAMorPM() {
        let question = Question(kind: .setClock(hour: 15, minute: 30))
        #expect(question.evaluate(hours: "", minutes: "", clockHour: 3, clockMinute: 30) == .correct)
        #expect(question.evaluate(hours: "", minutes: "", clockHour: 3, clockMinute: 35) == .incorrect)
        // The clock left at 12:00 hasn't been set, so since Stage 6E it is asked for rather than marked wrong.
        #expect(question.evaluate(hours: "", minutes: "", clockHour: 0, clockMinute: 0) == .unanswered)
    }

    /// Bounds, wording and marking of every generated question, and the old mix of questions.
    @Test func generatedQuestionsAreAnswerableAndCountedFairly() {
        var generator = SeededGenerator(seed: 0x6D04)
        var counts = [String: Int]()
        let samples = 60_000
        for _ in 0..<samples {
            let question = Question.random(using: &generator)
            let answer = question.answer
            #expect(!question.text.contains(singularMistakes), "\(question.text)")
            switch question.kind {
            case let .toMinutes(hours, minutes):
                counts["toMinutes", default: 0] += 1
                #expect(Question.hoursToConvert.contains(hours) && (0..<60).contains(minutes))
                #expect(numbersShown(in: question.text) == (minutes == 0 ? [hours] : [hours, minutes]))
                #expect(question.evaluate(hours: "", minutes: "\(answer.minutes)") == .correct)
                #expect(question.evaluate(hours: "", minutes: "\(answer.minutes + 1)") == .incorrect)
            case let .toHoursAndMinutes(minutes):
                counts["toHoursAndMinutes", default: 0] += 1
                #expect(Question.minutesToConvert.contains(minutes))
                #expect(answer.hours >= 1 && (0..<60).contains(answer.minutes))
                #expect(answer.hours * 60 + answer.minutes == minutes)
                #expect(question.evaluate(hours: "\(answer.hours)", minutes: "\(answer.minutes)") == .correct)
                #expect(question.evaluate(hours: "\(answer.hours + 1)", minutes: "\(answer.minutes)") == .incorrect)
            case let .timeAfter(hours, minutes, startHour, startMinute):
                counts["timeAfter", default: 0] += 1
                #expect(Question.durationHours.contains(hours) && (0..<60).contains(minutes))
                #expect(hours > 0 || minutes > 0)
                #expect((0...23).contains(startHour) && (0..<60).contains(startMinute))
                #expect(question.text.hasSuffix(String(format: "after %02d:%02d?", startHour, startMinute)))
                #expect((0...23).contains(answer.hours) && (0..<60).contains(answer.minutes))
                let elapsed = ((answer.hours * 60 + answer.minutes) - (startHour * 60 + startMinute) + 1440) % 1440
                #expect(elapsed == hours * 60 + minutes)
                #expect(question.evaluate(hours: String(format: "%02d", answer.hours),
                                          minutes: String(format: "%02d", answer.minutes)) == .correct)
                #expect(question.evaluate(hours: "\(answer.hours)", minutes: "\(answer.minutes)") == .correct)
                #expect(question.evaluate(hours: "\((answer.hours + 1) % 24)", minutes: "\(answer.minutes)") == .incorrect)
            case let .readClock(hour, minute):
                counts["readClock", default: 0] += 1
                #expect((0...23).contains(hour) && (0..<60).contains(minute))
                #expect((1...12).contains(answer.hours))
                #expect(question.evaluate(hours: "\(answer.hours)", minutes: "\(answer.minutes)") == .correct)
                #expect(question.evaluate(hours: "\(answer.hours % 12 + 1)", minutes: "\(answer.minutes)") == .incorrect)
            case let .setClock(hour, minute):
                counts["setClock", default: 0] += 1
                // The clock starts at 12:00, so that is never the answer.
                #expect(!(hour % 12 == 0 && minute == 0))
                #expect(question.evaluate(hours: "", minutes: "", clockHour: 0, clockMinute: 0) == .unanswered)
                #expect(question.evaluate(hours: "", minutes: "", clockHour: hour % 12, clockMinute: minute) == .correct)
            }
        }
        let sixth = Double(samples) / 6
        for kind in ["toMinutes", "toHoursAndMinutes", "readClock", "setClock"] {
            #expect(abs(Double(counts[kind, default: 0]) - sixth) < sixth * 0.1, "\(kind): \(counts[kind, default: 0])")
        }
        #expect(abs(Double(counts["timeAfter", default: 0]) - 2 * sixth) < sixth * 0.2)
    }
}

// MARK: - Year 4 Geometry angles

struct Stage6DAngleTests {
    private func angle(_ degrees: Int) -> Year4GeometryQuestion {
        Year4GeometryQuestion(question: 3, shapeType: 3, sides: [3, 4, 5], angleMeasure: degrees, unitType: "cm")
    }

    /// 89° and 91° can't be told from a right angle by eye, and a right angle used to come up 1 time in 179.
    @Test func anglesAreClearlyAcuteRightOrObtuseAndEquallyLikely() {
        #expect(Year4GeometryQuestion.angles.allSatisfy { $0 == 90 || (10...75).contains($0) || (105...170).contains($0) })
        var generator = SeededGenerator(seed: 0x6D05)
        var types = [String: Int]()
        for _ in 0..<30_000 {
            let degrees = Year4GeometryQuestion.randomAngle(using: &generator)
            #expect(Year4GeometryQuestion.angles.contains(degrees))
            types[angle(degrees).angleType, default: 0] += 1
        }
        for type in ["acute", "right", "obtuse"] {
            #expect(abs(types[type, default: 0] - 10_000) < 1_000, "\(type): \(types[type, default: 0])")
        }
    }

    @Test func angleNamesAreAcceptedWithOrWithoutTheWordAngle() {
        for answer in ["acute", "Acute angle", "acute-angled", "acute.", " ACUTE "] {
            #expect(angle(40).evaluate(answer: answer, unit: "") == .correct, "\(answer)")
        }
        for answer in ["right", "Right angle", "right-angle", "right angled", "Right-angled."] {
            #expect(angle(90).evaluate(answer: answer, unit: "") == .correct, "\(answer)")
        }
        for answer in ["obtuse", "obtuse angle", "Obtuse!"] {
            #expect(angle(130).evaluate(answer: answer, unit: "") == .correct, "\(answer)")
        }
        for answer in ["angle", "acutee", "45", "acute obtuse", "not acute", "right angle triangle", "obtuse"] {
            #expect(angle(40).evaluate(answer: answer, unit: "") == .incorrect, "\(answer)")
        }
        #expect(angle(90).evaluate(answer: "acute angle", unit: "") == .incorrect)
        // Since Stage 6E nothing typed is asked for again rather than marked wrong.
        #expect(angle(40).evaluate(answer: "", unit: "") == .unanswered)
    }
}

// MARK: - Typed whole numbers

struct Stage6DWholeNumberTests {
    /// Year 1 Addition and Subtraction, Year 3 Fractions and Year 5 Percentages read answers this way now,
    /// so a stray space (easy to type on the iPad keyboard) no longer marks a right answer wrong.
    @Test func wholeNumbersIgnoreSurroundingSpacesOnly() {
        #expect(TypedAnswer.wholeNumber("7") == 7)
        #expect(TypedAnswer.wholeNumber(" 7 ") == 7)
        #expect(TypedAnswer.wholeNumber("07") == 7)
        #expect(TypedAnswer.wholeNumber("0") == 0)
        for typed in ["", " ", "+7", "-7", "7.0", "7,0", "1 0", "seven", "99999999999999999999"] {
            #expect(TypedAnswer.wholeNumber(typed) == nil, "\(typed)")
        }
    }
}

// MARK: - Scoring wiring in the views

private enum Stage6DSource {
    static let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Maths Quest")
        .appendingPathComponent("ContentView.swift")

    static var isAvailable: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    static let activityViews = [
        "Year1CountingView", "Year1AdditionView", "Year1SubtractionView",
        "Year2MultiplicationView", "Year2DivisionView", "Year2ShapesView",
        "Year3FractionsView", "Year3MeasurementView", "Year3TimeView",
        "Year4DecimalsView", "Year4GeometryView", "Year4MoneyView",
        "Year5PercentagesView", "Year5StatisticsView", "Year5VolumeView",
        "Year6AlgebraView", "Year6ProbabilityView", "Year6RatiosView",
    ]

    struct Missing: Error {
        var view: String
    }

    static func body(of view: String) throws -> String {
        let source = try String(contentsOf: url, encoding: .utf8)
        guard let start = source.range(of: "\nstruct \(view): View {"),
              let end = source.range(of: "\n}\n", range: start.upperBound..<source.endIndex) else {
            throw Missing(view: view)
        }
        return String(source[start.lowerBound..<end.upperBound])
    }

    static func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }
}

@Suite(.enabled(if: Stage6DSource.isAvailable, "ContentView.swift isn't reachable from this test run"))
struct Stage6DViewWiringTests {
    /// Year 4 Geometry scored without counting the question as answered.
    @Test(arguments: Stage6DSource.activityViews)
    func everyPointCountsTheQuestionAsAnswered(view: String) throws {
        let body = try Stage6DSource.body(of: view)
        let points = Stage6DSource.count("gameData.points += 1", in: body)
        #expect(points == 1, "\(view)")
        #expect(Stage6DSource.count("gameData.totalQuestionsAnswered += 1", in: body) == points, "\(view)")
    }

    /// Int("7 ") is nil, so typed answers go through TypedAnswer instead.
    @Test(arguments: Stage6DSource.activityViews)
    func typedAnswersAreNotReadWithIntInit(view: String) throws {
        let body = try Stage6DSource.body(of: view)
        #expect(!body.contains("Int(answerString)"), "\(view)")
        #expect(!body.contains("== String("), "\(view)")
    }

    @Test func year3TimeMarksThroughItsQuestion() throws {
        let body = try Stage6DSource.body(of: "Year3TimeView")
        #expect(body.contains("@State private var current = Year3TimeQuestion.random()"))
        #expect(Stage6DSource.count("current.evaluate(", in: body) == 1)
        #expect(body.contains("case .unanswered:"))
        #expect(!body.contains("analog clock"))
        // Since Stage 6E the clock's hands belong to the screen and go back to 12:00 for each question.
        #expect(body.contains("clockHour = 0"))
        #expect(!body.contains("interactiveclock"))
    }
}

// MARK: - Scoring and progression

struct Stage6DProgressionTests {
    /// The full life of one question: wrong answers never score, Skip shows after two, a correct answer
    /// scores once however many times Enter is pressed, and the next question starts clean.
    @Test func oneQuestionScoresAtMostOnce() {
        var progress = QuestionProgress()
        var points = 0
        func press(_ isCorrect: Bool) {
            if case .correct = progress.recordSubmission(isCorrect: isCorrect) { points += 1 }
        }

        press(false)
        #expect(!progress.showSkipButton && points == 0)
        press(false)
        #expect(progress.showSkipButton && points == 0)
        press(true)
        press(true)
        press(false)
        #expect(points == 1)
        #expect(!progress.showSkipButton)
        // Skip can't follow an answer, so the ad's reward can't move the question on a second time.
        let skippedAfterAnswering = progress.recordSkip()
        #expect(!skippedAfterAnswering)

        progress.reset()
        #expect(progress == QuestionProgress())
        press(true)
        #expect(points == 2)
    }

    /// Skipping moves on without scoring, and an answer that arrives after the skip is ignored.
    @Test func skippedQuestionsNeverScore() {
        var progress = QuestionProgress()
        let skippedTooEarly = progress.recordSkip()
        #expect(!skippedTooEarly)
        progress.recordWrongAttempt()
        progress.recordWrongAttempt()
        let skipped = progress.recordSkip()
        let skippedAgain = progress.recordSkip()
        let scoredAfterSkip = progress.recordCorrectAnswer()
        let lateEnter = progress.recordSubmission(isCorrect: true)
        #expect(skipped && !skippedAgain && !scoredAfterSkip)
        #expect(lateEnter == .ignored)
    }
}
