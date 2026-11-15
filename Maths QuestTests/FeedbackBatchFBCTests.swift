//
//  FeedbackBatchFBCTests.swift
//  Maths QuestTests
//
//  User feedback, batch FB-C: children reported that Enter didn't respond straight after a message. Enter can't be
//  tapped while a message shows, so that one answer can't be marked twice, and two things kept it unavailable for
//  longer than they should:
//  - a corrected answer couldn't be entered until the message about the old answer had gone, and
//  - the timer of an earlier message could hide a newer one early, or, the other way round, let a message about a
//    new answer vanish before it had been read.
//  Now changing the answer hides the message about the old one, and only a message's own timer hides it. Enter is
//  still unavailable while a message shows, and an answered or skipped question still ignores Enter and Return, so
//  nothing scores twice. The timeline tests in Stage4AScoringIntegrityTests model the same rules.
//

import Foundation
import Testing
@testable import Maths_Quest

// MARK: - The clock

struct FBCMessageClockTests {
    @Test func aNewClockHasShownNothing() {
        let clock = AnswerMessageClock()
        #expect(clock.current == 0)
        #expect(clock.isShowing(0))
        #expect(!clock.isShowing(1))
    }

    @Test func eachMessageGetsTheNextNumber() {
        var clock = AnswerMessageClock()
        for expected in 1...50 {
            #expect(clock.show() == expected)
            #expect(clock.current == expected)
        }
    }

    /// Only the latest message's timer may hide it: the earlier timer finds that a newer message is showing.
    @Test func onlyTheLatestMessageIsShowing() {
        var clock = AnswerMessageClock()
        let wrong = clock.show()
        #expect(clock.isShowing(wrong))
        let correct = clock.show()
        #expect(!clock.isShowing(wrong), "The wrong answer's timer leaves \"Correct!\" alone")
        #expect(clock.isShowing(correct))
        let third = clock.show()
        #expect(!clock.isShowing(correct))
        #expect(clock.isShowing(third))
    }

    /// Two screens, or the same screen opened twice, each keep their own count.
    @Test func eachScreenHasItsOwnClock() {
        var first = AnswerMessageClock()
        var second = AnswerMessageClock()
        let shownOnFirst = first.show()
        _ = second.show()
        _ = second.show()
        #expect(first.isShowing(shownOnFirst))
        #expect(!second.isShowing(shownOnFirst))
    }

    @Test func clocksCompareByCount() {
        var first = AnswerMessageClock()
        var second = AnswerMessageClock()
        #expect(first == second)
        _ = first.show()
        #expect(first != second)
        _ = second.show()
        #expect(first == second)
    }
}

// MARK: - The 18 activities

private enum FBCSourceError: Error {
    case missing(String)
}

private enum FBCSource {
    static let projectFolder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static var isAvailable: Bool {
        FileManager.default.fileExists(atPath: projectFolder.appendingPathComponent("Maths Quest/ContentView.swift").path)
    }

    /// Every activity, with what the child types, picks or drags to answer, in the order the view lists it.
    static let answers: [String: [String]] = [
        "Year1CountingView": ["answerString"],
        "Year1AdditionView": ["answerString"],
        "Year1SubtractionView": ["answerString"],
        "Year2MultiplicationView": ["answerString"],
        "Year2DivisionView": ["answerString"],
        "Year2ShapesView": ["answerString"],
        "Year3FractionsView": ["answerString", "numeratorString", "denominatorString"],
        "Year3MeasurementView": ["answerString", "userUnit"],
        "Year3TimeView": ["hoursanswer", "minutesanswer", "\"\\(clockHour)\"", "\"\\(clockMinute)\""],
        "Year4DecimalsView": ["answerString"],
        "Year4GeometryView": ["answerString", "userUnit"],
        "Year4MoneyView": ["answerString"],
        "Year5PercentagesView": ["answerString"],
        "Year5StatisticsView": ["answerString"],
        "Year5VolumeView": ["answerString"],
        "Year6AlgebraView": ["stringAnswer"],
        "Year6ProbabilityView": ["numerator", "denominator"],
        "Year6RatiosView": ["answerString", "answerRatio1", "answerRatio2"],
    ]

    static let activityViews = answers.keys.sorted()

    static func source() throws -> String {
        try String(contentsOf: projectFolder.appendingPathComponent("Maths Quest/ContentView.swift"), encoding: .utf8)
    }

    /// From `struct Name: View {` to its closing brace in the first column.
    static func view(_ name: String) throws -> String {
        let source = try source()
        guard let start = source.range(of: "\nstruct \(name): View {"),
              let end = source.range(of: "\n}\n", range: start.upperBound..<source.endIndex) else {
            throw FBCSourceError.missing(name)
        }
        return String(source[start.lowerBound..<end.upperBound])
    }

    static func function(_ opening: String, in body: String) throws -> String {
        guard let start = body.range(of: "    " + opening),
              let end = body.range(of: "\n    }\n", range: start.upperBound..<body.endIndex) else {
            throw FBCSourceError.missing(opening)
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

    /// The modifier's arguments, joined onto one line.
    static func hidesAnswerMessage(in body: String) throws -> String {
        guard let start = body.range(of: ".hidesAnswerMessage("),
              let end = body.range(of: "})", range: start.upperBound..<body.endIndex) else {
            throw FBCSourceError.missing(".hidesAnswerMessage(")
        }
        return lines(of: String(body[start.lowerBound..<end.upperBound])).joined(separator: " ")
    }
}

@Suite(.enabled(if: FBCSource.isAvailable, "ContentView.swift isn't reachable from this test run"))
struct FBCViewWiringTests {
    /// The list above is every activity in the app, so none is left out.
    @Test func everyActivityIsChecked() throws {
        let source = try FBCSource.source()
        let views = try Regex(#"\nstruct (Year\d\w+View): View \{"#)
        let names = source.matches(of: views).compactMap { $0.output[1].substring.map(String.init) }
        let activities = names.filter { $0.range(of: #"^Year\dView$"#, options: .regularExpression) == nil }
        #expect(Set(activities) == Set(FBCSource.activityViews))
        #expect(FBCSource.activityViews.count == 18)
        #expect(FBCSource.count("@State private var messageClock = AnswerMessageClock()", in: source) == 18)
        #expect(FBCSource.count(".hidesAnswerMessage(whenChanged:", in: source) == 18)
    }

    /// Each message's timer hides it only if no newer message has been shown since.
    @Test(arguments: FBCSource.activityViews)
    func onlyTheLatestMessageHidesItself(view: String) throws {
        let body = try FBCSource.view(view)
        #expect(FBCSource.count("@State private var messageClock = AnswerMessageClock()", in: body) == 1)
        let feedback = try FBCSource.function("private func showFeedback() {", in: body)
        let lines = FBCSource.lines(of: feedback)
        guard let shown = lines.firstIndex(of: "showMessage = true"),
              let numbered = lines.firstIndex(of: "let shown = messageClock.show()"),
              let timer = lines.firstIndex(where: { $0.hasPrefix("DispatchQueue.main.asyncAfter(deadline: .now() + ") }),
              let check = lines.firstIndex(of: "guard messageClock.isShowing(shown) else { return }"),
              let hidden = lines.firstIndex(of: "showMessage = false") else {
            Issue.record("\(view).showFeedback() doesn't number its message: \(lines)")
            return
        }
        #expect(shown < numbered && numbered < timer && timer < check && check < hidden, "\(view)")
        #expect(FBCSource.count("showMessage = true", in: feedback) == 1)
        #expect(FBCSource.count("messageClock.show()", in: body) == 1, "\(view): only showFeedback() numbers messages")
    }

    /// Changing anything the child answers with hides the message about the old answer, and nothing else does.
    @Test(arguments: FBCSource.activityViews)
    func changingTheAnswerHidesTheMessage(view: String) throws {
        let body = try FBCSource.view(view)
        let expected = try #require(FBCSource.answers[view])
        let modifier = try FBCSource.hidesAnswerMessage(in: body)
        #expect(modifier == ".hidesAnswerMessage(whenChanged: [\(expected.joined(separator: ", "))], "
                    + "showMessage: $showMessage, isAdvancing: { progress.isAdvancing })", "\(view)")
        #expect(FBCSource.count(".hidesAnswerMessage(", in: body) == 1)

        // Every box and wheel in the view is watched.
        let bindings = try Regex(#"(?:text|selection): \$(\w+)"#)
        let bound = Set(body.matches(of: bindings).compactMap { $0.output[1].substring.map(String.init) })
        let watched = Set(expected.map { $0.replacingOccurrences(of: "\"\\(", with: "").replacingOccurrences(of: ")\"", with: "") })
        #expect(bound.isSubset(of: watched), "\(view): \(bound.subtracting(watched)) isn't watched")
        for name in watched {
            #expect(body.contains("@State private var \(name)") || body.contains("@State var \(name)"),
                    "\(view): \(name) is the view's own state")
        }
    }

    /// Enter still can't be tapped while a message shows, and the message still shows only while showMessage is set.
    @Test(arguments: FBCSource.activityViews)
    func enterIsStillUnavailableWhileAMessageShows(view: String) throws {
        let body = try FBCSource.view(view)
        #expect(FBCSource.count(".disabled(showMessage)", in: body) == 1, "\(view)")
        #expect(FBCSource.count("if showMessage {", in: body) == 1, "\(view)")
        // Apart from the modifier, only the message's own timer and, in some activities, the next question hide it.
        func hides(_ text: String) -> Int {
            FBCSource.lines(of: text).filter { $0 == "showMessage = false" }.count
        }
        let feedback = try FBCSource.function("private func showFeedback() {", in: body)
        let reset = try FBCSource.function("private func resetQuestion() {", in: body)
        #expect(hides(feedback) == 1, "\(view)")
        #expect(hides(body) == hides(feedback) + hides(reset), "\(view)")
        let check = try FBCSource.function("private func checkAnswer(", in: body)
        #expect(check.contains("guard !progress.isAdvancing else { return }"), "\(view)")
    }
}
