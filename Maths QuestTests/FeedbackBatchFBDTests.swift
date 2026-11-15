//
//  FeedbackBatchFBDTests.swift
//  Maths QuestTests
//
//  User feedback, batch FB-D: the owner's two decisions after batches FB-B and FB-C.
//  - Shapes: "diamond" or "rhombus" for the square standing on its corner says that turning a shape doesn't change
//    it, with a hint saying what a square is: 4 equal sides and 4 right angles. It is still asked for again without
//    scoring, counting towards Skip or playing a sound, and it shows only there.
//  - Ratio: one of the two boxes left empty is asked for again with "Fill in both boxes.", as in Time, Fractions and
//    Probability, instead of counting as a wrong answer with a hint. Right and wrong ratios are marked as before.
//

import CoreGraphics
import Foundation
import Testing
@testable import Maths_Quest

// MARK: - Shapes: the turned square

struct FBDShapeTests {
    static let squareIndex = Year2ShapeQuestion.figures.firstIndex { $0.name == "square" }!
    static let allQuestions = Year2ShapeQuestion.figures.indices.flatMap { index in
        [Year2ShapeQuestion.Kind.sides, .corners, .name].map { Year2ShapeQuestion(kind: $0, figureIndex: index) }
    }

    /// The square in the picture really has 4 equal sides and 4 right angles, standing on a corner, so the hint is
    /// true of what the child sees.
    @Test func theSquareInThePictureHasFourEqualSidesAndFourRightAngles() {
        let figure = Year2ShapeQuestion.figures[Self.squareIndex]
        #expect(figure.straightSides == 4 && figure.corners == 4)
        for size in [CGFloat(40), 78, 120, 300] {
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            let corners = ShapeMaker.corners(sides: figure.straightSides, in: rect)
            #expect(corners.count == 4)
            let sides = (0..<4).map { i in
                let a = corners[i], b = corners[(i + 1) % 4]
                return hypot(b.x - a.x, b.y - a.y)
            }
            for side in sides {
                #expect(abs(side - sides[0]) < 0.0001 * size, "\(sides)")
            }
            for i in 0..<4 {
                let corner = corners[i], before = corners[(i + 3) % 4], after = corners[(i + 1) % 4]
                let u = CGVector(dx: before.x - corner.x, dy: before.y - corner.y)
                let v = CGVector(dx: after.x - corner.x, dy: after.y - corner.y)
                let degrees = acos((u.dx * v.dx + u.dy * v.dy) / (hypot(u.dx, u.dy) * hypot(v.dx, v.dy))) * 180 / .pi
                #expect(abs(degrees - 90) < 0.001, "corner \(i): \(degrees)°")
            }
            // Standing on a corner: the first corner is at the top, in the middle.
            #expect(abs(corners[0].x - rect.midX) < 0.0001 && abs(corners[0].y - rect.minY) < 0.0001)
        }
        let outline = Year2ShapeQuestion(kind: .name, figureIndex: Self.squareIndex).outline
        #expect(outline.filter { $0 == .corner }.count == 4 && outline.filter { $0 == .straightSide }.count == 4)
    }

    /// The headline says turning doesn't change the shape; the hint gives a square's two properties. A rhombus has 4
    /// equal sides too, so both are needed. Neither names a shape, so "diamond" doesn't give the answer away.
    @Test func theWording() {
        let headline = AnswerFormat.turnedSquare
        let hint = AnswerFormat.turnedSquareExplanation
        #expect(headline == "Turning it doesn't change what shape it is.")
        #expect(hint.text == "It still has 4 equal sides and 4 right angles, like the corners of a book. What is it called?")
        #expect(hint.spoken == hint.text)

        // Short enough to read at a glance, like the other messages, and not "Correct!" or "Incorrect".
        #expect(headline.hasSuffix(".") && headline.split(separator: " ").count <= 8)
        #expect(!headline.contains("Correct") && !headline.contains("Incorrect"))

        // The properties it states are the square's.
        let square = Year2ShapeQuestion.figures[Self.squareIndex]
        #expect(hint.text.contains("\(square.straightSides) equal sides"))
        #expect(hint.text.contains("\(square.corners) right angles"))
        #expect(hint.text.hasSuffix("?"))

        // It names no shape, not even the one typed.
        let names = Year2ShapeQuestion.figures.map(\.name) + ["diamond", "rhombus", "rectangle", "kite"]
        for text in [headline.lowercased(), hint.text.lowercased()] {
            for name in names {
                #expect(!text.contains(name), "\(name) in \(text)")
            }
        }
    }

    /// The hint is for "diamond" or "rhombus" when the square is to be named, and for nothing else: not for the
    /// other shapes, not when counting sides or corners, not for any right answer, and never in the question, the
    /// picture's VoiceOver labels or another activity.
    @Test func theHintIsOnlyForTheTurnedSquare() {
        let answers = ["diamond", "a diamond", "Rhombus.", "", "square", "a square", "rectangle", "kite", "4", "diamonds"]
            + Year2ShapeQuestion.figures.map(\.name)
        for question in Self.allQuestions {
            for answer in answers {
                let isTurnedSquare = question.kind == .name && question.figureIndex == Self.squareIndex
                    && ["diamond", "rhombus"].contains(Year2ShapeQuestion.typedName(answer))
                #expect(question.asksAgainAboutTheTurnedSquare(answer) == isTurnedSquare, "\(question.text) \(answer)")
            }
            let rightAnswer = question.kind == .name ? question.figure.name
                : "\(question.kind == .sides ? question.figure.straightSides : question.figure.corners)"
            #expect(question.evaluate(rightAnswer) == .correct)
            #expect(!question.asksAgainAboutTheTurnedSquare(rightAnswer))

            let shown = [question.text, question.pictureLabel, Year2ShapeQuestion.pictureHint]
                + question.outline.indices.map { question.spokenLabel(ofPartAt: $0) }
            for label in shown {
                #expect(!label.contains(AnswerFormat.turnedSquareExplanation.text) && !label.contains("right angle"))
                #expect(label != AnswerFormat.turnedSquare)
            }
        }
    }

    /// VoiceOver reads the message and the hint as one announcement, and the card as "Hint: …", as in Stage 9C.
    @Test func voiceOverReadsTheMessageAndTheHintTogether() {
        let hint = AnswerFormat.turnedSquareExplanation
        let feedback = AnswerFeedbackText(message: AnswerFormat.turnedSquare, alsoSaying: "Hint: \(hint.spoken)")
        #expect(feedback.announcement == "Turning it doesn't change what shape it is. Hint: It still has 4 equal sides and "
                + "4 right angles, like the corners of a book. What is it called?")
    }

    /// The screen sets the hint only in the turned-square guard, which still scores nothing; clears it on a right
    /// answer and a new question; reads it only with its own message; and shows it under Enter, as Stage 9C does.
    @Test func theScreenShowsTheHintOnlyThere() throws {
        let view = try FBDSource.view("Year2ShapesView")
        let check = try FBDSource.function("private func checkAnswer()", in: view)

        let asks = try FBDSource.position(of: "guard !current.asksAgainAboutTheTurnedSquare(answerString) else {", in: check)
        let marked = try FBDSource.position(of: "switch current.evaluate(answerString)", in: check)
        let guardBody = FBDSource.slice(check, from: asks, to: marked)
        #expect(guardBody.contains("responseMessage = AnswerFormat.turnedSquare"))
        #expect(guardBody.contains("hint = AnswerFormat.turnedSquareExplanation"))
        #expect(guardBody.contains("showFeedback()") && guardBody.contains("return"))
        for forbidden in ["points", "playSound", "recordWrongAttempt", "recordSubmission", "totalQuestionsAnswered"] {
            #expect(!guardBody.contains(forbidden), "\(forbidden)")
        }

        // The hint is set in three places only: shown in the guard, cleared by "Correct!" and by a new question.
        #expect(FBDSource.count("hint = ", in: view) == 3)
        #expect(FBDSource.count("hint = AnswerFormat.turnedSquareExplanation", in: view) == 1)
        let correct = try FBDSource.position(of: "case .correct:", in: check)
        let incorrect = try FBDSource.position(of: "case .incorrect:", in: check)
        #expect(FBDSource.slice(check, from: correct, to: incorrect).contains("hint = nil"))
        #expect(!check[check.index(check.startIndex, offsetBy: incorrect)...].contains("hint ="))
        let reset = try FBDSource.function("private func resetQuestion()", in: view)
        #expect(reset.contains("hint = nil"))

        #expect(view.contains("AnswerFeedbackText(message: responseMessage, alsoSaying: hintAnnouncement)"))
        #expect(view.contains("responseMessage == AnswerFormat.turnedSquare ? hint.map { \"Hint: \\($0.spoken)\" } : nil"))
        let row = try FBDSource.position(of: ".questionSubmitRow()", in: view)
        let cards = try FBDSource.position(of: "ExplanationCards(hint: hint, solution: nil, place: .belowSubmitRow)", in: view)
        #expect(row < cards)
        #expect(view.contains(".movesAtOnce(whenMessageAppears: showMessage)"))

        // No other screen uses the message or the hint.
        let app = try FBDSource.appSource()
        #expect(app.contains(view))
        let elsewhere = app.replacingOccurrences(of: view, with: "")
        #expect(!elsewhere.contains("AnswerFormat.turnedSquare"))
        // The words themselves are written once, where they are defined.
        #expect(FBDSource.count("4 equal sides and 4 right angles", in: app) == 1)
    }
}

// MARK: - Ratio: one box left empty

struct FBDRatioTests {
    static let ratios: [Year6RatioQuestion] = [Year6RatioQuestion.Kind.simplify, .share, .missingFirst, .missingSecond]
        .flatMap { kind in
            Year6RatioQuestion.ratioTerms.flatMap { first in
                Year6RatioQuestion.multipliers.flatMap { multiplier in
                    [1, 2, 3, 7].map { second in
                        Year6RatioQuestion(kind: kind, first: first, second: second, multiplier: multiplier)
                    }
                }
            }
        }

    @Test func oneEmptyBoxIsAskedForAgain() {
        for question in Self.ratios {
            guard let ratio = question.correctRatio else {
                // Missing-value questions have one box, so there is nothing to fill in.
                for (first, second) in [("3", ""), ("", "3"), ("", ""), ("3", "4")] {
                    #expect(!question.hasOneBoxEmpty(first: first, second: second))
                }
                continue
            }
            for (first, second) in [("\(ratio.first)", ""), ("", "\(ratio.second)"), (" \(ratio.first) ", "  "),
                                    ("\n", "\(ratio.second)"), ("abc", ""), ("99", "")] {
                #expect(question.hasOneBoxEmpty(first: first, second: second), "\(question.text) [\(first)] [\(second)]")
                // It is never right, so asking again can't turn a wrong answer into a right one.
                #expect(question.evaluate(first: first, second: second, missing: "") == .incorrect)
            }
            for (first, second) in [("", ""), (" ", "\n"), ("\(ratio.first)", "\(ratio.second)"), ("99", "99"),
                                    ("\(ratio.second)", "\(ratio.first)"), ("abc", "\(ratio.second)")] {
                #expect(!question.hasOneBoxEmpty(first: first, second: second), "\(question.text) [\(first)] [\(second)]")
            }
        }
    }

    /// Right answers are still right, wrong ones in both boxes are still wrong and counted, and a blank answer is
    /// still "Please enter an answer!".
    @Test func otherAnswersAreMarkedAsBefore() {
        for question in Self.ratios {
            if let ratio = question.correctRatio {
                #expect(question.evaluate(first: "\(ratio.first)", second: "\(ratio.second)", missing: "") == .correct)
                #expect(question.evaluate(first: " \(ratio.first)", second: "\(ratio.second) ", missing: "") == .correct)
                #expect(question.evaluate(first: "\(ratio.first + 1)", second: "\(ratio.second)", missing: "") == .incorrect)
                #expect(question.evaluate(first: "", second: "", missing: "") == .unanswered)
            } else if let missing = question.correctMissingValue {
                #expect(question.evaluate(first: "", second: "", missing: "\(missing)") == .correct)
                #expect(question.evaluate(first: "", second: "", missing: "\(missing + 1)") == .incorrect)
                #expect(question.evaluate(first: "", second: "", missing: "") == .unanswered)
            }
        }
    }

    @Test func rightAnswersToGeneratedQuestionsAreNeverAskedForAgain() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<2000 {
            let question = Year6RatioQuestion.random(using: &generator)
            guard let ratio = question.correctRatio else { continue }
            #expect(!question.hasOneBoxEmpty(first: "\(ratio.first)", second: "\(ratio.second)"))
            #expect(question.evaluate(first: "\(ratio.first)", second: "\(ratio.second)", missing: "") == .correct)
        }
    }

    /// The screen asks after "2:3" in one box and before marking. Like a blank answer, it gives no point, plays no
    /// sound, sets no hint and counts nothing towards Skip. A hint from an earlier wrong answer is read out only with
    /// "Incorrect. Try Again!", so not with "Fill in both boxes.".
    @Test func theScreenAsksBeforeMarking() throws {
        let view = try FBDSource.view("Year6RatiosView")
        let check = try FBDSource.function("private func checkAnswer()", in: view)
        let open = try FBDSource.position(of: "guard !progress.isAdvancing else { return }", in: check)
        let twoNumbers = try FBDSource.position(of: "guard !current.hasTwoNumbersInOneBox(first: answerRatio1, second: answerRatio2)",
                                                in: check)
        let oneEmpty = try FBDSource.position(of: "guard !current.hasOneBoxEmpty(first: answerRatio1, second: answerRatio2) else {",
                                              in: check)
        let marked = try FBDSource.position(of: "switch current.evaluate(first: answerRatio1, second: answerRatio2, missing: answerString)",
                                            in: check)
        #expect(open < twoNumbers && twoNumbers < oneEmpty && oneEmpty < marked)

        let body = FBDSource.slice(check, from: oneEmpty, to: marked)
        #expect(body.contains("responseMessage = AnswerFormat.fillInBothBoxes"))
        #expect(body.contains("showFeedback()") && body.contains("return"))
        for forbidden in ["points", "playSound", "recordWrongAttempt", "recordSubmission", "hint =", "solution =",
                          "totalQuestionsAnswered"] {
            #expect(!body.contains(forbidden), "\(forbidden)")
        }
        #expect(view.contains("responseMessage == \"Incorrect. Try Again!\" ? hint.map { \"Hint: \\($0.spoken)\" } : nil"))
        #expect(AnswerFormat.fillInBothBoxes == "Fill in both boxes.")
    }
}

// MARK: - Source

private enum FBDSourceError: Error {
    case missing(String)
}

private enum FBDSource {
    static let projectFolder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static func appSource() throws -> String {
        try ["ContentView.swift", "Explanations.swift", "DesignComponents.swift", "AnswerFormats.swift"]
            .map { try String(contentsOf: projectFolder.appendingPathComponent("Maths Quest/\($0)"), encoding: .utf8) }
            .joined(separator: "\n")
    }

    static func view(_ name: String) throws -> String {
        let source = try String(contentsOf: projectFolder.appendingPathComponent("Maths Quest/ContentView.swift"),
                                encoding: .utf8)
        guard let start = source.range(of: "\nstruct \(name): View {"),
              let end = source.range(of: "\n}\n", range: start.upperBound..<source.endIndex) else {
            throw FBDSourceError.missing(name)
        }
        return String(source[start.lowerBound..<end.upperBound])
    }

    static func function(_ opening: String, in body: String) throws -> String {
        guard let start = body.range(of: "    " + opening),
              let end = body.range(of: "\n    }\n", range: start.upperBound..<body.endIndex) else {
            throw FBDSourceError.missing(opening)
        }
        return String(body[start.lowerBound..<end.upperBound])
    }

    static func position(of needle: String, in text: String) throws -> Int {
        guard let range = text.range(of: needle) else {
            throw FBDSourceError.missing(needle)
        }
        return text.distance(from: text.startIndex, to: range.lowerBound)
    }

    static func slice(_ text: String, from start: Int, to end: Int) -> Substring {
        text[text.index(text.startIndex, offsetBy: start)..<text.index(text.startIndex, offsetBy: end)]
    }

    static func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }
}
