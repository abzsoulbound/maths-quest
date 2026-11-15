//
//  FeedbackBatchFBATests.swift
//  Maths QuestTests
//
//  User feedback, batch FB-A. Children reported right answers marked wrong (FB-01), the same message sent more
//  than once (FB-02) and questions sent to Feedback in the hope of an answer (FB-05). This batch:
//  - Volume asks again for a cube or cuboid answer written like "1,000", which is 1000 with a thousands comma but 1
//    with a decimal comma, as Measurement already does, instead of marking it wrong.
//  - Measurement says "Correct number, but wrong unit!" for the right number with the wrong unit, or none. It still
//    counts as a wrong attempt.
//  - Feedback says no one will reply.
//  - DEBUG builds only: a UI test can point Firestore at an emulator it started on another port on this Mac, so it
//    can count what Feedback sends.
//  Nothing here talks to Firestore.
//

import Foundation
import FirebaseFirestore
import Testing
@testable import Maths_Quest

// MARK: - Volume: "1,000"

struct FBAVolumeCommaTests {
    /// Every cube and cuboid the activity can ask about.
    static let solids: [Year5VolumeQuestion] = {
        let edges = Year5VolumeQuestion.edgeLengths
        var solids = edges.map {
            Year5VolumeQuestion(kind: .cube, length: $0, width: $0, height: $0, glassAMillilitres: 0, glassBMillilitres: 0)
        }
        for length in edges {
            for width in edges {
                for height in edges {
                    solids.append(Year5VolumeQuestion(kind: .cuboid, length: length, width: width, height: height,
                                                      glassAMillilitres: 0, glassBMillilitres: 0))
                }
            }
        }
        return solids
    }()

    @Test func everySolidIsChecked() {
        #expect(Self.solids.count == 9 + 9 * 9 * 9)
        #expect(Self.solids.contains { $0.volume == 1000 })
    }

    @Test func aThousandsCommaIsAskedForAgain() {
        for question in Self.solids {
            for answer in ["1,000", " 1,000 ", "8,000", "2,500", "125,000", "999,999"] {
                #expect(question.needsWritingWithoutAComma(answer: answer), "\(question.figureDescription) \"\(answer)\"")
            }
        }
    }

    /// Only the ambiguous form is asked for again. Everything else is marked as before.
    @Test func otherAnswersAreMarkedAsBefore() {
        for question in Self.solids {
            let answers = ["\(question.volume)", " \(question.volume) ", "0\(question.volume)", "\(question.volume).0",
                           "\(question.volume),0", "\(question.volume).000", "1000", "125,0", "125,00", "125.000",
                           "0,125", "1,000.5", "1,0000", "1,00", "", "   ", "abc", "1 000", "9999"]
            for answer in answers {
                #expect(!question.needsWritingWithoutAComma(answer: answer), "\(question.figureDescription) \"\(answer)\"")
            }
            // The right answer, without a comma, is still right.
            #expect(question.isCorrect(answer: "\(question.volume)"))
        }
    }

    @Test func theGlassQuestionIsNotAffected() {
        let glasses = Year5VolumeQuestion(kind: .comparison, length: 0, width: 0, height: 0,
                                          glassAMillilitres: 1000, glassBMillilitres: 1250)
        for answer in ["1,000", "1,250", "A", "B"] {
            #expect(!glasses.needsWritingWithoutAComma(answer: answer))
        }
        #expect(glasses.isCorrect(answer: "B"))
        #expect(!glasses.isCorrect(answer: "A"))
    }

    /// The view asks again before marking, so "1,000" neither scores nor counts towards Skip, like a blank answer.
    @Test func theViewAsksAgainBeforeMarking() throws {
        let check = try FBASource.function("private func checkAnswer()", inView: "Year5VolumeView")
        let blank = try FBASource.position(of: "guard !TypedAnswer.isBlank(answerString)", in: check)
        let comma = try FBASource.position(of: "guard !current.needsWritingWithoutAComma(answer: answerString)", in: check)
        let message = try FBASource.position(of: "responseMessage = \"Write it without a comma.\"", in: check)
        let marking = try FBASource.position(of: "progress.recordSubmission(", in: check)
        #expect(blank < comma)
        #expect(comma < message)
        #expect(message < marking)
        let commaGuard = check[check.index(check.startIndex, offsetBy: comma)..<check.index(check.startIndex, offsetBy: marking)]
        #expect(commaGuard.contains("return"))
        #expect(!commaGuard.contains("points"))
        #expect(!commaGuard.contains("recordWrongAttempt"))
    }
}

// MARK: - Measurement: the right number with the wrong unit

struct FBAMeasurementUnitTests {
    /// Every conversion the activity can ask for.
    static let conversions: [Year3MeasurementQuestion] = {
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
        return questions
    }()

    @Test func everyConversionIsChecked() {
        // m to cm, m to mm, cm to mm, kg to g and l to ml, for 1 to 10 of each.
        #expect(Self.conversions.count == 5 * 10)
    }

    @Test func theRightNumberWithTheWrongUnitOrNoneIsCalledOut() {
        for question in Self.conversions {
            let number = "\(question.convertedAmount)"
            let wrongUnits = [""] + question.units.filter { $0 != question.toUnit }
            for unit in wrongUnits {
                for answer in [number, " \(number) ", "\(number).0", "0\(number)"] {
                    #expect(question.hasRightNumberButWrongUnit(answer: answer, unit: unit), "\(question.text) \"\(answer)\" \(unit)")
                    // Still wrong, and still a wrong attempt.
                    #expect(question.evaluate(answer: answer, unit: unit) == .incorrect)
                }
            }
            #expect(!question.hasRightNumberButWrongUnit(answer: number, unit: question.toUnit))
            #expect(question.evaluate(answer: number, unit: question.toUnit) == .correct)
        }
    }

    @Test func aWrongNumberOrNoNumberIsNotCalledOut() {
        for question in Self.conversions {
            let wrongNumbers = ["\(question.convertedAmount + 1)", "\(question.amount)", "0", "", " ", "abc", "1,000",
                                "\(question.convertedAmount)0"]
            for unit in [""] + question.units {
                for answer in wrongNumbers where answer != "\(question.convertedAmount)" {
                    #expect(!question.hasRightNumberButWrongUnit(answer: answer, unit: unit), "\(question.text) \"\(answer)\" \(unit)")
                }
            }
        }
    }

    /// Measuring with the ruler is always in centimetres, so there's no unit to get wrong.
    @Test func measuringIsNotAffected() {
        for length in Year3MeasurementQuestion.objectLengths {
            let question = Year3MeasurementQuestion(kind: .measure, group: 0, from: 0, to: 1, amount: 1, objectLength: length)
            for unit in ["", "m", "cm", "mm"] {
                #expect(!question.hasRightNumberButWrongUnit(answer: "\(length)", unit: unit))
                #expect(!question.hasRightNumberButWrongUnit(answer: "\(length * 10)", unit: unit))
            }
        }
    }

    /// Only the message changes: a wrong unit still plays the wrong sound and counts as a wrong attempt.
    @Test func theViewOnlyChangesTheMessage() throws {
        let check = try FBASource.function("private func checkAnswer()", inView: "Year3MeasurementView")
        let incorrect = try FBASource.position(of: "case .incorrect:", in: check)
        let tail = String(check[check.index(check.startIndex, offsetBy: incorrect)...])
        let compact = tail.filter { !$0.isWhitespace }
        #expect(compact.contains(#"responseMessage=current.hasRightNumberButWrongUnit(answer:answerString,unit:userUnit)?"Correctnumber,butwrongunit!":"Incorrect.TryAgain!""#))
        #expect(tail.contains("progress.recordWrongAttempt()"))
        #expect(tail.contains("sfxPlayer.playSound(named: \"wrong\""))
        #expect(!tail.contains("points"))
    }
}

// MARK: - Feedback: no reply

@MainActor
struct FBAFeedbackNoReplyTests {
    @Test func theNoticeSaysThereWillBeNoReply() {
        #expect(FeedbackView.noReplyNotice == "You won't get a reply to messages sent here.")
        // Short, and as plain as the reminder above it.
        #expect(FeedbackView.noReplyNotice.split(separator: " ").count <= 10)
    }

    /// Under the privacy reminder, in the heading, which scrolls rather than pushing Enter under the keyboard.
    @Test func theNoticeIsShownUnderTheReminder() throws {
        let heading = try FBASource.function("private var heading: some View", inView: "FeedbackView")
        let reminder = try FBASource.position(of: "Text(FeedbackView.privacyReminder)", in: heading)
        let notice = try FBASource.position(of: "Text(FeedbackView.noReplyNotice)", in: heading)
        #expect(reminder < notice)
        let noticeCode = String(heading[heading.index(heading.startIndex, offsetBy: notice)...])
        #expect(noticeCode.contains(".scaledFont(size: Metrics.contentWidth * 0.04, maximum: 28)"))
        #expect(noticeCode.contains(".fixedSize(horizontal: false, vertical: true)"))
        #expect(!noticeCode.contains(".accessibilityHidden"))
    }
}

// MARK: - The UI-test Firestore port (DEBUG builds only)

struct FBAUITestFirestorePortTests {
    @Test func theArgumentsAreAsTheUITestsUseThem() {
        #expect(UITestFirestore.portArgument == "-MathsQuestFirestorePort")
        #expect(UITestFirestore.emulatorHost == "127.0.0.1:8080")
    }

    @Test func aPortIsUsedOnlyInUITestLaunches() throws {
        #expect(UITestFirestore.settings(forLaunchArguments: [UITestFirestore.portArgument, "9199"]) == nil)
        let settings = try #require(UITestFirestore.settings(
            forLaunchArguments: ["Maths Quest", UITestFirestore.launchArgument, UITestFirestore.portArgument, "9199"]))
        #expect(settings.host == "127.0.0.1:9199")
        #expect(!settings.isSSLEnabled)
    }

    @Test func withoutAPortTheUsualEmulatorIsUsed() throws {
        #expect(UITestFirestore.host(forLaunchArguments: []) == UITestFirestore.emulatorHost)
        #expect(UITestFirestore.host(forLaunchArguments: [UITestFirestore.launchArgument]) == UITestFirestore.emulatorHost)
        let settings = try #require(UITestFirestore.settings(forLaunchArguments: [UITestFirestore.launchArgument]))
        #expect(settings.host == UITestFirestore.emulatorHost)
    }

    @Test func anUnusablePortFallsBackToTheUsualEmulator() {
        let unusable = ["", "abc", "0", "80", "1023", "65536", "70000", "-1", "9199.5", " 9199", "9199 ",
                        "127.0.0.1:9199", "example.com"]
        for value in unusable {
            #expect(UITestFirestore.host(forLaunchArguments: [UITestFirestore.launchArgument, UITestFirestore.portArgument, value])
                    == UITestFirestore.emulatorHost, "\"\(value)\"")
        }
        // The flag with nothing after it.
        #expect(UITestFirestore.host(forLaunchArguments: [UITestFirestore.launchArgument, UITestFirestore.portArgument])
                == UITestFirestore.emulatorHost)
    }

    /// Whatever is passed, Firestore only ever talks to this Mac.
    @Test func theHostIsAlwaysThisMac() {
        for value in ["1024", "9199", "65535", "8080", "abc", "evil.example.com"] {
            let host = UITestFirestore.host(forLaunchArguments: [UITestFirestore.launchArgument, UITestFirestore.portArgument, value])
            #expect(host.hasPrefix("127.0.0.1:"), "\(host)")
        }
        #expect(UITestFirestore.host(forLaunchArguments: [UITestFirestore.launchArgument, UITestFirestore.portArgument, "1024"]) == "127.0.0.1:1024")
        #expect(UITestFirestore.host(forLaunchArguments: [UITestFirestore.launchArgument, UITestFirestore.portArgument, "65535"]) == "127.0.0.1:65535")
    }

    /// The option is inside the DEBUG-only enum, and the UI test and the emulator script agree with it.
    @Test func theWiringMatches() throws {
        let appDelegate = try FBASource.text("Maths Quest/AppDelegate.swift")
        let declaration = try FBASource.position(of: "enum UITestFirestore", in: appDelegate)
        let option = try FBASource.position(of: "static let portArgument = \"-MathsQuestFirestorePort\"", in: appDelegate)
        let endDebug = try FBASource.position(of: "#endif", in: appDelegate, after: declaration)
        #expect(declaration < option)
        #expect(option < endDebug)
        #expect(appDelegate.contains("settings.host = host(forLaunchArguments: arguments)"))
        #expect(appDelegate.contains("return \"127.0.0.1:\\(port)\""))

        let uiTest = try FBASource.text("Maths QuestUITests/FeedbackBatchFBAUITests.swift")
        #expect(uiTest.contains("\"\(UITestFirestore.portArgument)\""))
        #expect(uiTest.contains("MATHSQUEST_FEEDBACK_EMULATOR_PORT"))

        let script = try FBASource.text("firebase/tests/feedback-emulator.mjs")
        #expect(script.contains("'--host', '127.0.0.1'"))
        #expect(script.contains("if (port !== 8080) return port;"))
        #expect(script.contains("readFileSync(RULES_FILE, 'utf8')"))
        #expect(script.contains("MATHSQUEST_FEEDBACK_EMULATOR_PORT="))
    }
}

// MARK: - Reading the source

private enum FBASourceError: Error {
    case missing(String)
}

private enum FBASource {
    static let projectFolder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static func text(_ path: String) throws -> String {
        try String(contentsOf: projectFolder.appendingPathComponent(path), encoding: .utf8)
    }

    /// From `struct <name>: View {` to the next closing brace in the first column.
    static func view(_ name: String) throws -> String {
        let source = try text("Maths Quest/ContentView.swift")
        guard let start = source.range(of: "\nstruct \(name): View {"),
              let end = source.range(of: "\n}\n", range: start.upperBound..<source.endIndex) else {
            throw FBASourceError.missing(name)
        }
        return String(source[start.lowerBound..<end.upperBound])
    }

    /// From `opening` to the next line that closes it at the same indent.
    static func function(_ opening: String, inView name: String) throws -> String {
        let body = try view(name)
        guard let start = body.range(of: "    " + opening),
              let end = body.range(of: "\n    }\n", range: start.upperBound..<body.endIndex) else {
            throw FBASourceError.missing("\(name).\(opening)")
        }
        return String(body[start.lowerBound..<end.upperBound])
    }

    static func position(of needle: String, in text: String, after offset: Int = 0) throws -> Int {
        let from = text.index(text.startIndex, offsetBy: offset)
        guard let range = text.range(of: needle, range: from..<text.endIndex) else {
            throw FBASourceError.missing(needle)
        }
        return text.distance(from: text.startIndex, to: range.lowerBound)
    }
}
