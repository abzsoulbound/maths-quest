//
//  FeedbackBatchFBFUITests.swift
//  Maths QuestUITests
//

import XCTest

/// User feedback, batch FB-F, as a player sees it: "Surprise me" in the Shop (FB-09).
///
/// - It sits under "Background Colours", above the colours, and fits the width of the screen.
/// - With another colour unlocked, it picks one of the unlocked colours, never the one in use, says which, and the
///   points don't change. The test taps it twice, then chooses Blue 80% again, as every saved game used for testing has.
/// - With no other colour unlocked, it is turned off and a line says how to use it.
///
/// Which of the two the test sees depends on the game saved on the device; between them the four test simulators have
/// both. Nothing is bought: only "Surprise me" and an unlocked colour are tapped.
@MainActor
final class FeedbackBatchFBFUITests: MathsQuestUITestCase {

    static let largestText = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

    static let buttonTitle = "Surprise me"
    static let needsAnotherColour = "Unlock another colour to use Surprise me."
    static let messagePrefix = "Surprise! Your background is now "
    /// The colour every test save starts with.
    static let startingColour = "Blue, 80 percent"

    private struct Swatch {
        let label: String
        let value: String
        let frame: CGRect
        /// How the Surprise me message names it: "Red, 70 percent" is "Red 70%".
        var messageName: String {
            label.replacingOccurrences(of: ", ", with: " ").replacingOccurrences(of: " percent", with: "%")
        }
    }

    func testSurpriseMePicksAnUnlockedColourOrSaysWhyItCant() throws {
        try checkSurpriseMe(largestText: false)
    }

    func testSurpriseMePicksAnUnlockedColourOrSaysWhyItCantAtTheLargestTextSize() throws {
        try checkSurpriseMe(largestText: true)
    }

    // MARK: -

    private func swatches() -> [Swatch] {
        guard let root = try? app.snapshot() else { return [] }
        var found: [Swatch] = []
        func visit(_ element: XCUIElementSnapshot) {
            if element.elementType == .button,
               element.label.wholeMatch(of: #/[A-Za-z ]+, \d+ percent/#) != nil {
                found.append(Swatch(label: element.label, value: element.value as? String ?? "", frame: element.frame))
            }
            element.children.forEach(visit)
        }
        visit(root)
        return found
    }

    private func value(of label: String) -> String {
        button(label).value as? String ?? ""
    }

    private var surpriseMessage: XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", Self.messagePrefix)).firstMatch
    }

    private func checkSurpriseMe(largestText: Bool) throws {
        continueAfterFailure = true
        if largestText {
            extraLaunchArguments = Self.largestText
        }
        let size = largestText ? ", largest text" : ""
        launchApp()
        openFromSidebar("Shop")
        let heading = text("Background Colours")
        XCTAssertTrue(heading.waitForExistence(timeout: 10), "The Shop didn't open.")
        let surprise = button(Self.buttonTitle)
        XCTAssertTrue(surprise.waitForExistence(timeout: 5), "The Shop has no Surprise me button.")
        let pointsBefore = currentPoints()

        let before = swatches()
        XCTAssertEqual(before.count, 60, "15 colours at 4 strengths each.")
        let unlocked = before.filter { $0.value == "Unlocked" }
        let selected = before.filter { $0.value == "Selected" }
        attachText("Shop\(size): colours before", before.map { "\($0.label): \($0.value)" }.joined(separator: "\n"))
        attachScreenshot("Shop\(size), before")

        // Where it is: under the heading, above the first colour, across the screen.
        let window = windowFrame
        XCTAssertGreaterThanOrEqual(surprise.frame.minX, window.minX - 0.5, "Surprise me starts off the screen.")
        XCTAssertLessThanOrEqual(surprise.frame.maxX, window.maxX + 0.5, "Surprise me runs off the screen.")
        XCTAssertGreaterThanOrEqual(surprise.frame.minY, heading.frame.maxY - 0.5, "Surprise me is above the heading.")
        if let firstColour = before.map(\.frame).min(by: { $0.minY < $1.minY }) {
            XCTAssertLessThanOrEqual(surprise.frame.maxY, firstColour.minY + 0.5, "Surprise me is below a colour.")
        }
        attachText("Shop\(size): frames", """
            Heading \(heading.frame)
            Surprise me \(surprise.frame)
            Window \(window)
            Unlocked, not in use: \(unlocked.map(\.label))
            In use: \(selected.map(\.label))
            """)

        guard !unlocked.isEmpty else {
            // Nothing else unlocked: turned off, with the reason under it.
            XCTAssertFalse(surprise.isEnabled, "Surprise me can be tapped with no other colour unlocked.")
            let reason = text(Self.needsAnotherColour)
            XCTAssertTrue(reason.exists, "Nothing says why Surprise me is turned off.")
            XCTAssertGreaterThanOrEqual(reason.frame.minY, surprise.frame.maxY - 0.5, "The reason isn't under the button.")
            XCTAssertGreaterThanOrEqual(reason.frame.minX, window.minX - 0.5, "The reason starts off the screen.")
            XCTAssertLessThanOrEqual(reason.frame.maxX, window.maxX + 0.5, "The reason runs off the screen.")
            surprise.tap()
            XCTAssertFalse(surpriseMessage.waitForExistence(timeout: 2), "Surprise me changed the colour while turned off.")
            XCTAssertEqual(swatches().map(\.value), before.map(\.value), "A colour changed.")
            assertPoints(pointsBefore)
            attachText("Shop\(size): reason", "\(reason.label) at \(reason.frame)")
            attachScreenshot("Shop\(size), Surprise me turned off")
            return
        }

        // Another colour unlocked: turned on, with no reason shown.
        XCTAssertTrue(surprise.isEnabled, "Surprise me is turned off with \(unlocked.count) other colours unlocked.")
        XCTAssertFalse(text(Self.needsAnotherColour).exists, "The turned-off line shows while Surprise me is on.")

        let canPick = Set((unlocked + selected).map(\.label))
        var current = selected.first?.label
        var lastMessage = ""
        for tapNumber in 1...2 {
            tap(surprise)
            let message = surpriseMessage
            XCTAssertTrue(message.waitForExistence(timeout: 5), "Tap \(tapNumber) on Surprise me said nothing.")
            _ = waitQuickly(timeout: 3) { message.label != lastMessage }
            let said = message.label
            lastMessage = said
            _ = waitForFrameToSettle(of: message)
            attachScreenshot("Shop\(size), after Surprise me \(tapNumber)")

            let now = swatches()
            let nowSelected = now.filter { $0.value == "Selected" }
            XCTAssertEqual(nowSelected.count, 1, "After tap \(tapNumber): \(nowSelected.map(\.label))")
            guard let pick = nowSelected.first else { continue }
            attachText("Shop\(size): tap \(tapNumber)", "Said: \(said)\nNow in use: \(pick.label)\nBefore: \(current ?? "none")")
            XCTAssertTrue(canPick.contains(pick.label), "Surprise me chose \(pick.label), which wasn't unlocked.")
            XCTAssertNotEqual(pick.label, current, "Surprise me chose the colour already in use.")
            XCTAssertEqual(said, "\(Self.messagePrefix)\(pick.messageName).", "The message names another colour.")
            if let current {
                XCTAssertEqual(value(of: current), "Unlocked", "\(current) didn't go back to unlocked.")
            }
            // Nothing was unlocked, locked or bought.
            XCTAssertEqual(now.filter { $0.value != "Selected" && $0.value != "Unlocked" }.map(\.label),
                           before.filter { $0.value != "Selected" && $0.value != "Unlocked" }.map(\.label),
                           "Surprise me unlocked or locked a colour.")
            XCTAssertGreaterThanOrEqual(message.frame.minY, surprise.frame.maxY - 0.5, "The message isn't under the button.")
            XCTAssertLessThanOrEqual(message.frame.maxX, window.maxX + 0.5, "The message runs off the screen.")
            assertPoints(pointsBefore)
            current = pick.label
        }

        // Back to the starting colour, which is unlocked, so choosing it is free.
        if current != Self.startingColour {
            tap(button(Self.startingColour))
            _ = waitQuickly(timeout: 3) { value(of: Self.startingColour) == "Selected" }
        }
        XCTAssertEqual(value(of: Self.startingColour), "Selected", "The starting colour couldn't be chosen again.")
        assertPoints(pointsBefore)
    }
}
