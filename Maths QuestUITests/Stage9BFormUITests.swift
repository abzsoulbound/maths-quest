//
//  Stage9BFormUITests.swift
//  Maths QuestUITests
//

import XCTest

/// Stage 9B's fixes to the Shop and Settings, checked in the app as a child sees them.
///
/// D1: a message about a colour is part of the page, just under that colour's row, so it can never cover a colour, and
/// it stays until the child does something else. D2 and D3: the points stay where the main menu has them, and the Spend
/// Points and Name cards stay below them, with the keyboard down or up and at the largest text size. Every other screen
/// without a Home button has its points in the same place too.
///
/// Nothing is bought, saved or sent: the only colours tapped cost more points than the player has, and Settings' and
/// Feedback's Enter are never tapped. On a simulator, whose game is thrown away, the Shop test first spends points with
/// Spend Points if the player could afford every colour, so that there is one to tap.
final class Stage9BFormUITests: MathsQuestUITestCase {

    /// A shop colour as VoiceOver reads it, such as "Red, 100 percent" with the value "Locked, 100 points".
    private struct Swatch {
        let label: String
        let colour: String
        let percent: Int
        /// What it costs, if it's locked and not free.
        let price: Int?
        let frame: CGRect
    }

    private static let swatchName = #/(?<colour>[A-Za-z ]+), (?<percent>\d+) percent/#
    private static let lockedPrice = #/Locked, (?<price>\d+) points/#
    /// The price of the dearest colours, the 100% ones.
    private static let dearest = 100

    // MARK: - D1: the Shop's messages

    /// Tapping a colour the player can't afford says so just under that colour's row, giving the price and the points,
    /// without covering any colour or the header. The message stays until the child types a number. Near the bottom of
    /// the Shop, the page scrolls to show it. Nothing is bought.
    @MainActor
    func testNotEnoughPointsShowsUnderTheColourAndCoversNothing() throws {
        continueAfterFailure = true
        launchApp()
        openFromSidebar("Shop")
        XCTAssertTrue(text("Background Colours").waitForExistence(timeout: 10), "The Shop didn't open.")
        let points = try pointsBelowTheDearestColour()

        // A colour at the top of the Shop.
        guard let top = unaffordable(points: points).first else {
            XCTFail("No locked colour in view costs more than \(points) points.")
            return
        }
        tap(button(top.label))
        let message = notEnoughPoints
        XCTAssertTrue(message.waitForExistence(timeout: 5), "Tapping \(top.label) with \(points) points showed nothing.")
        _ = waitForFrameToSettle(of: message)
        attachScreenshot("Shop: \(top.label) costs more than \(points) points")
        checkMessage(message, about: top, points: points)

        // Before Stage 9B the message went after 2 seconds.
        pause(3)
        XCTAssertTrue(message.exists, "The message went on its own.")

        // Typing a number starts again, so the message goes.
        let keyboardCameUp = showKeyboard(typing: "1", into: pointsField)
        XCTAssertTrue(message.waitForNonExistence(timeout: 5), "Typing a number in Spend Points left the message.")
        if keyboardCameUp {
            hideKeyboardByTappingBackground()
        }

        // A colour at the bottom of the Shop, whose message is below the screen until the page scrolls to it.
        for _ in 1...3 {
            app.swipeUp()
        }
        _ = waitForFrameToSettle(of: text("Background Colours"))
        guard let bottom = unaffordable(points: points).max(by: { $0.frame.maxY < $1.frame.maxY }) else {
            XCTFail("No colour the player can't afford is in view at the bottom of the Shop.")
            return
        }
        tap(button(bottom.label))
        XCTAssertTrue(message.waitForExistence(timeout: 5), "Tapping \(bottom.label) with \(points) points showed nothing.")
        _ = waitForFrameToSettle(of: message, timeout: 5, steadyFor: 0.5)
        attachScreenshot("Shop: \(bottom.label) costs more than \(points) points")
        checkMessage(message, about: bottom, points: points)

        assertPoints(points)
        for swatch in [top, bottom] {
            XCTAssertEqual(button(swatch.label).value as? String, "Locked, \(swatch.price ?? -1) points",
                           "\(swatch.label) was bought.")
        }
    }

    // MARK: - D2 and D3: the points with the keyboard up

    /// The Shop and Settings have their points where the main menu has them, and the Spend Points and Name cards stay
    /// below the points, with the keyboard down and up. Before Stage 9B the keyboard pushed "Spend Points" and "Name"
    /// up into the points. Nothing is spent or saved: Enter isn't tapped.
    @MainActor
    func testThePointsStayPutAboveTheShopAndSettingsWithTheKeyboardUp() throws {
        try checkThePointsStayPut(largestText: false)
    }

    /// The same at the largest accessibility text size.
    @MainActor
    func testThePointsStayPutAboveTheShopAndSettingsAtTheLargestTextSize() throws {
        try checkThePointsStayPut(largestText: true)
    }

    /// Every screen without a Home button has its points where the main menu has them. Nothing is bought or sent.
    @MainActor
    func testThePointsAreInTheSamePlaceOnEveryScreenWithoutHome() throws {
        continueAfterFailure = true
        launchApp()
        guard let mainMenu = settledFrame(of: pointsLabel)?.frame else {
            XCTFail("The main menu has no points.")
            return
        }
        for screen in ["Shop", "Feedback", "Information", "Remove Ads", "Settings"] {
            openFromSidebar(screen)
            XCTAssertTrue(text(screen).waitForExistence(timeout: 10), "\(screen) didn't open.")
            assertSamePlace(settledFrame(of: pointsLabel)?.frame ?? .null, mainMenu,
                            "\(screen): the points aren't where the main menu has them:")
            assertBelowTheHeader([("The title", text(screen))], on: screen)
            attachScreenshot(screen)
        }
    }

    @MainActor
    private func checkThePointsStayPut(largestText: Bool) throws {
        continueAfterFailure = true
        if largestText {
            extraLaunchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        launchApp()
        let size = largestText ? ", largest text" : ""
        guard let mainMenu = settledFrame(of: pointsLabel)?.frame else {
            XCTFail("The main menu has no points.")
            return
        }
        var keyboardsShown = 0
        let forms: [(screen: String, heading: String, field: XCUIElement, typing: String)] = [
            ("Shop", "Spend Points", pointsField, "1"),
            ("Settings", "Name", nameField, "A"),
        ]
        for (screen, heading, field, typing) in forms {
            let name = screen + size
            openFromSidebar(screen)
            XCTAssertTrue(field.waitForExistence(timeout: 10), "\(name) has no text box.")
            let parts = [(heading, text(heading)), ("The text box", field), ("Enter", button("Enter"))]
            assertSamePlace(settledFrame(of: pointsLabel)?.frame ?? .null, mainMenu,
                            "\(name): the points aren't where the main menu has them:")
            assertBelowTheHeader(parts, on: name)
            attachScreenshot(name)

            guard showKeyboard(typing: typing, into: field) else {
                attachText("\(name) keyboard", "No on-screen keyboard appeared, so \(name) wasn't checked with it up.")
                continue
            }
            keyboardsShown += 1
            _ = waitForFrameToSettle(of: field)
            attachScreenshot("\(name), keyboard up")
            attachText("\(name), keyboard up: frames", (parts + [("The points", pointsLabel)])
                .map { "\($0.0): \($0.1.frame)" }.joined(separator: "\n") + "\nKeyboard glass: \(keyboardGlassFrame)")
            assertSamePlace(pointsLabel.frame, mainMenu, "\(name): the points moved when the keyboard came up:")
            assertBelowTheHeader(parts, on: "\(name), keyboard up")
            XCTAssertFalse(keyboardOverlaps(field), "\(name): the keyboard covers the text box at \(field.frame).")
            XCTAssertFalse(keyboardCoversTapPoint(of: button("Enter")), "\(name): the keyboard covers Enter.")
            hideKeyboardByTappingBackground()
        }
        if keyboardsShown == 0 {
            throw XCTSkip("No on-screen keyboard appeared on the Shop or Settings.")
        }
    }

    // MARK: - Helpers

    @MainActor
    private var pointsField: XCUIElement {
        app.textFields.matching(NSPredicate(format: "placeholderValue == 'Points to spend' OR label == 'Points to spend'"))
            .firstMatch
    }

    @MainActor
    private var nameField: XCUIElement {
        app.textFields.matching(NSPredicate(format: "label == 'Name'")).firstMatch
    }

    @MainActor
    private var notEnoughPointsMessages: XCUIElementQuery {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Not enough points!'"))
    }

    @MainActor
    private var notEnoughPoints: XCUIElement { notEnoughPointsMessages.firstMatch }

    /// Each "Not enough points!" message on the page, once. On iOS 26 XCUITest also lists a message's icon and words
    /// underneath the message itself, as it does inside the points chip, although VoiceOver reads the message as one
    /// item (`aBannerIsReadAsOneItem`). So a match inside another match is part of that message, not a second one,
    /// while two messages, which would sit in different places on the page, are both counted.
    @MainActor
    private func notEnoughPointsBanners() -> [XCUIElementSnapshot] {
        guard let root = try? app.snapshot() else {
            return []
        }
        var found: [XCUIElementSnapshot] = []
        var unvisited = [root]
        while let element = unvisited.popLast() {
            if element.elementType == .staticText, element.label.hasPrefix("Not enough points!") {
                found.append(element)
                continue
            }
            unvisited.append(contentsOf: element.children)
        }
        return found
    }

    private static func pointsText(_ count: Int) -> String {
        count == 1 ? "1 point" : "\(count.formatted()) points"
    }

    /// The player's points, after spending some with Spend Points if they could afford every colour. Only a simulator
    /// spends them, as its game is thrown away after the tests. Elsewhere the test is skipped instead.
    @MainActor
    private func pointsBelowTheDearestColour() throws -> Int {
        let points = currentPoints()
        guard points >= Self.dearest else {
            return points
        }
        #if targetEnvironment(simulator)
        let spent = points - (Self.dearest - 1)
        let left = Self.dearest - 1
        _ = showKeyboard(typing: "\(spent)", into: pointsField)
        tap(button("Enter"))
        assertPoints(left)
        let said = "\(Self.pointsText(spent)) taken. You have \(Self.pointsText(left)) left."
        XCTAssertTrue(text(said).waitForExistence(timeout: 5), "Spend Points didn't say \"\(said)\".")
        attachText("Points spent first", "The player had \(points) points, enough for every colour, so \(spent) were spent.")
        return left
        #else
        throw XCTSkip("The player has \(points) points, enough for every colour, so tapping one would buy it.")
        #endif
    }

    /// Every colour in the Shop, in the order VoiceOver reads them, with where each is now.
    @MainActor
    private func swatches() -> [Swatch] {
        guard let root = try? app.snapshot() else {
            return []
        }
        var found: [Swatch] = []
        func visit(_ element: XCUIElementSnapshot) {
            if element.elementType == .button, let name = element.label.wholeMatch(of: Self.swatchName),
               let percent = Int(name.percent) {
                let value = element.value as? String ?? ""
                let price = value.wholeMatch(of: Self.lockedPrice).flatMap { Int($0.price) }
                found.append(Swatch(label: element.label, colour: String(name.colour), percent: percent, price: price,
                                    frame: element.frame))
            }
            element.children.forEach(visit)
        }
        visit(root)
        return found
    }

    /// The locked colours entirely in view that cost more than `points`, in the order VoiceOver reads them.
    @MainActor
    private func unaffordable(points: Int) -> [Swatch] {
        let area = visibleQuestionArea.insetBy(dx: -0.5, dy: -0.5)
        return swatches().filter { swatch in
            guard let price = swatch.price else {
                return false
            }
            return price > points && area.contains(swatch.frame)
        }
    }

    /// The message gives the price and the player's points, is the only one, is entirely in view below the header,
    /// covers no colour, and sits just under its colour's row, above the next colour's.
    @MainActor
    private func checkMessage(_ message: XCUIElement, about swatch: Swatch, points: Int,
                              file: StaticString = #filePath, line: UInt = #line) {
        let expected = "Not enough points! \(swatch.colour) \(swatch.percent)% costs \(Self.pointsText(swatch.price ?? -1)). "
            + "You have \(Self.pointsText(points))."
        XCTAssertEqual(message.label, expected, file: file, line: line)
        let showing = notEnoughPointsBanners()
        if showing.count != 1 {
            attachText("Every \"Not enough points!\" message", showing.map { "\($0.label) \($0.frame)" }
                .joined(separator: "\n") + "\n\n" + app.debugDescription)
        }
        XCTAssertEqual(showing.count, 1, "More than one message is showing: \(showing.map(\.frame)).", file: file, line: line)
        assertFullyVisible(message, "The message about \(swatch.label)", within: visibleQuestionArea, tappable: false,
                           file: file, line: line)
        let frame = message.frame
        assertNoOverlap([("The message", frame), ("The points", pointsLabel.frame), ("Menu", menuButton.frame)],
                        file: file, line: line)

        let all = swatches()
        let covered = all.filter { overlapArea($0.frame, frame) >= 1 }.map(\.label)
        XCTAssertTrue(covered.isEmpty, "The message at \(frame) covers \(covered).", file: file, line: line)
        let row = all.filter { $0.colour == swatch.colour }
        XCTAssertEqual(row.count, 4, "\(swatch.colour) doesn't have four strengths.", file: file, line: line)
        guard let rowBottom = row.map(\.frame.maxY).max() else {
            return
        }
        let gap = frame.minY - rowBottom
        XCTAssertGreaterThanOrEqual(gap, -0.5, "The message at \(frame) isn't under \(swatch.colour)'s row.",
                                    file: file, line: line)
        XCTAssertLessThanOrEqual(gap, 24, "The message is \(gap) points below \(swatch.colour)'s row, not just under it.",
                                 file: file, line: line)
        if let next = all.first(where: { $0.frame.minY > rowBottom }) {
            XCTAssertLessThanOrEqual(frame.maxY, next.frame.minY + 0.5, "The message at \(frame) runs into \(next.colour)'s row.",
                                     file: file, line: line)
        }
        attachText("The message about \(swatch.label)", "\(message.label)\nMessage \(frame)\nRow bottom \(rowBottom)\n"
            + "Visible area \(visibleQuestionArea)\nPoints \(pointsLabel.frame)")
    }

    /// Each part is entirely below the points and the menu button and overlaps neither.
    @MainActor
    private func assertBelowTheHeader(_ parts: [(String, XCUIElement)], on screen: String,
                                      file: StaticString = #filePath, line: UInt = #line) {
        let points = pointsLabel.frame
        let menu = menuButton.frame
        let headerBottom = max(points.maxY, menu.maxY)
        for (name, element) in parts {
            XCTAssertTrue(element.waitForExistence(timeout: 5), "\(screen): \(name) isn't there.", file: file, line: line)
            let frame = element.frame
            XCTAssertGreaterThanOrEqual(frame.minY, headerBottom - 0.5,
                                        "\(screen): \(name) at \(frame) reaches up into the header, which ends at \(headerBottom).",
                                        file: file, line: line)
            assertNoOverlap([("\(screen): \(name)", frame), ("the points", points), ("the menu button", menu)],
                            file: file, line: line)
        }
    }

    /// The frames are in the same place, give or take half a point.
    private func assertSamePlace(_ frame: CGRect, _ expected: CGRect, _ message: String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let moved = max(abs(frame.minX - expected.minX), abs(frame.minY - expected.minY),
                        abs(frame.width - expected.width), abs(frame.height - expected.height))
        XCTAssertLessThanOrEqual(moved, 0.5, "\(message) \(frame), not \(expected).", file: file, line: line)
    }

    private func overlapArea(_ first: CGRect, _ second: CGRect) -> CGFloat {
        let overlap = first.intersection(second)
        return overlap.isNull ? 0 : overlap.width * overlap.height
    }
}
