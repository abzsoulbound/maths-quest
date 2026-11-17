//
//  MathsQuestUITestSupport.swift
//  Maths QuestUITests
//

import UIKit
import XCTest

/// Launch, navigation, answering and waiting helpers shared by the Maths Quest UI tests.
///
/// Every UI test keeps to these safety rules:
/// - The app is launched with `launchArgument`. In Debug builds that points Firestore at the local
///   emulator with an in-memory cache (`UITestFirestore` in AppDelegate.swift), so nothing a test
///   does can reach the live feedback collection.
/// - Taps go through `tap(_:)`, which refuses anything that would buy or restore a purchase or send
///   feedback. The simulator's StoreKit is the local RemoveAds.storekit once the unit tests have run
///   on it; xcodebuild doesn't give UI tests the scheme's StoreKit file itself.
/// - Adverts are Google's test ads, which only Debug builds use. A test ad is closed with its own ×
///   and nothing inside an ad is ever tapped.
/// - Each test launches the app afresh and finishes well within the 180 seconds before the first
///   interstitial is allowed, so an interstitial never appears in the middle of a test.
class MathsQuestUITestCase: XCTestCase {
    /// Must match `UITestFirestore.launchArgument` in AppDelegate.swift.
    static let launchArgument = "-MathsQuestUITesting"

    static let feedbackPrivacyReminder = "Please don't write your name, school, address or anything else about you."

    static let activities: [Int: [String]] = [
        1: ["Counting", "Addition", "Subtraction"],
        2: ["Multiplication", "Division", "Shapes"],
        3: ["Fractions", "Measurement", "Time"],
        4: ["Decimals", "Geometry", "Money"],
        5: ["Percentages", "Statistics", "Volume"],
        6: ["Algebra", "Probability", "Ratios"],
    ]

    /// The messages that flash up for a second after Enter.
    enum Feedback: String, CaseIterable {
        case correct = "Correct!"
        case incorrect = "Incorrect. Try Again!"
        case unanswered = "Please enter an answer!"
    }

    /// Every message an activity can show after Enter.
    static let feedbackMessages = Feedback.allCases.map(\.rawValue) + [
        "Correct number, but wrong unit!",
        "Make sure to write your answer with 2 decimal places. E.g. £1.23",
        "Please enter a number!",
        "Please enter a valid number!",
        "Please enter valid numbers.",
        "Use a decimal point.",
        "Write it without a comma.",
        // Batch FB-B: answers in the wrong form, asked for again.
        "Fill in both boxes.",
        "Put each number in its own box.",
        "Type just the number, then pick the unit.",
        "Type just the number.",
        "Turning it doesn't change what shape it is.",
        // Stage 9C Batch 2: Algebra answers that are right but written another way, or equal but not simplified,
        // asked for again. As VoiceOver reads them, which is how XCUITest finds them.
        "Write x as a whole number, without a decimal point.",
        "Write each number as a whole number, without a decimal point.",
        "In algebra, leave out the times sign. Write 2x, not 2 times x.",
        "In algebra, leave out the times sign. Write 3x, not 3 times x.",
        "In algebra, write the number before the x, like 2x.",
        "In algebra, write the number before the x, like 3x.",
        "That's equal, but it needs simplifying further.",
        "That's true, but it needs simplifying further.",
        "That's the question. It needs simplifying.",
        "That's the question. It needs expanding.",
        "That's the question. Work out what x is.",
    ]

    enum UITestSafetyError: Error {
        /// Release builds show real adverts and use the live Firestore project.
        case notADebugBuild
    }

    var app: XCUIApplication!

    /// Added to the launch arguments, such as a text size for the app to use.
    var extraLaunchArguments: [String] = []

    override func setUpWithError() throws {
        continueAfterFailure = false
        #if !DEBUG
        throw UITestSafetyError.notADebugBuild
        #endif
    }

    // MARK: - Launching

    @MainActor
    @discardableResult
    func launchApp(file: StaticString = #filePath, line: UInt = #line) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [Self.launchArgument, "-AppleLanguages", "(en)", "-AppleLocale", "en_GB"] + extraLaunchArguments
        app.launch()
        self.app = app
        // Two loading screens come before the main menu.
        XCTAssertTrue(button("Year 1").waitForExistence(timeout: 30),
                      "The main menu didn't appear after launch.", file: file, line: line)
        return app
    }

    // MARK: - Finding things

    @MainActor
    func button(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    @MainActor
    func text(_ label: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    @MainActor
    var homeButton: XCUIElement { app.buttons["house"] }

    /// The gear at the top right of screens that have a home button.
    @MainActor
    var settingsButton: XCUIElement { app.buttons["gearshape"] }

    /// The sidebar button at the top left of screens without a home button.
    @MainActor
    var menuButton: XCUIElement { app.buttons["line.horizontal.3"] }

    @MainActor
    var sidebarCloseButton: XCUIElement { app.buttons["xmark.circle.fill"] }

    @MainActor
    var pointsLabel: XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Points: '")).firstMatch
    }

    @MainActor
    var answerField: XCUIElement { app.textFields.firstMatch }

    /// Enter on an activity screen. Its label has a trailing space.
    @MainActor
    var enterButton: XCUIElement { button("Enter ") }

    /// Year 6 Probability's Enter has no trailing space, so this matches both.
    @MainActor
    var anyEnterButton: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Enter'")).firstMatch
    }

    @MainActor
    var skipButton: XCUIElement { button("Skip Question") }

    @MainActor
    var feedbackPrivacyReminder: XCUIElement { text(Self.feedbackPrivacyReminder) }

    // MARK: - Tapping safely

    /// Why a UI test must never tap a control with this label, or nil if it's safe.
    static func refusalReason(forLabel label: String, onFeedbackScreen: Bool) -> String? {
        let label = label.trimmingCharacters(in: .whitespaces)
        if label.hasPrefix("Buy") {
            return "it would start a purchase"
        }
        if label == "Restore Purchases" {
            return "it would ask the App Store to restore purchases"
        }
        if onFeedbackScreen && label == "Enter" {
            return "it would send feedback"
        }
        return nil
    }

    /// Taps `element` once it exists, unless it could spend money or send feedback.
    @MainActor
    func tap(_ element: XCUIElement, timeout: TimeInterval = 10,
             file: StaticString = #filePath, line: UInt = #line) {
        guard element.waitForExistence(timeout: timeout) else {
            XCTFail("\(element) never appeared.", file: file, line: line)
            return
        }
        let label = element.label
        if let reason = Self.refusalReason(forLabel: label, onFeedbackScreen: feedbackPrivacyReminder.exists) {
            XCTFail("Refusing to tap \"\(label)\": \(reason).", file: file, line: line)
            return
        }
        // XCUITest still calls a control behind the keyboard hittable, and the tap lands on a key.
        if keyboardCoversTapPoint(of: element) {
            XCTFail("Refusing to tap \"\(label)\" at \(element.frame): the keyboard at \(keyboardGlassFrame) covers its middle.",
                    file: file, line: line)
            return
        }
        element.tap()
    }

    // MARK: - The keyboard

    @MainActor
    var keyboard: XCUIElement { app.keyboards.firstMatch }

    /// Whether the on-screen keyboard is up. It can exist while parked below the screen.
    @MainActor
    var keyboardIsOnScreen: Bool {
        keyboard.exists && keyboard.frame.height > 0 && keyboard.frame.minY < windowFrame.maxY
    }

    /// Whether the keyboard on screen has a space bar, as the iPhone letter keyboards do and the number
    /// and decimal pads don't. Always false on an iPad, where XCUITest finds no key named "space".
    @MainActor
    var keyboardHasLetters: Bool {
        keyboard.keys["space"].exists
    }

    /// The keyboard as a player sees it. On iOS 26 its glass panel is drawn higher than the frame
    /// XCUITest reports, so a control just above that frame can still be under the glass. Measured
    /// from screenshots on the iOS 26 simulators, the glass starts this many points higher: 17 for the
    /// iPhone number and decimal pads, 44 for an iPhone letter keyboard (its suggestion bar isn't in
    /// the reported frame) and 54 for any iPad keyboard. An iPad has no separate number pad: it shows
    /// the full keyboard, suggestion bar and all, for numbers as well as letters.
    @MainActor
    var keyboardGlassFrame: CGRect {
        var frame = keyboard.frame
        if #available(iOS 26, *) {
            let overhang: CGFloat
            if UIDevice.current.userInterfaceIdiom == .pad {
                overhang = 54
            } else if keyboardHasLetters {
                overhang = 44
            } else {
                overhang = 17
            }
            frame.origin.y -= overhang
            frame.size.height += overhang
        }
        return frame
    }

    /// Whether the keyboard's glass covers any of `element`.
    @MainActor
    func keyboardOverlaps(_ element: XCUIElement) -> Bool {
        guard keyboardIsOnScreen else {
            return false
        }
        let overlap = keyboardGlassFrame.intersection(element.frame)
        return !overlap.isNull && overlap.width * overlap.height >= 1
    }

    /// Whether a tap on `element`, which lands in its middle, would hit the keyboard instead.
    @MainActor
    func keyboardCoversTapPoint(of element: XCUIElement) -> Bool {
        guard keyboardIsOnScreen else {
            return false
        }
        let frame = element.frame
        return keyboardGlassFrame.contains(CGPoint(x: frame.midX, y: frame.midY))
    }

    /// Puts the cursor in `field`, types `text` and waits for the on-screen keyboard to finish sliding
    /// in. In the simulator, with its hardware keyboard connected (the default), focusing a field
    /// leaves the on-screen keyboard parked below the screen until something is typed. Returns false
    /// if it still doesn't come up.
    @MainActor
    func showKeyboard(typing text: String, into field: XCUIElement,
                      file: StaticString = #filePath, line: UInt = #line) -> Bool {
        focus(field, file: file, line: line)
        field.typeText(text)
        guard waitQuickly(timeout: 5, until: { keyboardIsOnScreen }) else {
            return false
        }
        waitForKeyboardToSettle(file: file, line: line)
        return true
    }

    /// Hides the keyboard the way a player can on a question screen without answering: by tapping the
    /// background. The number pad has no Return. The tap goes 2 points in from the left edge, outside
    /// the working-out canvas (5 points in) and long questions (11), level with the centred answer
    /// field, which the question screens keep above the keyboard.
    @MainActor
    func hideKeyboardByTappingBackground(file: StaticString = #filePath, line: UInt = #line) {
        guard keyboardIsOnScreen else {
            return
        }
        let point = CGVector(dx: windowFrame.minX + 2, dy: min(answerField.frame.midY, keyboardGlassFrame.minY - 20))
        app.coordinate(withNormalizedOffset: .zero).withOffset(point).tap()
        XCTAssertTrue(waitQuickly(timeout: 5) { !keyboardIsOnScreen },
                      "Tapping the background at \(point) didn't hide the keyboard.", file: file, line: line)
    }

    /// Waits for the keyboard to finish sliding in, so its frame can be compared with the controls.
    @MainActor
    func waitForKeyboardToSettle(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitForFrameToSettle(of: keyboard), "The keyboard didn't settle.", file: file, line: line)
    }

    // MARK: - Waiting

    /// Polls `condition` as often as accessibility snapshots allow. `waitForExistence` only checks
    /// about once a second, which can miss the messages that are on screen for a single second.
    @MainActor
    func waitQuickly(timeout: TimeInterval, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() {
                return true
            }
        } while Date() < deadline
        return false
    }

    /// Waits until `element` has stopped moving for `steadyFor` seconds, as when the keyboard slides
    /// in or the screen turns.
    @MainActor
    func waitForFrameToSettle(of element: XCUIElement, timeout: TimeInterval = 5,
                              steadyFor steady: TimeInterval = 0.5) -> Bool {
        var previous = CGRect.null
        var unchangedSince = Date()
        return waitQuickly(timeout: timeout) {
            let frame = element.frame
            if frame != previous {
                previous = frame
                unchangedSince = Date()
            }
            return Date().timeIntervalSince(unchangedSince) >= steady
        }
    }

    /// Waits without polling for anything. Only for the rewarded ad, which loads in the background
    /// with nothing on screen to show when it's ready.
    func pause(_ seconds: TimeInterval) {
        let nothing = XCTestExpectation(description: "Pause for \(seconds)s")
        _ = XCTWaiter.wait(for: [nothing], timeout: seconds)
    }

    // MARK: - Navigation

    @MainActor
    func assertOnMainMenu(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(text("Maths Quest").waitForExistence(timeout: 10), "Not on the main menu.", file: file, line: line)
        for year in 1...6 {
            XCTAssertTrue(button("Year \(year)").exists, "The main menu has no Year \(year) button.", file: file, line: line)
        }
        XCTAssertTrue(menuButton.exists, "The main menu has no sidebar button.", file: file, line: line)
        XCTAssertTrue(pointsLabel.exists, "The main menu doesn't show the points.", file: file, line: line)
    }

    @MainActor
    func assertOnYearMenu(_ year: Int, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(text("Year \(year)").waitForExistence(timeout: 10), "Year \(year) didn't open.", file: file, line: line)
        for activity in Self.activities[year] ?? [] {
            XCTAssertTrue(button(activity).exists, "Year \(year) has no \(activity) button.", file: file, line: line)
        }
        XCTAssertTrue(homeButton.exists, "Year \(year) has no home button.", file: file, line: line)
        XCTAssertTrue(settingsButton.exists, "Year \(year) has no settings button.", file: file, line: line)
    }

    /// From the main menu.
    @MainActor
    func openYear(_ year: Int, file: StaticString = #filePath, line: UInt = #line) {
        tap(button("Year \(year)"), file: file, line: line)
        assertOnYearMenu(year, file: file, line: line)
    }

    /// From a year menu.
    @MainActor
    func openActivity(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        tap(button(name), file: file, line: line)
        assertOnActivityScreen(name, file: file, line: line)
    }

    /// Not every activity has an answer field on every question (Measurement, for example, sometimes
    /// asks for a drag instead), but they all have Enter, the points, home and settings.
    @MainActor
    func assertOnActivityScreen(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(anyEnterButton.waitForExistence(timeout: 10), "\(name) didn't open: no Enter button.", file: file, line: line)
        XCTAssertTrue(pointsLabel.exists, "\(name) doesn't show the points.", file: file, line: line)
        XCTAssertTrue(homeButton.exists, "\(name) has no home button.", file: file, line: line)
        XCTAssertTrue(settingsButton.exists, "\(name) has no settings button.", file: file, line: line)
        XCTAssertFalse(button(name).exists, "Still on the year menu after opening \(name).", file: file, line: line)
    }

    @MainActor
    func goHome(file: StaticString = #filePath, line: UInt = #line) {
        tap(homeButton, file: file, line: line)
        assertOnMainMenu(file: file, line: line)
    }

    @MainActor
    func openSidebar(file: StaticString = #filePath, line: UInt = #line) {
        tap(menuButton, file: file, line: line)
        XCTAssertTrue(sidebarCloseButton.waitForExistence(timeout: 5), "The sidebar didn't open.", file: file, line: line)
    }

    /// A sidebar entry. While the sidebar is open, the main menu's own Year buttons are still behind
    /// it but disabled, so only an enabled button counts.
    @MainActor
    func sidebarButton(_ title: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let matches = app.buttons.matching(NSPredicate(format: "label == %@", title)).allElementsBoundByIndex
        guard let enabled = matches.first(where: { $0.isEnabled }) else {
            XCTFail("The sidebar has no enabled \(title) button.", file: file, line: line)
            return button(title)
        }
        return enabled
    }

    @MainActor
    func openFromSidebar(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        openSidebar(file: file, line: line)
        tap(sidebarButton(title, file: file, line: line), file: file, line: line)
        XCTAssertTrue(sidebarCloseButton.waitForNonExistence(timeout: 5),
                      "The sidebar stayed open after choosing \(title).", file: file, line: line)
    }

    // MARK: - Points

    @MainActor
    func currentPoints(file: StaticString = #filePath, line: UInt = #line) -> Int {
        XCTAssertTrue(pointsLabel.waitForExistence(timeout: 10), "The points aren't on screen.", file: file, line: line)
        let label = pointsLabel.label
        // From 1,000 points the label groups digits for the locale ("Points: 5,001").
        let digits = label.dropFirst("Points: ".count).filter { $0 != "," }
        guard let points = Int(digits) else {
            XCTFail("Couldn't read the points from \"\(label)\".", file: file, line: line)
            return Int.min
        }
        return points
    }

    /// Waits briefly for the points to settle on `expected`, then checks them.
    @MainActor
    func assertPoints(_ expected: Int, file: StaticString = #filePath, line: UInt = #line) {
        _ = waitQuickly(timeout: 3) { currentPoints(file: file, line: line) == expected }
        XCTAssertEqual(currentPoints(file: file, line: line), expected, "Wrong points.", file: file, line: line)
    }

    // MARK: - Answering

    /// What's typed in a field. An empty field reports its placeholder as its value.
    @MainActor
    func typedText(in field: XCUIElement) -> String {
        let value = field.value as? String ?? ""
        return value == field.placeholderValue ? "" : value
    }

    /// Puts the keyboard focus in `field`. Tapping near its right-hand edge leaves the cursor after
    /// the centred text, so deleting clears all of it.
    @MainActor
    func focus(_ field: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(field.waitForExistence(timeout: 10), "No answer field.", file: file, line: line)
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertTrue(waitQuickly(timeout: 5) { field.hasKeyboardFocus },
                      "The answer field didn't take the keyboard focus.", file: file, line: line)
    }

    @MainActor
    func replaceText(in field: XCUIElement, with text: String,
                     file: StaticString = #filePath, line: UInt = #line) {
        focus(field, file: file, line: line)
        for _ in 0..<3 {
            let existing = typedText(in: field)
            if existing.isEmpty {
                break
            }
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
            if !typedText(in: field).isEmpty {
                // The cursor wasn't at the end. Put it there and try again.
                focus(field, file: file, line: line)
            }
        }
        XCTAssertEqual(typedText(in: field), "", "Couldn't clear the answer field.", file: file, line: line)
        field.typeText(text)
        XCTAssertEqual(typedText(in: field), text, "The answer field doesn't show what was typed.", file: file, line: line)
    }

    /// The feedback message on screen, if any. It's drawn many times over as an outline, so only the
    /// first copy is read.
    @MainActor
    func visibleFeedback() -> String? {
        let messages = Feedback.allCases.map(\.rawValue)
        let message = app.staticTexts.matching(NSPredicate(format: "label IN %@", messages)).firstMatch
        // A snapshot rather than `label`, because the message can vanish between the two calls.
        return (try? message.snapshot())?.label
    }

    /// Taps Enter once the previous message has gone, and checks the message it brings up. If the
    /// keyboard is up, Enter is tapped with it up, as a player would; `tap(_:)` fails if the keyboard
    /// covers Enter.
    @MainActor
    func pressEnter(expecting expected: Feedback, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitQuickly(timeout: 5) { visibleFeedback() == nil && enterButton.isEnabled },
                      "Enter didn't become available again.", file: file, line: line)
        tap(enterButton, file: file, line: line)
        var shown: String?
        _ = waitQuickly(timeout: 3) {
            shown = visibleFeedback()
            return shown != nil
        }
        XCTAssertEqual(shown, expected.rawValue, "Unexpected message after Enter.", file: file, line: line)
    }

    @MainActor
    func answer(_ text: String, expecting expected: Feedback,
                file: StaticString = #filePath, line: UInt = #line) {
        replaceText(in: answerField, with: text, file: file, line: line)
        pressEnter(expecting: expected, file: file, line: line)
    }

    /// After a correct answer or a skip, the next question appears a second later with an empty
    /// answer field.
    @MainActor
    func waitForNextQuestion(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitQuickly(timeout: 5) { typedText(in: answerField).isEmpty && visibleFeedback() == nil },
                      "The next question didn't appear.", file: file, line: line)
    }

    /// Gets the Skip button showing, by giving two wrong answers to a question whose answer is a
    /// single number under 99.
    @MainActor
    func answerWronglyTwice(file: StaticString = #filePath, line: UInt = #line) {
        answer("99", expecting: .incorrect, file: file, line: line)
        XCTAssertFalse(skipButton.exists, "Skip appeared after one wrong answer.", file: file, line: line)
        pressEnter(expecting: .incorrect, file: file, line: line)
        XCTAssertTrue(skipButton.waitForExistence(timeout: 5), "Skip didn't appear after two wrong answers.", file: file, line: line)
    }

    // MARK: - Reading questions

    /// The question on screen as VoiceOver reads it, such as "7 + 2" or "7 minus 2".
    @MainActor
    func question(using symbol: String, file: StaticString = #filePath, line: UInt = #line) -> String {
        let pattern = "[0-9]+ \(NSRegularExpression.escapedPattern(for: symbol)) [0-9]+"
        let element = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", pattern)).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 10), "No \"a \(symbol) b\" question on screen.", file: file, line: line)
        return element.label
    }

    /// The two numbers in the question on screen, such as 7 and 2 in "7 + 2" or "7 times 2".
    @MainActor
    func operands(using symbol: String, file: StaticString = #filePath, line: UInt = #line) -> (Int, Int) {
        let parts = question(using: symbol, file: file, line: line).components(separatedBy: " \(symbol) ")
        guard parts.count == 2, let first = Int(parts[0]), let second = Int(parts[1]) else {
            XCTFail("Couldn't read the question \(parts).", file: file, line: line)
            return (0, 0)
        }
        return (first, second)
    }

    /// The number hidden by "_" in a Year 1 Counting question, worked out from where it sits among
    /// the ten consecutive numbers shown. VoiceOver reads the "_" as "missing number".
    @MainActor
    func missingCountingNumber(file: StaticString = #filePath, line: UInt = #line) -> Int {
        let gapLabel = "missing number"
        let cell = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "([0-9]+|\(gapLabel))"))
        XCTAssertTrue(cell.firstMatch.waitForExistence(timeout: 10), "No Counting question on screen.", file: file, line: line)
        let cells = staticTextSnapshots()
            .filter { $0.label == gapLabel || Int($0.label) != nil }
            .sorted { a, b in
                abs(a.frame.midY - b.frame.midY) > 1 ? a.frame.midY < b.frame.midY : a.frame.minX < b.frame.minX
            }
        guard cells.count == 10, let gap = cells.firstIndex(where: { $0.label == gapLabel }),
              let anchor = cells.firstIndex(where: { $0.label != gapLabel }), let anchorValue = Int(cells[anchor].label) else {
            XCTFail("Couldn't read the Counting question: \(cells.map(\.label)).", file: file, line: line)
            return -1
        }
        let start = anchorValue - anchor
        for (index, cell) in cells.enumerated() where index != gap {
            XCTAssertEqual(Int(cell.label), start + index, "The Counting numbers aren't in order.", file: file, line: line)
        }
        return start + gap
    }

    /// Every static text on screen, read in one go.
    @MainActor
    func staticTextSnapshots() -> [XCUIElementSnapshot] {
        guard let root = try? app.snapshot() else {
            return []
        }
        var found: [XCUIElementSnapshot] = []
        var unvisited = [root]
        while let element = unvisited.popLast() {
            if element.elementType == .staticText {
                found.append(element)
            }
            unvisited.append(contentsOf: element.children)
        }
        return found
    }

    // MARK: - Skipping with the rewarded test ad

    /// Taps Skip Question until the app offers the rewarded test ad. The ad loads in the background
    /// after launch, so it may not be ready the first time; the app then says so and loads it again.
    @MainActor
    func tapSkipUntilAdIsOffered(timeout: TimeInterval = 60,
                                 file: StaticString = #filePath, line: UInt = #line) throws {
        let offer = app.alerts["Skip this question?"]
        let notReady = app.alerts["Ad Not Ready"]
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            tap(skipButton, file: file, line: line)
            XCTAssertTrue(waitQuickly(timeout: 10) { offer.exists || notReady.exists || !skipButton.exists },
                          "Nothing happened after tapping Skip Question.", file: file, line: line)
            if offer.exists {
                return
            }
            guard notReady.exists else {
                XCTFail("Skip worked without an advert, which means Remove Ads has been bought in this simulator. "
                        + "Erase the simulator, or delete the app, to clear the local StoreKit purchase.",
                        file: file, line: line)
                return
            }
            tap(notReady.buttons["OK"], file: file, line: line)
            XCTAssertTrue(notReady.waitForNonExistence(timeout: 5), "\"Ad Not Ready\" didn't close.", file: file, line: line)
            guard Date() < deadline else {
                throw XCTSkip("Google's rewarded test ad didn't load within \(Int(timeout)) seconds. It needs a network connection.")
            }
            pause(5)
        }
    }

    /// Waits for the rewarded test ad to finish, then closes it with its ×.
    ///
    /// Google's test ad labels itself "Test mode". In the simulator its native "Close Advertisement"
    /// button stays disabled; once "Reward granted" appears, the × is the small square immediately to
    /// its right. Some versions of the ad expose that square as an unlabelled element and others as a
    /// "Close" button. Nothing else in the ad is touched, and if that square can't be found
    /// unambiguously the test fails rather than guessing.
    @MainActor
    func closeRewardedTestAd(file: StaticString = #filePath, line: UInt = #line) {
        let testMode = text("Test mode")
        XCTAssertTrue(testMode.waitForExistence(timeout: 30),
                      "The rewarded ad isn't labelled as a Google test ad.", file: file, line: line)
        attachScreenshot("Rewarded test ad")

        let rewardGranted = text("Reward granted")
        XCTAssertTrue(rewardGranted.waitForExistence(timeout: 90),
                      "The test ad never granted its reward.", file: file, line: line)

        let nativeClose = app.buttons["Close Advertisement"]
        if nativeClose.exists && nativeClose.isEnabled {
            nativeClose.tap()
        } else {
            let reward = rewardGranted.frame
            let closeControls = closeControlSnapshots().filter {
                let frame = $0.frame
                return (18...40).contains(frame.width) && (18...40).contains(frame.height)
                    && frame.minX >= reward.maxX - 1 && abs(frame.midY - reward.midY) <= 6
            }
            guard closeControls.count == 1, let close = closeControls.first else {
                let found = closeControls.map { "\($0.frame)" }
                add(XCTAttachment(string: app.debugDescription))
                XCTFail("Couldn't find the test ad's × unambiguously next to \"Reward granted\" \(reward): \(found).",
                        file: file, line: line)
                return
            }
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: close.frame.midX, dy: close.frame.midY))
                .tap()
        }
        XCTAssertTrue(testMode.waitForNonExistence(timeout: 15), "The test ad didn't close.", file: file, line: line)
    }

    /// The app's unlabelled elements and buttons, one for each frame.
    @MainActor
    private func closeControlSnapshots() -> [XCUIElementSnapshot] {
        guard let root = try? app.snapshot() else {
            return []
        }
        var found: [XCUIElementSnapshot] = []
        var unvisited = [root]
        while let element = unvisited.popLast() {
            if [.other, .button].contains(element.elementType) && !found.contains(where: { $0.frame == element.frame }) {
                found.append(element)
            }
            unvisited.append(contentsOf: element.children)
        }
        return found
    }

    // MARK: - Layout and evidence

    @MainActor
    var windowFrame: CGRect { app.windows.firstMatch.frame }

    /// Checks that `element` is entirely inside `bounds` and, for a control, that it can be tapped.
    @MainActor
    func assertFullyVisible(_ element: XCUIElement, _ name: String, within bounds: CGRect, tappable: Bool = true,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "\(name) isn't on screen.", file: file, line: line)
        let frame = element.frame
        XCTAssertTrue(bounds.insetBy(dx: -0.5, dy: -0.5).contains(frame),
                      "\(name) at \(frame) isn't entirely within \(bounds).", file: file, line: line)
        if tappable {
            XCTAssertTrue(element.isHittable, "\(name) can't be tapped.", file: file, line: line)
        }
    }

    @MainActor
    func assertNoOverlap(_ frames: [(name: String, frame: CGRect)],
                         file: StaticString = #filePath, line: UInt = #line) {
        for (index, first) in frames.enumerated() {
            for second in frames[(index + 1)...] {
                let overlap = first.frame.intersection(second.frame)
                XCTAssertTrue(overlap.isNull || overlap.width * overlap.height < 1,
                              "\(first.name) \(first.frame) overlaps \(second.name) \(second.frame).", file: file, line: line)
            }
        }
    }

    /// The scrolling space below the header that holds the question. Anything scrolled above its top is hidden
    /// under the header. The working-out pad is a scroll view too, inside this one, so this is the biggest.
    /// Snapshots rather than `frame`, because a scroll view can go between counting them and reading one, as the
    /// keyboard's do when Enter hides it.
    @MainActor
    var questionAreaFrame: CGRect {
        app.scrollViews.allElementsBoundByIndex.compactMap { try? $0.snapshot().frame }
            .max { $0.width * $0.height < $1.width * $1.height } ?? .null
    }

    /// The part of the question area a player can see: below the header and above the keyboard's glass.
    @MainActor
    var visibleQuestionArea: CGRect {
        var area = questionAreaFrame.intersection(windowFrame)
        if keyboardIsOnScreen {
            area.size.height = max(0, min(area.maxY, keyboardGlassFrame.minY) - area.minY)
        }
        return area
    }

    /// Every answer box and Enter are entirely in view and can be tapped.
    @MainActor
    func assertAnswerAndEnterInView(_ when: String, file: StaticString = #filePath, line: UInt = #line) {
        let area = visibleQuestionArea
        for (index, field) in app.textFields.allElementsBoundByIndex.enumerated() {
            assertFullyVisible(field, "\(when): answer box \(index + 1)", within: area, file: file, line: line)
        }
        assertFullyVisible(anyEnterButton, "\(when): Enter", within: area, file: file, line: line)
    }

    /// The header has its own strip above the question area, so nothing in the question can run into it.
    @MainActor
    func assertHeaderClearOfTheQuestion(_ when: String, file: StaticString = #filePath, line: UInt = #line) {
        let area = questionAreaFrame
        for (name, element) in [("Home", homeButton), ("The points", pointsLabel), ("Settings", settingsButton)] {
            XCTAssertLessThanOrEqual(element.frame.maxY, area.minY + 0.5,
                                     "\(when): \(name) at \(element.frame) reaches into the question area \(area).",
                                     file: file, line: line)
        }
    }

    /// The label and frame of `element` once it has stopped moving, or, if it goes first, where it was last seen.
    /// Nil if it was never seen.
    @MainActor
    func settledFrame(of element: XCUIElement,
                      steadyFor steady: TimeInterval = 0.2) -> (label: String, frame: CGRect)? {
        var last: (label: String, frame: CGRect)?
        var unchangedSince = Date()
        _ = waitQuickly(timeout: 3) {
            guard let snapshot = try? element.snapshot() else {
                return last != nil
            }
            if snapshot.frame != last?.frame {
                last = (snapshot.label, snapshot.frame)
                unchangedSince = Date()
            }
            return Date().timeIntervalSince(unchangedSince) >= steady
        }
        return last
    }

    /// The whole screen: a screenshot of just the app leaves out the keyboard.
    @MainActor
    func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func attachText(_ name: String, _ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

extension XCUIElement {
    var hasKeyboardFocus: Bool {
        (value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }
}
