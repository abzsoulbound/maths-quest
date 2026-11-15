//
//  FeedbackBatchFBAUITests.swift
//  Maths QuestUITests
//

import XCTest

/// User feedback, batch FB-A, as a player sees it.
///
/// - Feedback sends a message once, however many times Enter is tapped, and doesn't send spaces alone (FB-02). These
///   two tests tap Feedback's Enter, so they run only against a Firestore emulator started for them on this Mac:
///
///       node firebase/tests/feedback-emulator.mjs
///       TEST_RUNNER_MATHSQUEST_FEEDBACK_EMULATOR_PORT=<the port it prints> xcodebuild test ... \
///         -only-testing:"Maths QuestUITests/FeedbackBatchFBAUITests"
///
///   Without that port, or if it's 8080, or if nothing that answers like the emulator is there, they're skipped and
///   Enter is never tapped. The app is told the port with a launch option that only DEBUG builds have, always on
///   127.0.0.1. The emulator enforces the real firestore.rules, and the test counts the documents that arrived.
/// - Feedback says no one will reply, and the line can be seen, at the default and the largest text size (FB-05).
/// - Volume asks for "1,000" again without the comma, and it neither scores nor counts towards Skip (FB-01).
/// - Measurement says "Correct number, but wrong unit!" for the right number with the wrong unit or none. It still
///   counts towards Skip, as before (FB-01).
/// - Both new messages can be read in full, at the default and the largest text size.
///
/// Every answer is worked out here from what the screen shows, not taken from the app.
@MainActor
final class FeedbackBatchFBAUITests: MathsQuestUITestCase {

    /// The DEBUG-only launch option, followed by a port, that points Firestore at an emulator on 127.0.0.1.
    nonisolated static let firestorePortArgument = "-MathsQuestFirestorePort"
    static let noReplyNotice = "You won't get a reply to messages sent here."
    static let largestText = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

    var feedbackField: XCUIElement {
        app.textViews.matching(NSPredicate(format: "label == 'Your feedback'")).firstMatch
    }

    /// Feedback's Enter. Only the two emulator tests tap it, and never with `tap(_:)`, which refuses.
    var feedbackEnter: XCUIElement { button("Enter") }

    // MARK: - FB-02: one message, however often Enter is tapped

    func testFeedbackSendsOneMessageHoweverOftenEnterIsTapped() async throws {
        let emulator = try await FeedbackEmulator.started()
        try await emulator.clear()
        let before = try await emulator.messages()
        XCTAssertEqual(before, [], "The emulator still has messages after clearing it.")

        try openFeedback(using: emulator)
        let message = "FB-A UI test, first message \(UUID().uuidString)"
        try type(message)

        // Five taps, as fast as XCUITest allows: a tap, a double tap and two more.
        try assertSafeToSend(using: emulator)
        feedbackEnter.tap()
        feedbackEnter.doubleTap()
        feedbackEnter.tap()
        feedbackEnter.tap()
        attachScreenshot("After five taps on Enter")

        var arrived = try await emulator.waitForMessages(atLeast: 1, timeout: 20)
        // Anything else would have been sent by now.
        try await Task.sleep(nanoseconds: 3_000_000_000)
        arrived = try await emulator.messages()
        attachText("Messages in the emulator after five taps", arrived.joined(separator: "\n"))
        XCTAssertEqual(arrived, [message], "Five taps on Enter didn't send the message exactly once.")
        XCTAssertEqual(typedText(in: feedbackField), "", "The box wasn't emptied after the message was sent.")
        // After it's sent, Enter on the empty box asks for a message. If every tap came while it was sending, the
        // thank-you stays.
        let shown = banner(["Please type a message first.", "Thank you! Your message was sent."])
        XCTAssertTrue(shown.waitForExistence(timeout: 5), "No message under the box after sending.")

        // A new message is sent as usual.
        let second = "FB-A UI test, second message \(UUID().uuidString)"
        try type(second)
        try assertSafeToSend(using: emulator)
        feedbackEnter.tap()
        XCTAssertTrue(banner(["Thank you! Your message was sent."]).waitForExistence(timeout: 15),
                      "The second message wasn't thanked for.")
        arrived = try await emulator.waitForMessages(atLeast: 2, timeout: 10)
        try await Task.sleep(nanoseconds: 2_000_000_000)
        arrived = try await emulator.messages()
        attachText("Messages in the emulator at the end", arrived.joined(separator: "\n"))
        XCTAssertEqual(Set(arrived), [message, second])
        XCTAssertEqual(arrived.count, 2, "Two messages were sent, so two should have arrived.")
    }

    func testFeedbackDoesNotSendSpacesAlone() async throws {
        let emulator = try await FeedbackEmulator.started()
        try await emulator.clear()
        try openFeedback(using: emulator)
        try type("   ")
        try assertSafeToSend(using: emulator)
        feedbackEnter.tap()
        XCTAssertTrue(banner(["Please type a message first."]).waitForExistence(timeout: 5),
                      "Spaces alone weren't refused.")
        try await Task.sleep(nanoseconds: 3_000_000_000)
        let arrived = try await emulator.messages()
        XCTAssertEqual(arrived, [], "Spaces alone were sent.")
    }

    // MARK: - FB-05: no reply

    func testFeedbackSaysThereWillBeNoReply() throws {
        try checkTheNoReplyNotice(largestText: false)
    }

    func testFeedbackSaysThereWillBeNoReplyAtTheLargestTextSize() throws {
        try checkTheNoReplyNotice(largestText: true)
    }

    /// The notice is under the privacy reminder, below the header and above the box. If the heading has to scroll,
    /// as at the largest text on a small iPhone, it's scrolled into view first. Enter isn't tapped.
    private func checkTheNoReplyNotice(largestText: Bool) throws {
        continueAfterFailure = true
        if largestText {
            extraLaunchArguments = Self.largestText
        }
        let size = largestText ? ", largest text" : ""
        launchApp()
        openFromSidebar("Feedback")
        XCTAssertTrue(feedbackPrivacyReminder.waitForExistence(timeout: 10), "Feedback didn't open.")
        let notice = text(Self.noReplyNotice)
        XCTAssertTrue(notice.waitForExistence(timeout: 5), "Feedback doesn't say there will be no reply.")
        XCTAssertTrue(feedbackField.waitForExistence(timeout: 5), "Feedback has no text box.")

        let headerBottom = max(pointsLabel.frame.maxY, menuButton.frame.maxY)
        func noticeIsInView() -> Bool {
            let frame = notice.frame
            return !frame.isEmpty && windowFrame.insetBy(dx: -0.5, dy: -0.5).contains(frame)
                && frame.minY >= headerBottom - 0.5 && frame.maxY <= feedbackField.frame.minY + 0.5
        }
        var swipes = 0
        while !noticeIsInView() && swipes < 3 && app.scrollViews.firstMatch.exists {
            app.scrollViews.firstMatch.swipeUp()
            swipes += 1
            _ = waitForFrameToSettle(of: notice)
        }
        attachScreenshot("Feedback\(size)")
        attachText("Feedback\(size): frames", """
            Header bottom \(headerBottom)
            Reminder \(feedbackPrivacyReminder.frame)
            Notice \(notice.frame)
            Text box \(feedbackField.frame)
            Window \(windowFrame)
            Swipes to bring the notice into view: \(swipes)
            """)
        XCTAssertTrue(noticeIsInView(), "The no-reply notice at \(notice.frame) can't be seen in full.")
        XCTAssertGreaterThanOrEqual(notice.frame.minY, feedbackPrivacyReminder.frame.maxY - 0.5,
                                    "The notice isn't under the privacy reminder.")
    }

    // MARK: - FB-01: Volume, "1,000"

    func testVolumeAsksForAThousandWithoutAComma() throws {
        try checkTheVolumeComma(largestText: false)
    }

    func testVolumeAsksForAThousandWithoutACommaAtTheLargestTextSize() throws {
        try checkTheVolumeComma(largestText: true)
    }

    private func checkTheVolumeComma(largestText: Bool) throws {
        if largestText {
            extraLaunchArguments = Self.largestText
        }
        let size = largestText ? ", largest text" : ""
        let pattern = #"^A (cube|cuboid)\. Width [0-9]+ centimetres, length [0-9]+ centimetres, height [0-9]+ centimetres\.$"#
        let volume = try findQuestion(in: "Volume", inYear: 5) { () -> Int? in
            guard answerField.waitForExistence(timeout: 10) else { return nil }
            let picture = labelled(pattern)
            guard picture.waitForExistence(timeout: 1),
                  let edges = picture.label.firstMatch(of: #/Width (\d+) centimetres, length (\d+) centimetres, height (\d+) centimetres/#),
                  let width = Int(edges.1), let length = Int(edges.2), let height = Int(edges.3) else { return nil }
            return width * length * height
        }
        attachText("Volume question\(size)", "Volume \(volume)")
        let start = currentPoints()

        focus(answerField)
        let commaKey = keyboard.keys[","].exists
        answerField.typeText("1,000")
        attachScreenshot("Volume\(size): 1,000 typed")
        attachText("Volume keyboard\(size)", "The keyboard has a comma key: \(commaKey). The box shows \"\(typedText(in: answerField))\".")
        guard typedText(in: answerField) == "1,000" else {
            throw XCTSkip("\"1,000\" can't be typed here (comma key: \(commaKey)), so a child can't type it either.")
        }

        // Twice, because two counted wrong answers would bring up Skip.
        for attempt in 1...2 {
            enterAndCheckTheMessage("Write it without a comma.", "Volume\(size), comma \(attempt)")
            assertPoints(start)
            XCTAssertFalse(skipButton.exists, "Skip appeared after \"1,000\" was asked for again \(attempt) times.")
        }
        XCTAssertEqual(typedText(in: answerField), "1,000", "The answer was cleared, so it can't be corrected.")

        replaceText(in: answerField, with: "\(volume)")
        pressEnter(expectingMessage: "Correct!")
        assertPoints(start + 1)
    }

    // MARK: - FB-01: Measurement, the right number with the wrong unit

    func testMeasurementSaysTheNumberIsRightButTheUnitIsWrong() throws {
        try checkTheUnitMessage(largestText: false)
    }

    /// At the largest text, only the typed steps: the unit wheel isn't needed to show the new message.
    func testMeasurementSaysTheNumberIsRightButTheUnitIsWrongAtTheLargestTextSize() throws {
        try checkTheUnitMessage(largestText: true)
    }

    private func checkTheUnitMessage(largestText: Bool) throws {
        if largestText {
            extraLaunchArguments = Self.largestText
        }
        let size = largestText ? ", largest text" : ""
        let sizes = ["m": 1000, "cm": 10, "mm": 1, "kg": 1000, "g": 1, "l": 1000, "ml": 1]
        let pattern = "^Convert [0-9]+ (m|cm|mm|kg|g|l|ml) into (m|cm|mm|kg|g|l|ml)$"
        let (amount, from, to) = try findQuestion(in: "Measurement", inYear: 3) { () -> (Int, String, String)? in
            guard answerField.waitForExistence(timeout: 10) else { return nil }
            let question = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", pattern)).firstMatch
            guard question.waitForExistence(timeout: 1) else { return nil }
            let words = question.label.split(separator: " ").map(String.init)
            guard words.count == 5, let amount = Int(words[1]) else { return nil }
            return (amount, words[2], words[4])
        }
        guard let fromSize = sizes[from], let toSize = sizes[to] else {
            return XCTFail("Unknown units in \"Convert \(amount) \(from) into \(to)\".")
        }
        let converted = amount * fromSize / toSize
        attachText("Measurement question\(size)", "Convert \(amount) \(from) into \(to): \(converted) \(to)")
        let start = currentPoints()

        // The right number with no unit picked.
        replaceText(in: answerField, with: "\(converted)")
        enterAndCheckTheMessage("Correct number, but wrong unit!", "Measurement\(size), no unit")
        assertPoints(start)
        XCTAssertFalse(skipButton.exists, "Skip appeared after one wrong answer.")

        if largestText {
            // A wrong number is just wrong, and it's the second wrong answer, so Skip appears, as before.
            replaceText(in: answerField, with: "\(converted + 1)")
            pressEnter(expectingMessage: "Incorrect. Try Again!")
            assertPoints(start)
            XCTAssertTrue(skipButton.waitForExistence(timeout: 5), "Skip didn't appear after two wrong answers.")
            return
        }

        // With the unit it's converted from. Still wrong, and the second wrong answer brings up Skip, as before.
        pickUnit(from)
        enterAndCheckTheMessage("Correct number, but wrong unit!", "Measurement, the unit it's converted from")
        assertPoints(start)
        XCTAssertTrue(skipButton.waitForExistence(timeout: 5), "Skip didn't appear after two wrong answers.")

        // The right unit with a wrong number is just wrong.
        pickUnit(to)
        replaceText(in: answerField, with: "\(converted + 1)")
        pressEnter(expectingMessage: "Incorrect. Try Again!")
        assertPoints(start)

        replaceText(in: answerField, with: "\(converted)")
        pressEnter(expectingMessage: "Correct!")
        assertPoints(start + 1)
    }

    /// The screen, read once while a message shows.
    private struct MessageSample {
        /// Seconds since Enter was tapped, at the middle of the snapshot.
        let time: TimeInterval
        let parts: QuestionParts
    }

    /// How long the keyboard, the message, Enter and the answer boxes must have stayed put for a snapshot to count as
    /// taken while nothing was moving, as in the Stage 9B tests (`Stage9BInteractionChecks.stillFor`).
    private static let stillFor: TimeInterval = 0.15

    /// Taps Enter and checks that `expected` follows and can be read: below the header, and above the keyboard's glass
    /// if the keyboard is up. The message shows for a second, too briefly for `waitForExistence`, so the screen is read
    /// as often as snapshots allow while it shows, as the Stage 9B tests do. Only snapshots taken while nothing was
    /// moving are judged: the whole message with the keyboard down, and its first line with the keyboard up, which is
    /// the line the app keeps above the keyboard. A screenshot is attached, because a frame check can't see text cut
    /// short with "…".
    private func enterAndCheckTheMessage(_ expected: String, _ when: String,
                                         file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitQuickly(timeout: 5) { shownMessage() == nil && enterButton.isEnabled },
                      "\(when): Enter didn't become available again.", file: file, line: line)
        let overhang = keyboardIsOnScreen ? keyboard.frame.minY - keyboardGlassFrame.minY : 0
        tap(enterButton, file: file, line: line)
        let start = Date()
        var samples: [MessageSample] = []
        var sawMessage = false
        var tookScreenshot = false
        while Date().timeIntervalSince(start) < 3 {
            let before = Date()
            let parts = questionParts()
            guard !parts.area.isNull else {
                continue // The snapshot failed.
            }
            let time = (before.timeIntervalSince(start) + Date().timeIntervalSince(start)) / 2
            if !tookScreenshot, let previous = samples.last, previous.parts.message != nil, parts.message != nil,
               nothingMoved(previous.parts, parts) {
                attachScreenshot("\(when): the message")
                tookScreenshot = true
            }
            samples.append(MessageSample(time: time, parts: parts))
            if parts.message != nil {
                sawMessage = true
            } else if sawMessage {
                break
            }
        }
        attachText("\(when): snapshots after Enter", messageLog(samples, overhang: overhang))

        guard let first = samples.compactMap(\.parts.message).first else {
            return XCTFail("\(when): \"\(expected)\" wasn't seen in \(samples.count) snapshots over the 3 seconds after "
                           + "Enter.", file: file, line: line)
        }
        XCTAssertEqual(first.label, expected, "\(when): unexpected message after Enter.", file: file, line: line)
        let still = stillSamples(samples)
        guard !still.isEmpty else {
            return XCTFail("UNVERIFIED: \(when): the message was never seen standing still, so whether it can be read "
                           + "couldn't be checked.", file: file, line: line)
        }
        var problems: [String] = []
        for sample in still {
            guard let message = sample.parts.message else {
                continue
            }
            let area = visibleArea(of: sample.parts, overhang: overhang)
            var frame = message.frame
            var part = "the message"
            if sample.parts.keyboardUp {
                frame.size.height = min(frame.height, firstLineHeight(in: sample.parts))
                part = "the message's first line"
            }
            if !isInView(frame, area) {
                problems.append(String(format: "%.2f s: ", sample.time)
                                + "\(part) \(frame) is \(percentInView(frame, area))% in view of \(area)")
            }
        }
        XCTAssertTrue(problems.isEmpty, "\(when): the message can't be read in full: "
                      + problems.joined(separator: "; "), file: file, line: line)
    }

    /// Whether the keyboard, the message, Enter and the answer boxes are where they were.
    private func nothingMoved(_ a: QuestionParts, _ b: QuestionParts) -> Bool {
        func same(_ x: CGRect?, _ y: CGRect?) -> Bool {
            switch (x, y) {
            case (nil, nil):
                return true
            case let (x?, y?):
                if x.isNull || y.isNull {
                    return x.isNull && y.isNull
                }
                return abs(x.minX - y.minX) <= 0.5 && abs(x.minY - y.minY) <= 0.5
                    && abs(x.width - y.width) <= 0.5 && abs(x.height - y.height) <= 0.5
            default:
                return false
            }
        }
        return same(a.keyboard, b.keyboard) && same(a.message?.frame, b.message?.frame) && same(a.enter, b.enter)
            && a.answerBoxes.count == b.answerBoxes.count
            && zip(a.answerBoxes, b.answerBoxes).allSatisfy { same($0, $1) }
    }

    /// The samples taken while nothing was moving: each that agrees with every sample in the `stillFor` seconds before
    /// it, all with the message showing.
    private func stillSamples(_ samples: [MessageSample]) -> [MessageSample] {
        samples.indices.compactMap { index in
            let sample = samples[index]
            guard sample.parts.message != nil else {
                return nil
            }
            var earlier = index - 1
            while earlier >= 0, samples[earlier].parts.message != nil, nothingMoved(samples[earlier].parts, sample.parts) {
                if sample.time - samples[earlier].time >= Self.stillFor {
                    return sample
                }
                earlier -= 1
            }
            return nil
        }
    }

    /// The height of the message's first line: bold, at 7.5% of the content's width, which is the screen's up to 600
    /// points, as in `AnswerFeedbackText`.
    private func firstLineHeight(in parts: QuestionParts) -> CGFloat {
        let width = min(parts.window.isNull ? parts.area.width : parts.window.width, 600)
        return UIFont.systemFont(ofSize: width * 0.075, weight: .bold).lineHeight
    }

    private func messageLog(_ samples: [MessageSample], overhang: CGFloat) -> String {
        let lines = samples.map { sample -> String in
            let parts = sample.parts
            return [
                String(format: "%.2f s", sample.time),
                parts.keyboardUp ? "keyboard \(parts.keyboard)" : "keyboard down",
                "message " + (parts.message.map { "\"\($0.label)\" \($0.frame)" } ?? "none"),
                "boxes \(parts.answerBoxes)",
                "Enter " + (parts.enter.map { "\($0)" } ?? "none"),
                "visible \(visibleArea(of: parts, overhang: overhang))",
            ].joined(separator: " | ")
        }
        return (["Keyboard glass \(overhang) pt above the keyboard XCUITest reports. Times are from Enter."] + lines)
            .joined(separator: "\n")
    }

    // MARK: - Feedback helpers

    private func openFeedback(using emulator: FeedbackEmulator) throws {
        extraLaunchArguments = [Self.firestorePortArgument, String(emulator.port)]
        launchApp()
        openFromSidebar("Feedback")
        XCTAssertTrue(feedbackPrivacyReminder.waitForExistence(timeout: 10), "Feedback didn't open.")
        XCTAssertTrue(feedbackField.waitForExistence(timeout: 5), "Feedback has no text box.")
    }

    private func type(_ message: String) throws {
        focus(feedbackField)
        feedbackField.typeText(message)
        XCTAssertEqual(typedText(in: feedbackField), message, "The box doesn't show what was typed.")
    }

    /// Feedback's Enter is tapped only if the app was launched pointing at this emulator, the app has the option
    /// that makes it use that port, and the keyboard doesn't cover Enter, so the tap can't land on a key.
    private func assertSafeToSend(using emulator: FeedbackEmulator) throws {
        guard app.launchArguments.contains(Self.launchArgument),
              let index = app.launchArguments.firstIndex(of: Self.firestorePortArgument),
              app.launchArguments.indices.contains(index + 1), app.launchArguments[index + 1] == String(emulator.port),
              emulator.port != 8080 else {
            XCTFail("The app wasn't launched pointing at the emulator: \(app.launchArguments).")
            throw FeedbackEmulator.Problem(description: "Not safe to send.")
        }
        try FeedbackEmulator.checkTheAppUsesThePortOption()
        XCTAssertTrue(feedbackEnter.waitForExistence(timeout: 5), "Feedback has no Enter.")
        guard !keyboardCoversTapPoint(of: feedbackEnter) else {
            XCTFail("The keyboard at \(keyboardGlassFrame) covers Enter at \(feedbackEnter.frame).")
            throw FeedbackEmulator.Problem(description: "Enter is under the keyboard.")
        }
    }

    /// The message under the box, read out as one of `messages`.
    private func banner(_ messages: [String]) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", messages)).firstMatch
    }

    // MARK: - Question helpers, as in Stage9CFeedbackUITests

    struct QuestionNotFound: Error, CustomStringConvertible {
        let description: String
    }

    /// When the app was last launched. The interstitial ad can show on a menu 3 minutes after launch, so the app is
    /// launched again well before then rather than going back through the menus.
    private var lastLaunch: Date?

    private func findQuestion<Question>(in activity: String, inYear year: Int, attempts: Int = 60,
                                        file: StaticString = #filePath, line: UInt = #line,
                                        until read: () -> Question?) throws -> Question {
        for _ in 1...attempts {
            if let lastLaunch, Date().timeIntervalSince(lastLaunch) < 90 {
                goHome(file: file, line: line)
            } else {
                launchApp(file: file, line: line)
                lastLaunch = Date()
            }
            openYear(year, file: file, line: line)
            openActivity(activity, file: file, line: line)
            if let found = read() {
                return found
            }
        }
        let problem = QuestionNotFound(description: "\(attempts) \(activity) questions in a row weren't the one wanted.")
        XCTFail(problem.description, file: file, line: line)
        throw problem
    }

    private func labelled(_ pattern: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label MATCHES %@", pattern)).firstMatch
    }

    private func shownMessage() -> String? {
        let message = app.staticTexts.matching(NSPredicate(format: "label IN %@", Self.feedbackMessages)).firstMatch
        return (try? message.snapshot())?.label
    }

    private func pressEnter(expectingMessage expected: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitQuickly(timeout: 5) { shownMessage() == nil && enterButton.isEnabled },
                      "Enter didn't become available again.", file: file, line: line)
        tap(enterButton, file: file, line: line)
        var shown: String?
        _ = waitQuickly(timeout: 3) {
            shown = shownMessage()
            return shown != nil
        }
        XCTAssertEqual(shown, expected, "Unexpected message after Enter.", file: file, line: line)
    }

    private func pickUnit(_ unit: String, file: StaticString = #filePath, line: UInt = #line) {
        hideKeyboardByTappingBackground(file: file, line: line)
        let wheel = app.pickerWheels.firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout: 5), "No unit wheel.", file: file, line: line)
        wheel.adjust(toPickerWheelValue: unit)
        XCTAssertTrue(waitQuickly(timeout: 3) {
            let value = wheel.value as? String ?? ""
            return value == unit || value.hasPrefix(unit + ",")
        }, "The unit wheel shows \"\(wheel.value as? String ?? "")\", not \(unit).", file: file, line: line)
    }
}

// MARK: - The emulator

/// The Firestore emulator that firebase/tests/feedback-emulator.mjs started on this Mac for these tests. Every
/// request goes to 127.0.0.1 on the port it printed, never 8080.
struct FeedbackEmulator {
    static let environmentKey = "MATHSQUEST_FEEDBACK_EMULATOR_PORT"
    /// The app's own project, which its Firebase SDK names in every request. The script uses it too.
    static let project = "maths-mania-8d613"

    struct Problem: Error, CustomStringConvertible {
        let description: String
    }

    let port: Int

    private var base: String { "http://127.0.0.1:\(port)" }
    private var documents: String { "\(base)/v1/projects/\(Self.project)/databases/(default)/documents" }

    /// The emulator on the port the script printed, or a skip if there isn't one.
    static func started() async throws -> FeedbackEmulator {
        guard let value = ProcessInfo.processInfo.environment[environmentKey] else {
            throw XCTSkip("Start the emulator with `node firebase/tests/feedback-emulator.mjs` and pass the port it prints as TEST_RUNNER_\(environmentKey).")
        }
        guard let port = Int(value), (1024...65535).contains(port), port != 8080 else {
            throw XCTSkip("\(environmentKey) is \"\(value)\", which isn't a port the script picks. 8080 is never used.")
        }
        let emulator = FeedbackEmulator(port: port)
        let reply = try? await emulator.request("GET", emulator.base)
        guard let reply, reply.status == 200,
              String(decoding: reply.body, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "Ok" else {
            throw XCTSkip("Nothing that answers like the Firestore emulator is on 127.0.0.1:\(port).")
        }
        return emulator
    }

    /// The app under test is built from this checkout. Before Feedback's Enter is tapped, check that it has the
    /// option that points it at this emulator, so nothing goes to 127.0.0.1:8080 instead.
    static func checkTheAppUsesThePortOption() throws {
        let appDelegate = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Maths Quest").appendingPathComponent("AppDelegate.swift")
        guard let source = try? String(contentsOf: appDelegate, encoding: .utf8) else {
            throw XCTSkip("Couldn't read \(appDelegate.path) to check the app uses the emulator's port, so nothing was sent.")
        }
        let option = "static let portArgument = \"\(FeedbackBatchFBAUITests.firestorePortArgument)\""
        guard source.contains(option), source.contains("settings.host = host(forLaunchArguments: arguments)") else {
            throw XCTSkip("The app doesn't have the emulator port option, so nothing was sent.")
        }
    }

    /// Deletes every document in the emulator, which only ever holds what these tests sent.
    func clear() async throws {
        let reply = try await request("DELETE", "\(base)/emulator/v1/projects/\(Self.project)/databases/(default)/documents")
        guard reply.status == 200 else {
            throw Problem(description: "Clearing the emulator failed with \(reply.status).")
        }
    }

    /// The text of every feedback message in the emulator. "Bearer owner" reads past the rules, which let nobody
    /// read feedback; only the emulator accepts it.
    func messages() async throws -> [String] {
        let reply = try await request("GET", "\(documents)/feedbacks?pageSize=300", headers: ["Authorization": "Bearer owner"])
        guard reply.status == 200 else {
            throw Problem(description: "Reading the emulator failed with \(reply.status).")
        }
        let json = try JSONSerialization.jsonObject(with: reply.body) as? [String: Any] ?? [:]
        let found = json["documents"] as? [[String: Any]] ?? []
        return found.map { document in
            let fields = document["fields"] as? [String: Any]
            let text = fields?["text"] as? [String: Any]
            return text?["stringValue"] as? String ?? "<no text>"
        }
    }

    func waitForMessages(atLeast count: Int, timeout: TimeInterval) async throws -> [String] {
        let deadline = Date().addingTimeInterval(timeout)
        var found = try await messages()
        while found.count < count && Date() < deadline {
            try await Task.sleep(nanoseconds: 500_000_000)
            found = try await messages()
        }
        return found
    }

    private func request(_ method: String, _ address: String,
                         headers: [String: String] = [:]) async throws -> (status: Int, body: Data) {
        guard let url = URL(string: address), url.host == "127.0.0.1", url.port == port, port != 8080 else {
            throw Problem(description: "Refusing to send to \(address).")
        }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = method
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let (body, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, body)
    }
}
