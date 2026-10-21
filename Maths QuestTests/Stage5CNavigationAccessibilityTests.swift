//
//  Stage5CNavigationAccessibilityTests.swift
//  Maths QuestTests
//
//  Stage 5C: navigation goes through AppNavigator, so a second tap can't open a screen twice and the
//  sidebar can't build up a stack of screens. VoiceOver is given words for maths it can't read as
//  written, and descriptions of the pictures it can't see, which say what the picture shows without
//  giving the answer. These tests check the navigation rules and those words.
//

import SwiftUI
import Testing
@testable import Maths_Quest

// MARK: - Navigation

struct Stage5CNavigationTests {
    @Test func aButtonOpensItsScreenOnTopOfTheScreenItIsOn() {
        #expect(AppNavigator.opening(.year(1), from: nil, in: []) == [.year(1)])
        #expect(AppNavigator.opening(.activity(.counting), from: .year(1), in: [.year(1)]) == [.year(1), .activity(.counting)])
    }

    @Test func aSecondTapAfterTheScreenHasOpenedDoesNothing() {
        // The first tap on Year 1 has opened it, and a second tap arrives from the main menu.
        #expect(AppNavigator.opening(.year(1), from: nil, in: [.year(1)]) == [.year(1)])
        // Two activity buttons tapped together.
        let afterFirst = AppNavigator.opening(.activity(.counting), from: .year(1), in: [.year(1)])
        #expect(AppNavigator.opening(.activity(.addition), from: .year(1), in: afterFirst) == afterFirst)
    }

    @Test func aScreenDoesNotOpenOnTopOfItself() {
        #expect(AppNavigator.opening(.settings, from: .settings, in: [.settings]) == [.settings])
    }

    @Test func theSidebarReplacesWhateverWasOpen() {
        #expect(AppNavigator.showing(.shop) == [.shop])
        #expect(AppNavigator.showing(.year(4)) == [.year(4)])
        #expect(AppNavigator.showing(nil) == [])
    }

    @MainActor @Test func homeAlwaysGoesBackToTheOriginalMainMenu() {
        let navigator = AppNavigator()
        navigator.open(.year(6), from: nil)
        navigator.open(.activity(.ratios), from: .year(6))
        #expect(navigator.path == [.year(6), .activity(.ratios)])
        navigator.goHome()
        #expect(navigator.path.isEmpty)
        navigator.show(.feedback)
        navigator.show(.removeAds)
        #expect(navigator.path == [.removeAds])
    }

    @Test func everyYearHasItsThreeActivitiesInMenuOrder() {
        let expected: [[String]] = [
            ["Counting", "Addition", "Subtraction"],
            ["Multiplication", "Division", "Shapes"],
            ["Fractions", "Measurement", "Time"],
            ["Decimals", "Geometry", "Money"],
            ["Percentages", "Statistics", "Volume"],
            ["Algebra", "Probability", "Ratios"],
        ]
        for year in 1...6 {
            #expect(Activity.activities(inYear: year).map(\.title) == expected[year - 1])
            #expect(Activity.activities(inYear: year).allSatisfy { $0.year == year })
        }
        #expect(Activity.allCases.count == 18)
    }
}

// MARK: - Text size

struct Stage5CTextSizeTests {
    @Test func theStandardTextSizeKeepsTheDesignedSize() {
        #expect(ScaledFont.pointSize(20, maximum: 34, for: .large) == 20)
    }

    @Test func smallerTextSizesNeverShrinkTheText() {
        #expect(ScaledFont.pointSize(20, maximum: 34, for: .xSmall) == 20)
    }

    @Test func largerTextSizesGrowUpToTheMaximum() {
        let larger = ScaledFont.pointSize(17, maximum: 34, for: .xxxLarge)
        #expect(larger > 17 && larger <= 34)
        #expect(ScaledFont.pointSize(17, maximum: 34, for: .accessibility5) == 34)
        #expect(ScaledFont.pointSize(17, maximum: 28, for: .accessibility3) == 28)
    }

    @Test func textAlreadyLargerThanTheMaximumIsLeftAlone() {
        #expect(ScaledFont.pointSize(40, maximum: 34, for: .accessibility5) == 40)
    }
}

// MARK: - Answer keyboards

struct Stage5CAnswerKeyboardTests {
    @Test func theIPadAsksForItsNumbersPageInsteadOfANumberPad() {
        #expect(AnswerKeyboard.type(.numberPad, on: .pad) == .numbersAndPunctuation)
        #expect(AnswerKeyboard.type(.decimalPad, on: .pad) == .numbersAndPunctuation)
    }

    @Test func iPhonesKeepTheirNumberPads() {
        #expect(AnswerKeyboard.type(.numberPad, on: .phone) == .numberPad)
        #expect(AnswerKeyboard.type(.decimalPad, on: .phone) == .decimalPad)
    }

    @Test func boxesForWordsKeepTheirKeyboard() {
        #expect(AnswerKeyboard.type(.default, on: .pad) == .default)
        #expect(AnswerKeyboard.type(.default, on: .phone) == .default)
    }
}

// MARK: - Spoken maths

struct Stage5CSpokenMathsTests {
    @Test func fractionsAreSaidAsTheyAreInClass() {
        #expect(SpokenMaths.fraction(numerator: 1, denominator: 2) == "1 half")
        #expect(SpokenMaths.fraction(numerator: 2, denominator: 4) == "2 quarters")
        #expect(SpokenMaths.fraction(numerator: 1, denominator: 3) == "1 third")
        #expect(SpokenMaths.fraction(numerator: 3, denominator: 10) == "3 tenths")
        #expect(SpokenMaths.fraction(numerator: 5, denominator: 12) == "5 twelfths")
        #expect(SpokenMaths.fraction(numerator: 5, denominator: 11) == "5 over 11")
    }

    @Test func everyFractionToSimplifyIsReadInWords() {
        // Year3FractionsView's fractions to simplify, written with small digits.
        let expected = ["²/₄": "2 quarters", "³/₆": "3 sixths", "⁴/₈": "4 eighths", "²/₆": "2 sixths", "⁴/₆": "4 sixths"]
        for (written, spoken) in expected {
            #expect(SpokenMaths.fraction(written) == spoken)
        }
        #expect(SpokenMaths.fraction("1/2") == "1 half")
        #expect(SpokenMaths.fraction("12") == nil)
        #expect(SpokenMaths.fraction("1/") == nil)
    }

    @Test func ratiosAreSaidWithTo() {
        #expect(SpokenMaths.ratio("6", "12") == "6 to 12")
    }

    @Test func multiplicationIsSaidAsTimes() {
        let question = Year2MultiplicationQuestion(first: 7, second: 5)
        #expect(question.text == "7 × 5")
        #expect(question.spokenText == "7 times 5")
    }

    @Test func decimalsAreSaidWithTheirOperation() {
        #expect(Year4DecimalsQuestion(kind: .add, first: 25, second: 40, multiplier: 1).spokenText == "What is 2.5 plus 4.0?")
        #expect(Year4DecimalsQuestion(kind: .subtract, first: 40, second: 25, multiplier: 1).spokenText == "What is 4.0 minus 2.5?")
        #expect(Year4DecimalsQuestion(kind: .multiply, first: 25, second: 0, multiplier: 3).spokenText == "What is 2.5 times 3?")
    }

    @Test func expandingSaysTheBrackets() {
        let expand = Year6AlgebraQuestion(kind: .expand, first: 5, second: 2, multiplier: 3)
        #expect(expand.expression == "3(5x + 2)")
        #expect(expand.spokenExpression == "3 times open bracket 5x plus 2 close bracket")
        #expect(Year6AlgebraQuestion(kind: .expand, first: 1, second: 4, multiplier: 2).spokenExpression
                == "2 times open bracket x plus 4 close bracket")
        let solve = Year6AlgebraQuestion(kind: .solve, first: 7, second: 12, multiplier: 2)
        #expect(solve.spokenExpression == solve.expression)
    }

    @Test func ratioQuestionsAreSaidWithoutGivingTheAnswer() {
        #expect(Year6RatioQuestion(kind: .simplify, first: 1, second: 2, multiplier: 6).spokenText
                == "Simplify the ratio 6 to 12")
        #expect(Year6RatioQuestion(kind: .share, first: 1, second: 2, multiplier: 6).spokenText
                == "Divide 18 in the ratio 1 to 2")
        let missingFirst = Year6RatioQuestion(kind: .missingFirst, first: 1, second: 2, multiplier: 6)
        #expect(missingFirst.spokenText == "Find the missing number. missing number to 12 equals 1 to 2")
        let missingSecond = Year6RatioQuestion(kind: .missingSecond, first: 1, second: 2, multiplier: 6)
        #expect(missingSecond.spokenText == "Find the missing number. 6 to missing number equals 1 to 2")
        // The missing values are 6 and 12.
        #expect(!missingFirst.spokenText.contains(" 6 ") && !missingFirst.spokenText.hasPrefix("6 "))
        #expect(!missingSecond.spokenText.contains("12"))
    }
}

// MARK: - Pictures

struct Stage5CPictureDescriptionTests {
    @Test func clockHandsAreDescribedWithoutSayingTheTime() {
        #expect(ClockMaths.handPositions(hour: 3, minute: 0)
                == "The short hour hand points at the 3. The long minute hand points at the 12.")
        #expect(ClockMaths.handPositions(hour: 15, minute: 25)
                == "The short hour hand is between the 3 and the 4. The long minute hand points at the 5.")
        #expect(ClockMaths.handPositions(hour: 0, minute: 27)
                == "The short hour hand is between the 12 and the 1. The long minute hand is 2 small marks past the 5.")
        #expect(ClockMaths.handPositions(hour: 11, minute: 1)
                == "The short hour hand is between the 11 and the 12. The long minute hand is 1 small mark past the 12.")
        #expect(ClockMaths.handPositions(hour: 23, minute: 59).hasSuffix("4 small marks past the 11."))
    }

    @Test func clockDescriptionsNeverSayTheTime() {
        for hour in 0..<24 {
            for minute in 0..<60 {
                let description = ClockMaths.handPositions(hour: hour, minute: minute)
                #expect(!description.contains(":"))
                #expect(!description.contains("o'clock"))
                #expect(!description.contains("minutes"))
            }
        }
    }

    @Test func turningTheClockCarriesTheHourAndWrapsAtTwelve() {
        func turned(_ hour: Int, _ minute: Int, by minutes: Int) -> [Int] {
            let clock = ClockMaths.turning(hour: hour, minute: minute, by: minutes)
            return [clock.hour, clock.minute]
        }
        #expect(turned(3, 10, by: 1) == [3, 11])
        #expect(turned(3, 59, by: 1) == [4, 0])
        #expect(turned(11, 59, by: 1) == [0, 0])
        #expect(turned(0, 0, by: -1) == [11, 59])
        #expect(turned(0, 2, by: -5) == [11, 57])
        #expect(turned(3, 10, by: 60) == [4, 10])
        #expect(turned(0, 10, by: -60) == [11, 10])
    }

    @Test func aClockTurnedToTheTimeIsMarkedCorrect() {
        // 3:45 PM, turned to from 12:00 a minute at a time as VoiceOver's swipe up does.
        var clock = (hour: 0, minute: 0)
        for _ in 0..<(3 * 60 + 45) {
            clock = ClockMaths.turning(hour: clock.hour, minute: clock.minute, by: 1)
        }
        #expect(ClockMaths.isCorrectlySet(clockHour: clock.hour, clockMinute: clock.minute, hour24: 15, minute: 45))
    }

    @Test func theRulerBarMovesACentimetreAtATimeAndStopsAtTheEnds() {
        let placement = RulerPlacement(objectLength: 4, scale: 20)
        let start = placement.startOffset
        let left = Int(placement.leftEdgeMark(at: start).rounded())
        #expect(placement.spokenPosition(at: start) == "Left end at \(left) centimetres, right end at \(left + 4) centimetres")
        let moved = placement.offset(movingBy: 1, from: start)
        #expect(Int(placement.leftEdgeMark(at: moved).rounded()) == left + 1)

        var offset = start
        for _ in 0..<30 {
            offset = placement.offset(movingBy: -1, from: offset)
        }
        #expect(placement.spokenPosition(at: offset) == "Left end at 0 centimetres, right end at 4 centimetres")
        for _ in 0..<30 {
            offset = placement.offset(movingBy: 1, from: offset)
        }
        #expect(placement.spokenPosition(at: offset) == "Left end at 11 centimetres, right end at 15 centimetres")
    }

    @Test func shapesAreDescribedByTheirLabelledSides() {
        let rectangle = Year4GeometryQuestion(question: 1, shapeType: 4, sides: [5, 3, 5, 3], angleMeasure: 45, unitType: "cm")
        #expect(rectangle.figureDescription
                == "A rectangle with sides of 5 centimetres, 3 centimetres, 5 centimetres and 3 centimetres.")
        let square = Year4GeometryQuestion(question: 2, shapeType: 4, sides: [7, 7, 7, 7], angleMeasure: 45, unitType: "m")
        #expect(square.figureDescription == "A square with sides of 7 metres, 7 metres, 7 metres and 7 metres.")
        let triangle = Year4GeometryQuestion(question: 1, shapeType: 3, sides: [3, 4, 5], angleMeasure: 45, unitType: "mm")
        #expect(triangle.figureDescription == "A triangle with sides of 3 millimetres, 4 millimetres and 5 millimetres.")
        let pentagon = Year4GeometryQuestion(question: 1, shapeType: 5, sides: [2, 3, 4, 5, 6], angleMeasure: 45, unitType: "km")
        #expect(pentagon.figureDescription.hasPrefix("A pentagon with sides of 2 kilometres, "))
    }

    @Test func shapeDescriptionsNeverGiveThePerimeterOrArea() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<500 {
            let question = Year4GeometryQuestion.random(using: &generator)
            guard question.question != 3 else { continue }
            let numbers = Set(question.figureDescription.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) })
            #expect(numbers == Set(question.sides), "\(question.figureDescription)")
            #expect(!question.figureDescription.contains("perimeter") && !question.figureDescription.contains("area"))
        }
    }

    @Test func anglesAreDescribedByWhichWayTheyOpenNotInDegrees() {
        func angle(_ degrees: Int) -> String {
            Year4GeometryQuestion(question: 3, shapeType: 3, sides: [3, 4, 5], angleMeasure: degrees, unitType: "cm")
                .figureDescription
        }
        #expect(angle(45) == "An angle. One arm points right, and the other points up and to the right.")
        #expect(angle(90) == "An angle. One arm points right, and the other points straight up.")
        #expect(angle(135) == "An angle. One arm points right, and the other points up and to the left.")
        for degrees in Year4GeometryQuestion.angles {
            let description = angle(degrees)
            #expect(!description.contains("\(degrees)"))
            #expect(!["acute", "right angle", "obtuse", "degree"].contains { description.lowercased().contains($0) })
        }
    }

    @Test func volumeShapesAreDescribedByTheirLabelledEdges() {
        let cuboid = Year5VolumeQuestion(kind: .cuboid, length: 4, width: 3, height: 2, glassAMillilitres: 0, glassBMillilitres: 0)
        #expect(cuboid.figureDescription == "A cuboid. Width 3 centimetres, length 4 centimetres, height 2 centimetres.")
        let cube = Year5VolumeQuestion(kind: .cube, length: 5, width: 5, height: 5, glassAMillilitres: 0, glassBMillilitres: 0)
        #expect(cube.figureDescription == "A cube. Width 5 centimetres, length 5 centimetres, height 5 centimetres.")
        #expect(!cube.figureDescription.contains("125"))
        #expect(!cuboid.figureDescription.contains("24"))
    }

    @Test func shopColoursSayTheirStrength() {
        let red = colours.first { $0.name == "Red" }!
        #expect(ShopView.accessibilityName(of: red, red.opacities[0]) == "Red, 70 percent")
        #expect(ShopView.accessibilityName(of: red, red.opacities[3]) == "Red, 100 percent")
    }
}

// MARK: - What VoiceOver reads

/// UI tests list elements that VoiceOver skips, so what VoiceOver reads is checked here instead: the view is put in a
/// window and its accessibility elements are walked the way VoiceOver walks them.
/// SwiftUI only builds its accessibility elements when something such as VoiceOver or UI testing is using them. This
/// turns that on for the test, as accessibility snapshot tools do.
private func enableAccessibility() {
    guard let library = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
          let symbol = dlsym(library, "_AXSSetAutomationEnabled") else { return }
    typealias SetEnabled = @convention(c) (Int32) -> Void
    unsafeBitCast(symbol, to: SetEnabled.self)(1)
}

@MainActor
private func spokenLabels<Content: View>(of view: Content, size: CGSize = CGSize(width: 390, height: 844)) -> [String] {
    enableAccessibility()
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first!
    let window = UIWindow(windowScene: scene)
    window.frame = CGRect(origin: .zero, size: size)
    let host = UIHostingController(rootView: view.environmentObject(AppNavigator()).environmentObject(GameData()))
    window.rootViewController = host
    window.isHidden = false
    host.view.setNeedsLayout()
    host.view.layoutIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    defer { window.isHidden = true }

    var labels: [String] = []
    func visit(_ object: NSObject) {
        if object.accessibilityElementsHidden { return }
        if let view = object as? UIView, view.isHidden { return }
        if object.isAccessibilityElement {
            labels.append(object.accessibilityLabel ?? "")
            return
        }
        if let elements = object.accessibilityElements as? [NSObject], !elements.isEmpty {
            elements.forEach(visit)
        } else if case let count = object.accessibilityElementCount(), count > 0, count != NSNotFound {
            (0..<count).compactMap { object.accessibilityElement(at: $0) as? NSObject }.forEach(visit)
        } else if let view = object as? UIView {
            view.subviews.forEach(visit)
        }
    }
    visit(host.view)
    return labels
}

@MainActor
struct Stage5CVoiceOverTests {
    @Test func textThatIsNotGroupedIsReadOnItsOwn() {
        // Shows the check finds text, so the pictures below are read as one description and not missed.
        #expect(spokenLabels(of: VStack { Text("5 cm"); Text("7 cm") }) == ["5 cm", "7 cm"])
    }

    @Test func theRulerIsReadAsOnePicture() {
        let labels = spokenLabels(of: RulerView().frame(width: 350, height: 40))
        #expect(labels == ["Ruler, marked from 0 to \(RulerPlacement.rulerLength) centimetres"])
    }

    @Test func theClockIsReadAsOnePictureWithoutItsNumbers() {
        let labels = spokenLabels(of: StationaryClockView(minute: .constant(25), hour: .constant(3), rotationCount: .constant(0))
            .frame(width: 250, height: 250))
        #expect(labels == ["Clock"])
    }

    @Test func aShapeIsReadAsItsDescription() {
        let question = Year4GeometryQuestion(question: 1, shapeType: 4, sides: [5, 3, 5, 3], angleMeasure: 45, unitType: "cm")
        let labels = spokenLabels(of: ShapeView(sides: question.shapeType, labels: question.sides, unitType: question.unitType)
            .frame(width: 160, height: 160)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(question.figureDescription)
            .accessibilityAddTraits(.isImage))
        #expect(labels == [question.figureDescription])
    }

    @Test func aCuboidIsReadAsItsDescription() {
        let question = Year5VolumeQuestion(kind: .cuboid, length: 4, width: 3, height: 2, glassAMillilitres: 0, glassBMillilitres: 0)
        let labels = spokenLabels(of: VolumeShapeView(side: 4, length: 4, width: 3, height: 2)
            .frame(width: 200, height: 200)
            .frame(width: 200, height: 150, alignment: .bottom)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(question.figureDescription)
            .accessibilityAddTraits(.isImage))
        #expect(labels == [question.figureDescription])
    }

    @Test func theOpenSidebarHidesTheScreenBehindIt() {
        let behind = VStack {
            Text("Screen behind")
            Button("Year 1") {}
        }
        let closed = spokenLabels(of: behind.sidebarOverlay(isOpen: .constant(false), selectedTab: "Main Menu"))
        #expect(closed == ["Screen behind", "Year 1"])

        let open = spokenLabels(of: behind.sidebarOverlay(isOpen: .constant(true), selectedTab: "Main Menu"))
        #expect(!open.contains("Screen behind"))
        #expect(open.first == "Close menu")
        #expect(open.filter { $0 == "Year 1" }.count == 1)
    }
}
