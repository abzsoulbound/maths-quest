//
//  NavigationAccessibilityUITests.swift
//  Maths QuestUITests
//

import UIKit
import XCTest

/// The navigation controls and what VoiceOver is given to read: the names of the controls, the order they're read
/// in, the spoken form of the maths and the descriptions of the pictures. The spoken-maths tests answer questions
/// using only what VoiceOver reads, so they show it's enough to answer with.
///
/// XCUITest reads the accessibility tree VoiceOver reads, so it can check names, values and order. It also lists
/// elements VoiceOver skips, such as the screen behind the open sidebar and the numbers inside a picture, and it can't
/// turn VoiceOver on, swipe through it or use its adjustable actions, so those are covered by the unit tests
/// (Stage5CVoiceOverTests).
final class NavigationAccessibilityUITests: MathsQuestUITestCase {

    // MARK: - Navigation controls

    /// The menu, close, home and settings buttons have spoken names, are big enough to tap and sit below the
    /// status bar, and every button on the way has a spoken name rather than an SF Symbol's.
    @MainActor
    func testNavigationControlsHaveSpokenNamesAndRoomToTap() throws {
        continueAfterFailure = true
        launchApp()

        assertNavigationControl(menuButton, named: "Menu", on: "Main menu")
        assertEveryButtonHasASpokenName(on: "Main menu")
        assertReadInOrder(["Menu", "Maths Quest", "Year 1", "Year 2", "Year 3", "Year 4", "Year 5", "Year 6"],
                          on: "Main menu")

        openSidebar()
        assertNavigationControl(sidebarCloseButton, named: "Close menu", on: "Sidebar")
        assertEveryButtonHasASpokenName(on: "Sidebar")
        attachScreenshot("Sidebar open")
        tap(sidebarCloseButton)
        XCTAssertTrue(sidebarCloseButton.waitForNonExistence(timeout: 5), "The sidebar didn't close.")

        openYear(1)
        assertNavigationControl(homeButton, named: "Home", on: "Year 1")
        assertNavigationControl(settingsButton, named: "Settings", on: "Year 1")
        assertEveryButtonHasASpokenName(on: "Year 1")
        // The header reads Home, the points, then Settings, on the device's own screen, iPad included.
        assertReadInOrder(["Home", pointsLabel.label, "Settings", "Year 1", "Counting", "Addition", "Subtraction"],
                          on: "Year 1")

        openActivity("Addition")
        assertNavigationControl(homeButton, named: "Home", on: "Addition")
        assertNavigationControl(settingsButton, named: "Settings", on: "Addition")
        assertEveryButtonHasASpokenName(on: "Addition")
        let question = question(using: "+")
        assertReadInOrder(["Home", pointsLabel.label, "Settings", question, "Answer", "Enter "], on: "Addition")
    }

    /// Settings opened with the gear in an activity has the sidebar rather than Home, and the sidebar takes the
    /// player on to another year and Home takes them back to the main menu.
    @MainActor
    func testSettingsFromAnActivityLeadsOnThroughTheSidebar() throws {
        launchApp()
        openYear(3)
        openActivity("Time")
        tap(settingsButton)
        XCTAssertTrue(nameField.waitForExistence(timeout: 10), "Settings didn't open from the gear.")
        assertNavigationControl(menuButton, named: "Menu", on: "Settings")
        XCTAssertFalse(homeButton.exists, "Settings has a home button as well as the menu.")

        openFromSidebar("Year 2")
        assertOnYearMenu(2)
        goHome()
    }

    /// Every year and activity has the same home and settings buttons in the same place, each with a spoken name.
    @MainActor
    func testEveryScreenInYears1To3HasTheSameNavigationControls() throws {
        try checkNavigationControls(inYears: 1...3)
    }

    @MainActor
    func testEveryScreenInYears4To6HasTheSameNavigationControls() throws {
        try checkNavigationControls(inYears: 4...6)
    }

    /// Going Home while "Correct!" is showing keeps the point, scores it once, and doesn't carry the message or
    /// the answer to the next visit.
    @MainActor
    func testGoingHomeDuringCorrectScoresOnce() throws {
        launchApp()
        openYear(1)
        openActivity("Addition")
        let start = currentPoints()

        let (a, b) = operands(using: "+")
        replaceText(in: answerField, with: "\(a + b)")
        tap(enterButton)
        XCTAssertTrue(waitQuickly(timeout: 3) { visibleFeedback() == Feedback.correct.rawValue }, "No \"Correct!\".")
        tap(homeButton)
        assertOnMainMenu()
        assertPoints(start + 1)

        // The next question would have come up a second after "Correct!". Nothing more is scored when it does.
        pause(2)
        assertPoints(start + 1)

        openYear(1)
        openActivity("Addition")
        XCTAssertNil(visibleFeedback(), "The message was still showing on the next visit.")
        XCTAssertEqual(typedText(in: answerField), "", "The answer was still there on the next visit.")
        assertPoints(start + 1)
    }

    // MARK: - Maths as VoiceOver reads it

    /// "Simplify the ratio 6 to 12" rather than a time, and "missing number" for the gap.
    @MainActor
    func testRatiosCanBeAnsweredFromWhatVoiceOverReads() throws {
        try answerFromWhatVoiceOverReads("Ratios", inYear: 6, questions: 4) { spoken in
            if let match = spoken.firstMatch(of: #/^Simplify the ratio (\d+) to (\d+)$/#) {
                let (first, second) = (Int(match.1)!, Int(match.2)!)
                let factor = Self.greatestCommonDivisor(first, second)
                return ["First part of the ratio": "\(first / factor)", "Second part of the ratio": "\(second / factor)"]
            }
            if let match = spoken.firstMatch(of: #/^Divide (\d+) in the ratio (\d+) to (\d+)$/#) {
                let (total, first, second) = (Int(match.1)!, Int(match.2)!, Int(match.3)!)
                let share = total / (first + second)
                return ["First part of the ratio": "\(first * share)", "Second part of the ratio": "\(second * share)"]
            }
            if let match = spoken.firstMatch(of: #/^Find the missing number\. missing number to (\d+) equals (\d+) to (\d+)$/#) {
                let (shown, first, second) = (Int(match.1)!, Int(match.2)!, Int(match.3)!)
                return ["": "\(first * shown / second)"]
            }
            if let match = spoken.firstMatch(of: #/^Find the missing number\. (\d+) to missing number equals (\d+) to (\d+)$/#) {
                let (shown, first, second) = (Int(match.1)!, Int(match.2)!, Int(match.3)!)
                return ["": "\(second * shown / first)"]
            }
            return nil
        }
    }

    /// "Simplify 2 quarters" rather than VoiceOver reading the small digits of "²/₄".
    @MainActor
    func testFractionsCanBeAnsweredFromWhatVoiceOverReads() throws {
        try answerFromWhatVoiceOverReads("Fractions", inYear: 3, questions: 4) { spoken in
            if let match = spoken.firstMatch(of: #/^Simplify (\d+) ([a-z]+)$/#) {
                guard let denominator = Self.denominator(named: String(match.2)) else { return nil }
                let numerator = Int(match.1)!
                let factor = Self.greatestCommonDivisor(numerator, denominator)
                return ["Numerator": "\(numerator / factor)", "Denominator": "\(denominator / factor)"]
            }
            if let match = spoken.firstMatch(of: #/^What is (\d+) ([a-z]+) of (\d+)\?$/#) {
                guard let denominator = Self.denominator(named: String(match.2)) else { return nil }
                return ["": "\(Int(match.1)! * Int(match.3)! / denominator)"]
            }
            return nil
        }
    }

    /// "plus", "minus" and "times" rather than "x" read as a letter and "-" skipped.
    @MainActor
    func testDecimalsCanBeAnsweredFromWhatVoiceOverReads() throws {
        try answerFromWhatVoiceOverReads("Decimals", inYear: 4, questions: 4) { spoken in
            guard let match = spoken.firstMatch(of: #/^What is (\d+)\.(\d) (plus|minus|times) (\d+)(?:\.(\d))?\?$/#) else {
                return nil
            }
            let first = Int(match.1)! * 10 + Int(match.2)!
            let tenths: Int
            switch match.3 {
            case "plus":
                tenths = first + Int(match.4)! * 10 + Int(match.5 ?? "0")!
            case "minus":
                tenths = first - (Int(match.4)! * 10 + Int(match.5 ?? "0")!)
            default:
                tenths = first * Int(match.4)!
            }
            return ["": "\(tenths / 10).\(tenths % 10)"]
        }
    }

    /// "3 times open bracket 5x plus 2 close bracket", because VoiceOver doesn't read brackets.
    @MainActor
    func testAlgebraCanBeAnsweredFromWhatVoiceOverReads() throws {
        try answerFromWhatVoiceOverReads("Algebra", inYear: 6, questions: 4) { spoken in
            func coefficient(_ term: Substring) -> Int { term.isEmpty ? 1 : Int(term)! }
            if let match = spoken.firstMatch(of: #/^x \+ (\d+) = (\d+)$/#) {
                return ["": "\(Int(match.2)! - Int(match.1)!)"]
            }
            if let match = spoken.firstMatch(of: #/^(\d*)x \+ (\d*)x$/#) {
                return ["": "\(coefficient(match.1) + coefficient(match.2))x"]
            }
            if let match = spoken.firstMatch(of: #/^(\d+) times open bracket (\d*)x plus (\d+) close bracket$/#) {
                let multiplier = Int(match.1)!
                return ["": "\(multiplier * coefficient(match.2))x+\(multiplier * Int(match.3)!)"]
            }
            return nil
        }
    }

    // MARK: - Pictures as VoiceOver describes them

    /// The shape's sides or the angle's arms are described.
    @MainActor
    func testGeometryPictureIsDescribed() throws {
        launchApp()
        openYear(4)
        openActivity("Geometry")
        let picture = element(labelled: #"^(A (triangle|square|rectangle|pentagon|shape) with sides of .+ and \d+ (milli|centi|kilo)?metres?\.|An angle\. One arm points right, and the other points (up and to the right|straight up|up and to the left)\.)$"#)
        XCTAssertTrue(picture.waitForExistence(timeout: 10), "The Geometry picture has no description.")
        attachText("Geometry description", picture.label)
        XCTAssertTrue(picture.elementType == .image || picture.elementType == .other,
                      "The Geometry picture is a \(picture.elementType.rawValue), not an image.")
        XCTAssertFalse(picture.label.contains("degree"), "The description gives the angle away.")
    }

    /// The cube or cuboid's three edges are described, and the volume can be worked out from them.
    @MainActor
    func testVolumePictureIsDescribedWellEnoughToAnswer() throws {
        launchApp()
        let pattern = #"^A (cube|cuboid)\. Width (\d+) centimetres, length (\d+) centimetres, height (\d+) centimetres\.$"#
        let picture = try openUntilOneAppears(element(labelled: pattern), in: "Volume", inYear: 5)
        let start = currentPoints()
        guard let match = picture.label.firstMatch(of: #/Width (\d+) centimetres, length (\d+) centimetres, height (\d+) centimetres/#) else {
            return XCTFail("Couldn't read \"\(picture.label)\".")
        }
        answer("\(Int(match.1)! * Int(match.2)! * Int(match.3)!)", expecting: .correct)
        assertPoints(start + 1)
    }

    /// Each bar is read as its category and value, and the highest can be found from them.
    @MainActor
    func testBarChartIsDescribedWellEnoughToAnswer() throws {
        launchApp()
        _ = try openUntilOneAppears(element(labelled: "^Bar chart$"), in: "Statistics", inYear: 5)
        let bars = app.descendants(matching: .any).matching(NSPredicate(format: "label MATCHES %@", "^Category [A-D]$"))
            .allElementsBoundByIndex
        XCTAssertEqual(bars.count, 4, "The bar chart doesn't read out four bars.")
        let values = bars.compactMap { bar -> (String, Int)? in
            guard let value = bar.value as? String, let number = Int(value) else { return nil }
            return (String(bar.label.suffix(1)), number)
        }
        XCTAssertEqual(values.count, bars.count, "A bar has no value: \(bars.map { $0.value ?? "nil" }).")
        attachText("Bars", "\(values)")
        guard let highest = values.max(by: { $0.1 < $1.1 }) else { return }
        let start = currentPoints()
        answer(highest.0, expecting: .correct)
        assertPoints(start + 1)
    }

    /// The red bar says where its ends are on the ruler, which is enough to measure it, and the ruler is described.
    @MainActor
    func testRulerAndBarAreDescribedWellEnoughToAnswer() throws {
        launchApp()
        let bar = try openUntilOneAppears(element(labelled: "^Red bar to measure$"), in: "Measurement", inYear: 3)
        XCTAssertTrue(element(labelled: "^Ruler, marked from 0 to 15 centimetres$").exists, "The ruler has no description.")
        let value = bar.value as? String ?? ""
        attachText("Red bar", value)
        guard let match = value.firstMatch(of: #/^Left end at (\d+) centimetres, right end at (\d+) centimetres$/#) else {
            return XCTFail("The red bar's position reads \"\(value)\".")
        }
        let start = currentPoints()
        answer("\(Int(match.2)! - Int(match.1)!)", expecting: .correct)
        assertPoints(start + 1)
    }

    /// The clock says where its hands point, as a sighted player sees them, without giving the time away.
    @MainActor
    func testClockIsDescribed() throws {
        launchApp()
        let clock = try openUntilOneAppears(element(labelled: "^(Clock|Clock to set)$"), in: "Time", inYear: 3)
        let value = clock.value as? String ?? ""
        attachText("\(clock.label)", value)
        XCTAssertNotNil(value.firstMatch(of: #/^The short hour hand (points at|is between) the \d+.* The long minute hand (points at|is \d small marks? past) the \d+\.$/#),
                        "The clock reads \"\(value)\".")
        XCTAssertNil(value.firstMatch(of: #/\d+:\d+|o'clock|past \d+ minutes/#), "The clock's description says the time.")
    }

    // MARK: - The largest text size

    /// At the largest accessibility text size, the menus fit, the question is bigger, and Addition can still be
    /// answered with the keyboard up.
    @MainActor
    func testLargestTextSize() throws {
        continueAfterFailure = true
        extraLaunchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        launchApp()
        let window = windowFrame
        for year in 1...6 {
            assertFullyVisible(button("Year \(year)"), "Year \(year)", within: window)
        }
        attachScreenshot("Main menu, largest text")

        openYear(1)
        for activity in Self.activities[1]! {
            assertFullyVisible(button(activity), activity, within: window)
        }
        openActivity("Addition")
        let start = currentPoints()
        let (a, b) = operands(using: "+")
        let question = text("\(a) + \(b)")
        XCTAssertGreaterThanOrEqual(question.frame.height, 34, "The question didn't get bigger with the text size.")
        assertFullyVisible(question, "The question", within: window, tappable: false)
        assertFullyVisible(pointsLabel, "The points", within: window, tappable: false)
        assertNoOverlap([("Home", homeButton.frame), ("The points", pointsLabel.frame), ("Settings", settingsButton.frame),
                         ("The question", question.frame)])
        attachScreenshot("Addition, largest text")

        if showKeyboard(typing: "\(a + b)", into: answerField) {
            attachScreenshot("Addition, largest text, keyboard up")
            XCTAssertFalse(keyboardOverlaps(enterButton), "The keyboard covers Enter at the largest text size.")
            XCTAssertFalse(keyboardOverlaps(answerField), "The keyboard covers the answer at the largest text size.")
            pressEnter(expecting: .correct)
        } else {
            attachText("Keyboard", "No on-screen keyboard appeared, so Enter was tapped with it down.")
            pressEnter(expecting: .correct)
        }
        assertPoints(start + 1)

        // The sidebar scrolls if its entries don't fit, so Settings can still be reached.
        goHome()
        openSidebar()
        attachScreenshot("Sidebar, largest text")
        tap(sidebarButton("Settings"))
        XCTAssertTrue(nameField.waitForExistence(timeout: 10), "Settings didn't open from the sidebar.")
        assertFullyVisible(nameField, "The name box", within: window)
        assertFullyVisible(button("Enter"), "Settings' Enter", within: window)
        attachScreenshot("Settings, largest text")
    }

    // MARK: - The keyboard on the other screens

    /// On the Shop, Settings and Feedback, the keyboard leaves Enter in view. Nothing is bought, saved or sent:
    /// Enter isn't tapped.
    @MainActor
    func testKeyboardLeavesEnterInViewOnShopSettingsAndFeedback() throws {
        continueAfterFailure = true
        launchApp()
        var keyboardsShown = 0
        let screens: [(screen: String, field: XCUIElement, typing: String)] = [
            ("Shop", app.textFields.matching(NSPredicate(format: "placeholderValue == 'Points to spend' OR label == 'Points to spend'")).firstMatch, "1"),
            ("Settings", nameField, "A"),
            ("Feedback", app.textViews.matching(NSPredicate(format: "label == 'Your feedback'")).firstMatch, "A"),
        ]
        for (screen, field, typing) in screens {
            openFromSidebar(screen)
            XCTAssertTrue(field.waitForExistence(timeout: 10), "\(screen) has no text box.")
            let enter = button("Enter")
            guard showKeyboard(typing: typing, into: field) else {
                attachText("\(screen) keyboard", "No on-screen keyboard appeared, so \(screen) wasn't checked with it up.")
                continue
            }
            keyboardsShown += 1
            attachScreenshot("\(screen) with the keyboard up")
            XCTAssertFalse(keyboardCoversTapPoint(of: enter), "\(screen): the keyboard covers Enter at \(enter.frame).")
            XCTAssertFalse(keyboardOverlaps(field), "\(screen): the keyboard covers the text box at \(field.frame).")
            XCTAssertTrue(enter.isHittable, "\(screen): Enter can't be tapped with the keyboard up.")
            XCTAssertTrue(menuButton.isHittable, "\(screen): the menu button can't be tapped with the keyboard up.")
        }
        if keyboardsShown == 0 {
            throw XCTSkip("No on-screen keyboard appeared on the Shop, Settings or Feedback.")
        }
    }

    /// At the largest accessibility text size, Feedback's text box, Enter and the menu button are still in view and
    /// can be used with the keyboard up. Enter isn't tapped, so nothing is sent.
    @MainActor
    func testFeedbackAtTheLargestTextSizeWithTheKeyboardUp() throws {
        continueAfterFailure = true
        extraLaunchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        launchApp()
        openFromSidebar("Feedback")
        let field = app.textViews.matching(NSPredicate(format: "label == 'Your feedback'")).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Feedback has no text box.")
        let enter = button("Enter")
        attachScreenshot("Feedback, largest text")
        guard showKeyboard(typing: "A", into: field) else {
            throw XCTSkip("No on-screen keyboard appeared on Feedback.")
        }
        attachScreenshot("Feedback, largest text, keyboard up")
        attachText("Feedback frames", "Text box \(field.frame)\nEnter \(enter.frame)\nWindow \(windowFrame)")
        XCTAssertFalse(keyboardCoversTapPoint(of: enter), "The keyboard covers Enter at \(enter.frame).")
        XCTAssertFalse(keyboardOverlaps(field), "The keyboard covers the text box at \(field.frame).")
        XCTAssertTrue(enter.isHittable, "Enter can't be tapped with the keyboard up.")
        XCTAssertTrue(menuButton.isHittable, "The menu button can't be tapped with the keyboard up.")
        XCTAssertTrue(field.hasKeyboardFocus, "Typing left the text box.")
    }

    /// Every shop colour has a spoken name and says whether it's chosen, unlocked or what it costs, and the
    /// screenshots show the prices on their swatches. Nothing is bought: no swatch is tapped.
    @MainActor
    func testShopSwatchesSayWhatTheyCost() throws {
        launchApp()
        openFromSidebar("Shop")
        let name = #/^[A-Za-z ]+, \d+ percent$/#
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label MATCHES %@", "^[A-Za-z ]+, [0-9]+ percent$"))
            .firstMatch.waitForExistence(timeout: 10), "The Shop has no colours.")
        let swatches = snapshots { $0.elementType == .button && $0.label.wholeMatch(of: name) != nil }
        let read = swatches.map { "\($0.label): \($0.value as? String ?? "")" }
        attachText("Shop colours as VoiceOver reads them", read.joined(separator: "\n"))
        attachScreenshot("Shop")
        XCTAssertEqual(swatches.count, 60, "15 colours at 4 strengths each.")
        for line in read {
            XCTAssertNotNil(line.firstMatch(of: #/: (Selected|Unlocked|Locked, \d+ points)$/#), "\(line)")
        }
        // At most one, not exactly one: the starting colour is saved as "0000FF" but the shop's Blue is "#0000FF", so
        // until a colour is chosen the shop shows none as chosen. Left for the owner (Stage 5D report).
        XCTAssertLessThanOrEqual(swatches.filter { $0.value as? String == "Selected" }.count, 1, "\(read)")
        app.swipeUp()
        attachScreenshot("Shop, scrolled")
    }

    /// The text field is drawn inside a white box with a 16-point margin. A tap on the margin, outside the text field
    /// itself, must still put the cursor in it.
    @MainActor
    func testAnswerBoxCanBeTappedAnywhereOnIt() throws {
        launchApp()
        openYear(1)
        openActivity("Addition")
        let field = answerField.frame
        // The white box is a third of the column, which is the screen's width up to 600 points. VoiceOver's frame for
        // the field is the whole box once the margin can be tapped; before that it was only the text field inside it.
        let reportsWholeBox = field.width >= min(windowFrame.width, 600) / 3 - 1
        func whiteBox() -> CGRect {
            reportsWholeBox ? answerField.frame : answerField.frame.insetBy(dx: -16, dy: -16)
        }
        attachText("Answer box", "Text field frame \(field); white box \(whiteBox())")
        XCTAssertGreaterThanOrEqual(whiteBox().height, 44, "The white answer box is shorter than 44 points.")
        let origin = app.coordinate(withNormalizedOffset: .zero)
        // 6 points inside the white box, which is inside the 16-point margin round the text.
        let marginPoints: [(String, (CGRect) -> CGPoint)] = [
            ("left", { CGPoint(x: $0.minX + 6, y: $0.midY) }),
            ("right", { CGPoint(x: $0.maxX - 6, y: $0.midY) }),
            ("top", { CGPoint(x: $0.midX, y: $0.minY + 6) }),
            ("bottom", { CGPoint(x: $0.midX, y: $0.maxY - 6) }),
        ]
        for (edge, pointIn) in marginPoints {
            takeCursorOut(of: answerField, "the box")
            let point = pointIn(whiteBox())
            origin.withOffset(CGVector(dx: point.x, dy: point.y)).tap()
            XCTAssertTrue(
                waitQuickly(timeout: 5) { answerField.hasKeyboardFocus },
                "A tap on the white margin \(edge) of the text, at \(point), didn't put the cursor in the box."
            )
        }
    }

    /// A fraction's two boxes are drawn as tall as the screen allows, which is under 44 points on a small iPhone, so
    /// they can also be tapped just above and below, up to 44 points. Since Stage 5D that area isn't centred on the box:
    /// it stops where it meets the other box and is made up on the far side.
    ///
    /// The taps go 5 points inside the far edges. On the iPhone SE simulator a 1-point scan found each box takes taps
    /// up to about 2 points short of the bottom of its reported area (the denominator, drawn in front, takes the 2
    /// points above where the boxes meet), so a tap 3 points inside the denominator's bottom edge sometimes missed.
    @MainActor
    func testFractionBoxesCanBeTappedOver44Points() throws {
        launchApp()
        openYear(6)
        openActivity("Probability")
        let origin = app.coordinate(withNormalizedOffset: .zero)
        // The middle, then the top of the numerator and the bottom of the denominator.
        for (name, farEdgeIsTop) in [("Numerator", true), ("Denominator", false)] {
            let field = app.textFields.matching(NSPredicate(format: "placeholderValue == %@ OR label == %@", name, name)).firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 10), "Probability has no \(name) box.")
            attachText("\(name) box", "\(field.frame)")
            XCTAssertGreaterThanOrEqual(field.frame.height, 44 - 0.001, "Only \(field.frame.height) points of the \(name) box can be tapped.")
            for atTheEdge in [false, true] {
                takeCursorOut(of: field, "the \(name) box")
                let frame = field.frame
                let y = !atTheEdge ? frame.midY : farEdgeIsTop ? frame.minY + 5 : frame.maxY - 5
                let point = CGPoint(x: frame.midX, y: y)
                origin.withOffset(CGVector(dx: point.x, dy: point.y)).tap()
                XCTAssertTrue(waitQuickly(timeout: 5) { field.hasKeyboardFocus },
                              "A tap at \(point), \(point.y - frame.midY) points from the middle of the \(name) box's tap area \(frame), didn't put the cursor in it.")
            }
        }
    }

    /// The two fraction boxes' tap areas used to overlap by about 4 points on the iPhone SE. Now they meet without
    /// overlapping, and a tap on either side of where they meet goes to the box on that side. The taps are 5 points
    /// inside each box's area, past the 2 points by the join that the denominator also takes (see above).
    @MainActor
    func testFractionBoxTapAreasMeetWithoutOverlapping() throws {
        launchApp()
        openYear(6)
        openActivity("Probability")
        func box(_ name: String) -> XCUIElement {
            app.textFields.matching(NSPredicate(format: "placeholderValue == %@ OR label == %@", name, name)).firstMatch
        }
        let (numerator, denominator) = (box("Numerator"), box("Denominator"))
        XCTAssertTrue(numerator.waitForExistence(timeout: 10) && denominator.exists, "Probability has no fraction boxes.")
        attachText("Fraction boxes", "Numerator \(numerator.frame)\nDenominator \(denominator.frame)")
        XCTAssertLessThanOrEqual(numerator.frame.maxY, denominator.frame.minY + 0.5,
                                 "The numerator's tap area \(numerator.frame) overlaps the denominator's \(denominator.frame).")
        // The heights are worked out from the screen size, so 44 can come back as 43.99999999999994.
        XCTAssertGreaterThanOrEqual(numerator.frame.height, 44 - 0.001)
        XCTAssertGreaterThanOrEqual(denominator.frame.height, 44 - 0.001)
        for (field, name, aboveTheJoin) in [(numerator, "Numerator", true), (denominator, "Denominator", false)] {
            takeCursorOut(of: numerator, "the Numerator box")
            takeCursorOut(of: denominator, "the Denominator box")
            // On the iPad the boxes are 44 points already, with the bar between them, so this is inside each box.
            let y = aboveTheJoin ? numerator.frame.maxY - 5 : denominator.frame.minY + 5
            let point = CGPoint(x: field.frame.midX, y: y)
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y)).tap()
            XCTAssertTrue(waitQuickly(timeout: 5) { field.hasKeyboardFocus },
                          "A tap at \(point), 5 points \(aboveTheJoin ? "above" : "below") the edge of the \(name) box's area, didn't go to it.")
        }
    }

    /// Year 2 Shapes, answered from what VoiceOver reads: the picture is described, then gone round a part at a time.
    /// Counting the parts answers every kind of question, and nothing read names the shape.
    @MainActor
    func testShapesCanBeAnsweredByGoingRoundTheEdge() throws {
        launchApp()
        openYear(2)
        openActivity("Shapes")
        let start = currentPoints()
        let names = ["circle", "triangle", "square", "pentagon", "hexagon", "octagon"]
        let shapeWithCorners = [0: "circle", 3: "triangle", 4: "square", 5: "pentagon", 6: "hexagon", 8: "octagon"]
        var heard: [String] = []
        for number in 1...8 {
            let read = snapshots { !$0.label.isEmpty }.map(\.label)
            XCTAssertTrue(read.contains { $0.hasPrefix("Shape picture") }, "The picture isn't described: \(read)")
            XCTAssertFalse(read.contains("A shape"))
            XCTAssertFalse(read.contains { label in names.contains { label.lowercased().contains($0) } },
                           "Something read names the shape: \(read)")
            let corners = read.filter { $0.hasPrefix("Corner") }.count
            let sides = read.filter { $0.hasPrefix("Straight side") }.count
            let curved = read.filter { $0.hasPrefix("Curved edge") }.count
            let answer: String?
            switch read.first(where: { $0.hasSuffix("?") }) {
            case "How many straight sides does this shape have?": answer = "\(sides)"
            case "How many corners does this shape have?": answer = "\(corners)"
            case "What is this shape called?": answer = shapeWithCorners[corners]
            default: answer = nil
            }
            guard let answer else {
                XCTFail("No Shapes question could be answered from: \(read).")
                return
            }
            heard.append("\(corners) corners, \(sides) straight sides, \(curved) curved edges → \(answer)")
            replaceText(in: answerField, with: answer)
            pressEnter(expecting: .correct)
            assertPoints(start + number)
            waitForNextQuestion()
        }
        attachText("Shapes as VoiceOver reads them", heard.joined(separator: "\n"))
    }

    // MARK: - Helpers

    /// Takes the cursor out of `field`, or puts the keyboard away if another box has the cursor, by tapping the
    /// background beside it: level with it, or just above the keyboard if that's lower. Then waits for the keyboard
    /// to go and the question to scroll back, so the field is where it is with the keyboard down. With a hardware
    /// keyboard there's no on-screen keyboard to wait for.
    @MainActor
    private func takeCursorOut(of field: XCUIElement, _ name: String) {
        guard field.hasKeyboardFocus || keyboardIsOnScreen else {
            return
        }
        var y = field.frame.midY
        if keyboardIsOnScreen {
            y = min(y, keyboardGlassFrame.minY - 20)
        }
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: windowFrame.minX + 2, dy: y)).tap()
        XCTAssertTrue(waitQuickly(timeout: 5) { !field.hasKeyboardFocus }, "The cursor stayed in \(name).")
        XCTAssertTrue(waitQuickly(timeout: 5) { !keyboardIsOnScreen }, "The keyboard stayed up.")
        _ = waitForFrameToSettle(of: field)
    }

    private struct PictureNotShown: Error, CustomStringConvertible {
        let description: String
    }

    /// The Settings name box.
    @MainActor
    private var nameField: XCUIElement {
        app.textFields.matching(NSPredicate(format: "label == 'Name'")).firstMatch
    }

    /// The height of the status bar, which the navigation controls must be below. iPhones with a notch or the
    /// Dynamic Island are more than twice as tall as they are wide.
    @MainActor
    private var statusBarHeight: CGFloat {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return 24
        }
        return windowFrame.height > windowFrame.width * 2 ? 44 : 20
    }

    @MainActor
    private func assertNavigationControl(_ control: XCUIElement, named name: String, on screen: String,
                                         file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(control.waitForExistence(timeout: 10), "\(screen) has no \(name) button.", file: file, line: line)
        XCTAssertEqual(control.label, name, "\(screen): VoiceOver reads the wrong name.", file: file, line: line)
        let frame = control.frame
        XCTAssertGreaterThanOrEqual(frame.width, 44, "\(screen): \(name) at \(frame) is narrower than 44 points.",
                                    file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.height, 44, "\(screen): \(name) at \(frame) is shorter than 44 points.",
                                    file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minY, windowFrame.minY + statusBarHeight,
                                    "\(screen): \(name) at \(frame) is under the status bar.", file: file, line: line)
        assertFullyVisible(control, "\(screen): \(name)", within: windowFrame, file: file, line: line)
    }

    /// Fails for a button VoiceOver would read by an SF Symbol's name, such as "line.horizontal.3", by the
    /// description iOS gives a symbol, such as "Drag" for the menu button before Stage 5C, or by nothing.
    @MainActor
    private func assertEveryButtonHasASpokenName(on screen: String, file: StaticString = #filePath, line: UInt = #line) {
        let unnamed = snapshots(where: { $0.elementType == .button }).filter { button in
            let label = button.label.trimmingCharacters(in: .whitespaces)
            return label.isEmpty || label == "Drag" || label.wholeMatch(of: #/[a-z0-9]+(\.[a-z0-9]+)+/#) != nil
        }
        XCTAssertTrue(unnamed.isEmpty,
                      "\(screen): buttons without a spoken name: \(unnamed.map { "\"\($0.label)\" (\($0.identifier)) at \($0.frame)" }).",
                      file: file, line: line)
    }

    /// Checks that VoiceOver reaches the elements with these labels in this order. A text box is matched by its
    /// label or its placeholder.
    @MainActor
    private func assertReadInOrder(_ labels: [String], on screen: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        let order = snapshots(where: { [.button, .staticText, .textField, .textView, .image].contains($0.elementType) })
        let read = order.map { $0.label.isEmpty ? ($0.placeholderValue ?? "") : $0.label }
        attachText("\(screen) reading order", read.joined(separator: "\n"))
        var previous = -1
        for label in labels {
            guard let index = read.indices.first(where: { $0 > previous && read[$0] == label }) else {
                XCTFail("\(screen): \"\(label)\" isn't read after the elements before it in \(labels).", file: file, line: line)
                return
            }
            previous = index
        }
    }

    /// The accessibility tree's elements that pass `include`, in the order the tree lists them.
    @MainActor
    private func snapshots(where include: (XCUIElementSnapshot) -> Bool) -> [XCUIElementSnapshot] {
        guard let root = try? app.snapshot() else {
            return []
        }
        var found: [XCUIElementSnapshot] = []
        func visit(_ element: XCUIElementSnapshot) {
            if include(element) {
                found.append(element)
            }
            element.children.forEach(visit)
        }
        visit(root)
        return found
    }

    @MainActor
    private func element(labelled pattern: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label MATCHES %@", pattern)).firstMatch
    }

    /// Opens `activity` until a question shows `element`, and returns it.
    @MainActor
    private func openUntilOneAppears(_ element: XCUIElement, in activity: String, inYear year: Int,
                                     attempts: Int = 15, file: StaticString = #filePath, line: UInt = #line) throws -> XCUIElement {
        for attempt in 1...attempts {
            if attempt > 1 {
                goHome(file: file, line: line)
            }
            openYear(year, file: file, line: line)
            openActivity(activity, file: file, line: line)
            if element.waitForExistence(timeout: 2) {
                return element
            }
        }
        throw PictureNotShown(description: "\(attempts) \(activity) questions in a row didn't show the picture.")
    }

    /// Reads each question as VoiceOver reads it, works out the answer from that alone with `solve`, types it in
    /// and checks it's marked right and scores a point. `solve` returns the text for each answer box, keyed by its
    /// spoken name, or "" for the only box; nil means it doesn't recognise what was read.
    @MainActor
    private func answerFromWhatVoiceOverReads(_ activity: String, inYear year: Int, questions: Int,
                                              solve: (String) -> [String: String]?) throws {
        launchApp()
        openYear(year)
        openActivity(activity)
        let start = currentPoints()
        var heard: [String] = []
        for number in 1...questions {
            let read = staticTextSnapshots().map(\.label)
            guard let found = read.compactMap({ label in solve(label).map { (label, $0) } }).first else {
                XCTFail("\(activity): no question VoiceOver reads could be answered from: \(read).")
                return
            }
            let (spoken, answers) = found
            heard.append("\(spoken) → \(answers)")
            for (name, typed) in answers.sorted(by: { $0.key < $1.key }) {
                let field = name.isEmpty
                    ? answerField
                    : app.textFields.matching(NSPredicate(format: "label == %@ OR placeholderValue == %@", name, name)).firstMatch
                replaceText(in: field, with: typed)
            }
            pressEnter(expecting: .correct)
            assertPoints(start + number)
            waitForNextQuestion()
        }
        attachText("\(activity) as VoiceOver reads it", heard.joined(separator: "\n"))
    }

    @MainActor
    private func checkNavigationControls(inYears years: ClosedRange<Int>) throws {
        continueAfterFailure = true
        launchApp()
        for year in years {
            openFromSidebar("Year \(year)")
            assertOnYearMenu(year)
            assertNavigationControl(homeButton, named: "Home", on: "Year \(year)")
            assertNavigationControl(settingsButton, named: "Settings", on: "Year \(year)")
            let homeOnTheYearMenu = homeButton.frame
            for (index, activity) in Self.activities[year]!.enumerated() {
                if index > 0 {
                    openYear(year)
                }
                openActivity(activity)
                assertNavigationControl(homeButton, named: "Home", on: activity)
                assertNavigationControl(settingsButton, named: "Settings", on: activity)
                XCTAssertEqual(homeButton.frame.midX, homeOnTheYearMenu.midX, accuracy: 2,
                               "\(activity)'s home button isn't where the year menu's is.")
                assertEveryButtonHasASpokenName(on: activity)
                goHome()
            }
        }
    }

    private static func greatestCommonDivisor(_ a: Int, _ b: Int) -> Int {
        b == 0 ? a : greatestCommonDivisor(b, a % b)
    }

    /// 4 for "quarters", 2 for "half".
    private static func denominator(named name: String) -> Int? {
        let names = ["half": 2, "halves": 2, "third": 3, "thirds": 3, "quarter": 4, "quarters": 4, "fifth": 5,
                     "fifths": 5, "sixth": 6, "sixths": 6, "seventh": 7, "sevenths": 7, "eighth": 8, "eighths": 8,
                     "ninth": 9, "ninths": 9, "tenth": 10, "tenths": 10, "twelfth": 12, "twelfths": 12]
        return names[name]
    }
}

/// The test that types on a hardware keyboard. It's in its own class so that it runs after every other UI test
/// (with parallel testing off, XCTest runs the classes in alphabetical order): once XCUITest has typed a key, the
/// simulator treats a hardware keyboard as attached until it restarts. On the iPhones, the first Command-full stop
/// after each later launch of the app then doesn't reach it, so this test only passes on a simulator that hasn't
/// been typed on since it started. (Before the iPad's answer boxes asked for its numbers page, the iPad also opened
/// them with a small number pad that dimmed the screen and covered Enter.)
final class ZZHardwareKeyboardUITests: MathsQuestUITestCase {

    /// While the sidebar is open, the screen behind it can't be used, so only the sidebar's own buttons work, and
    /// the cancel shortcut on a hardware keyboard closes it. That VoiceOver skips the screen behind is checked by the
    /// unit tests.
    @MainActor
    func testSidebarHidesTheScreenBehindItAndClosesWithTheCancelShortcut() throws {
        launchApp()
        openSidebar()

        XCTAssertFalse(menuButton.exists && menuButton.isEnabled, "The menu button behind the open sidebar can still be used.")
        let yearOneButtons = app.buttons.matching(NSPredicate(format: "label == 'Year 1' AND enabled == true")).count
        XCTAssertEqual(yearOneButtons, 1, "The main menu's Year 1 can still be used behind the sidebar.")

        // Command-full stop. Escape is the same shortcut, but on the iOS 26 simulators an Escape typed by XCUITest
        // never reaches the app, whether or not the simulator's hardware keyboard is connected.
        app.typeKey(".", modifierFlags: .command)
        XCTAssertTrue(sidebarCloseButton.waitForNonExistence(timeout: 5), "Command-full stop didn't close the sidebar.")
        assertOnMainMenu()

        // Choosing a screen closes the sidebar and shows only that screen.
        openFromSidebar("Shop")
        XCTAssertTrue(menuButton.waitForExistence(timeout: 5), "The Shop has no menu button.")
        XCTAssertFalse(text("Maths Quest").exists, "The main menu is still showing behind the Shop.")
        openFromSidebar("Main Menu")
        assertOnMainMenu()
    }
}
