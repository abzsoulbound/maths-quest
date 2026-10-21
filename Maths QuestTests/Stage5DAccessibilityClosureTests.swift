//
//  Stage5DAccessibilityClosureTests.swift
//  Maths QuestTests
//
//  Stage 5D: VoiceOver users can answer the Year 2 Shapes questions by going round the shape's edge a part at a time,
//  without being told the answer. The navigation bar, shop prices and shop messages are coloured so they can be read
//  on every background colour, and a fraction's two answer boxes no longer share any of their tap area.
//

import SwiftUI
import Testing
@testable import Maths_Quest

// MARK: - Year 2 Shapes for VoiceOver

struct Stage5DShapeOutlineTests {
    private static let allQuestions: [Year2ShapeQuestion] = Year2ShapeQuestion.figures.indices.flatMap { index in
        [Year2ShapeQuestion.Kind.sides, .corners, .name].map { Year2ShapeQuestion(kind: $0, figureIndex: index) }
    }

    /// Every word VoiceOver is given for the picture, the hint included.
    private static func spokenWords(of question: Year2ShapeQuestion) -> [String] {
        [question.pictureLabel, Year2ShapeQuestion.pictureHint] + question.outline.indices.map(question.spokenLabel(ofPartAt:))
    }

    @Test func goingRoundTheEdgeMeetsEachCornerAndSideOnce() {
        for figure in Year2ShapeQuestion.figures {
            let question = Year2ShapeQuestion(kind: .corners, figureIndex: Year2ShapeQuestion.figures.firstIndex(of: figure)!)
            #expect(question.outline.filter { $0 == .corner }.count == figure.corners, "\(figure.name)")
            #expect(question.outline.filter { $0 == .straightSide }.count == figure.straightSides, "\(figure.name)")
        }
    }

    @Test func theCircleHasOneCurvedEdgeAndNothingElse() {
        let circle = Year2ShapeQuestion(kind: .sides, figureIndex: 0)
        #expect(circle.figure.name == "circle")
        #expect(circle.outline == [.curvedEdge])
    }

    @Test func cornersAndSidesTakeTurnsStartingAtTheTop() {
        for index in 1..<Year2ShapeQuestion.figures.count {
            let question = Year2ShapeQuestion(kind: .name, figureIndex: index)
            for (position, part) in question.outline.enumerated() {
                #expect(part == (position.isMultiple(of: 2) ? .corner : .straightSide))
            }
            #expect(question.spokenLabel(ofPartAt: 0) == "Corner at the top. The edge starts here.")
            #expect(question.spokenLabel(ofPartAt: question.outline.count - 1) == "Straight side, back to the corner at the top")
        }
    }

    @Test func eachPartIsWhereItIsDrawn() {
        let rect = CGRect(x: 0, y: 0, width: 80, height: 80)
        for index in 1..<Year2ShapeQuestion.figures.count {
            let question = Year2ShapeQuestion(kind: .name, figureIndex: index)
            let sides = question.figure.straightSides
            let corners = ShapeMaker.corners(sides: sides, in: rect)
            let points = question.outlinePoints(in: rect)
            #expect(points.count == question.outline.count)
            for i in 0..<sides {
                #expect(points[2 * i] == corners[i])
                let next = corners[(i + 1) % sides]
                #expect(abs(points[2 * i + 1].x - (corners[i].x + next.x) / 2) < 0.001)
                #expect(abs(points[2 * i + 1].y - (corners[i].y + next.y) / 2) < 0.001)
            }
            // The first corner is at the top and the next is to its right, so the edge goes round clockwise.
            #expect(abs(corners[0].x - 40) < 0.001 && abs(corners[0].y) < 0.001)
            #expect(corners[1].x > corners[0].x)
        }
    }

    @Test func nothingVoiceOverReadsNamesTheShapeOrCountsItsParts() {
        let names = Set(Year2ShapeQuestion.figures.map(\.name))
        let counts: Set<String> = ["no", "none", "zero", "nought", "one", "two", "three", "four", "five", "six", "seven",
                                   "eight", "once", "twice", "first", "second", "third", "last", "number"]
        let giveaways: Set<String> = ["sided", "gon", "curved", "rectangle", "oval", "ring", "circular"]
        for question in Self.allQuestions {
            for words in Self.spokenWords(of: question) {
                #expect(!words.contains { $0.isNumber }, "\(words)")
                let spoken = Set(words.lowercased().split { !$0.isLetter }.map(String.init))
                #expect(spoken.isDisjoint(with: names), "\(words)")
                #expect(spoken.isDisjoint(with: counts), "\(words)")
                // The circle's edge is described as curved, as touching it would show.
                if question.figure.straightSides > 0 {
                    #expect(spoken.isDisjoint(with: giveaways), "\(words)")
                }
            }
        }
    }

    @Test func whatIsReadDoesNotChangeWithTheQuestion() {
        // The same shape is read the same way whatever is asked, so the words can't hint at the kind of answer.
        for index in Year2ShapeQuestion.figures.indices {
            let readings = [Year2ShapeQuestion.Kind.sides, .corners, .name].map {
                Self.spokenWords(of: Year2ShapeQuestion(kind: $0, figureIndex: index))
            }
            #expect(readings.allSatisfy { $0 == readings[0] })
        }
    }

    @Test func countingThePartsAnswersEveryQuestion() {
        // What a VoiceOver user meets going round the edge is enough to answer, as the picture is for a sighted child.
        let shapeWithCorners = [0: "circle", 3: "triangle", 4: "square", 5: "pentagon", 6: "hexagon", 8: "octagon"]
        for question in Self.allQuestions {
            let labels = question.outline.indices.map(question.spokenLabel(ofPartAt:))
            let corners = labels.filter { $0.hasPrefix("Corner") }.count
            let sides = labels.filter { $0.hasPrefix("Straight side") }.count
            let answer: String
            switch question.kind {
            case .sides: answer = "\(sides)"
            case .corners: answer = "\(corners)"
            case .name: answer = shapeWithCorners[corners]!
            }
            #expect(question.evaluate(answer) == .correct, "\(question.figure.name), \(question.kind)")
        }
    }

    @Test func everyShapeHasADifferentEdge() {
        let outlines = Year2ShapeQuestion.figures.indices.map { Year2ShapeQuestion(kind: .name, figureIndex: $0).outline }
        #expect(Set(outlines.map(\.count)).count == outlines.count)
    }

    @Test func theQuestionsAndMarkingAreUnchanged() {
        #expect(Year2ShapeQuestion.figures.map(\.name) == ["circle", "triangle", "square", "pentagon", "hexagon", "octagon"])
        #expect(Year2ShapeQuestion.figures.map(\.straightSides) == [0, 3, 4, 5, 6, 8])
        #expect(Year2ShapeQuestion.figures.map(\.corners) == [0, 3, 4, 5, 6, 8])
        #expect(Year2ShapeQuestion(kind: .sides, figureIndex: 1).text == "How many straight sides does this shape have?")
        #expect(Year2ShapeQuestion(kind: .corners, figureIndex: 1).text == "How many corners does this shape have?")
        #expect(Year2ShapeQuestion(kind: .name, figureIndex: 1).text == "What is this shape called?")
        #expect(Year2ShapeQuestion(kind: .name, figureIndex: 3).evaluate("Pen ta gon") == .correct)
        #expect(Year2ShapeQuestion(kind: .corners, figureIndex: 3).evaluate("4") == .incorrect)
        #expect(Year2ShapeQuestion(kind: .sides, figureIndex: 0).evaluate(" ") == .unanswered)

        // Every shape and every kind of question still comes up.
        var generator = SystemRandomNumberGenerator()
        var seen = Set<String>()
        for _ in 0..<2000 {
            let question = Year2ShapeQuestion.random(using: &generator)
            seen.insert("\(question.figureIndex) \(question.kind)")
        }
        #expect(seen.count == 18)
    }

    @Test func theDrawnShapeIsUnchanged() {
        // ShapeMaker now gets its corners from `corners(sides:in:)`. The square is still drawn with a corner at the top.
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let square = ShapeMaker.corners(sides: 4, in: rect)
        let expected = [CGPoint(x: 50, y: 0), CGPoint(x: 100, y: 50), CGPoint(x: 50, y: 100), CGPoint(x: 0, y: 50)]
        for (corner, point) in zip(square, expected) {
            #expect(abs(corner.x - point.x) < 0.001 && abs(corner.y - point.y) < 0.001)
        }
        let drawn = ShapeMaker(sides: 4).path(in: rect).boundingRect
        #expect(abs(drawn.minX) < 0.001 && abs(drawn.minY) < 0.001 && abs(drawn.maxX - 100) < 0.001 && abs(drawn.maxY - 100) < 0.001)
    }
}

// MARK: - What VoiceOver reads on the Shapes screen

/// See Stage5CVoiceOverTests: the view is put in a window and its accessibility elements are walked the way VoiceOver
/// walks them, after turning on the accessibility SwiftUI only builds when something is using it.
private func enableAccessibility() {
    guard let library = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
          let symbol = dlsym(library, "_AXSSetAutomationEnabled") else { return }
    typealias SetEnabled = @convention(c) (Int32) -> Void
    unsafeBitCast(symbol, to: SetEnabled.self)(1)
}

private struct SpokenElement {
    let label: String
    let hint: String
    let traits: UIAccessibilityTraits
    let frame: CGRect
}

@MainActor
private func spokenElements<Content: View>(of view: Content, size: CGSize = CGSize(width: 390, height: 844)) -> [SpokenElement] {
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

    var found: [SpokenElement] = []
    func visit(_ object: NSObject) {
        if object.accessibilityElementsHidden { return }
        if let view = object as? UIView, view.isHidden { return }
        if object.isAccessibilityElement {
            found.append(SpokenElement(label: object.accessibilityLabel ?? "", hint: object.accessibilityHint ?? "",
                                       traits: object.accessibilityTraits, frame: object.accessibilityFrame))
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
    return found
}

@MainActor
struct Stage5DShapeVoiceOverTests {
    @Test func thePictureIsReadThenItsEdgeAPartAtATime() {
        for index in Year2ShapeQuestion.figures.indices {
            let question = Year2ShapeQuestion(kind: .corners, figureIndex: index)
            let elements = spokenElements(of: Year2ShapePicture(question: question, size: 78))
            let expected = [question.pictureLabel] + question.outline.indices.map(question.spokenLabel(ofPartAt:))
            #expect(elements.map(\.label) == expected, "\(question.figure.name)")
            #expect(elements.first?.hint == Year2ShapeQuestion.pictureHint)
            #expect(elements.first?.traits.contains(.image) == true)
            #expect(!elements.contains { $0.label == "A shape" })
        }
    }

    @Test(arguments: 1..<6)
    func movingOnFindsEachPartWhereItIsDrawnGoingClockwise(figureIndex: Int) {
        // Each spot is a corner or the middle of a side, in turn round the edge from the top.
        let question = Year2ShapeQuestion(kind: .sides, figureIndex: figureIndex)
        let elements = spokenElements(of: Year2ShapePicture(question: question, size: 78))
        // The picture's own frame is the drawn shape's outline, so the spots are measured from the corner at the top.
        let expected = question.outlinePoints(in: CGRect(x: 0, y: 0, width: 78, height: 78))
        let spots = elements.dropFirst().map { CGPoint(x: $0.frame.midX, y: $0.frame.midY) }
        #expect(spots.count == expected.count)
        guard let top = spots.first else { return }
        let parts = spots.map { CGPoint(x: $0.x - top.x + expected[0].x, y: $0.y - top.y + expected[0].y) }
        // Every spot is on the drawn picture.
        #expect(spots.allSatisfy { elements[0].frame.insetBy(dx: -1, dy: -1).contains($0) })
        for (part, point) in zip(parts, expected) {
            #expect(abs(part.x - point.x) < 1 && abs(part.y - point.y) < 1, "\(part) should be at \(point)")
        }
        // The spots are small enough not to cover each other.
        let frames = elements.dropFirst().map(\.frame)
        for (i, frame) in frames.enumerated() {
            for other in frames[(i + 1)...] {
                #expect(!frame.insetBy(dx: 0.5, dy: 0.5).intersects(other.insetBy(dx: 0.5, dy: 0.5)))
            }
        }
    }

    @Test func theScreenReadsThePictureBeforeTheQuestion() {
        let labels = spokenElements(of: NavigationStack { Year2ShapesView() }).map(\.label)
        let picture = labels.firstIndex { $0.hasPrefix("Shape picture") }
        let question = labels.firstIndex { $0.hasSuffix("does this shape have?") || $0 == "What is this shape called?" }
        #expect(picture != nil && question != nil, "\(labels)")
        if let picture, let question {
            #expect(picture < question)
            #expect(labels[(picture + 1)..<question].allSatisfy { $0.hasPrefix("Corner") || $0.hasPrefix("Straight side")
                || $0.hasPrefix("Curved edge") }, "\(labels)")
        }
        #expect(!labels.contains("A shape"))
        let names = Year2ShapeQuestion.figures.map(\.name)
        #expect(!labels.contains { label in names.contains { label.lowercased().contains($0) } }, "\(labels)")
    }
}

// MARK: - Contrast

struct Stage5DContrastTests {
    /// Every background the child can choose: each shop colour at each strength, and the colour a new player starts with.
    private static let backgrounds: [(hex: String, opacity: Double)] =
        colours.flatMap { colour in colour.opacities.map { (colour.hexCode, $0.opacity) } } + [("0000FF", 0.8)]

    @Test func contrastIsMeasuredAsWCAGDoes() {
        #expect(abs(Contrast.ratio(Contrast.black, Contrast.white) - 21) < 0.001)
        #expect(Contrast.ratio(Contrast.white, Contrast.white) == 1)
        // #777777 on white is the familiar 4.48:1.
        let grey = Contrast.RGB(red: 119 / 255, green: 119 / 255, blue: 119 / 255)
        #expect(abs(Contrast.ratio(grey, Contrast.white) - 4.48) < 0.01)
        #expect(Contrast.rgb(hex: "#0000FF") == Contrast.rgb(hex: "0000FF"))
        #expect(Contrast.rgb(hex: "#DC143C") == Contrast.RGB(red: 220 / 255, green: 20 / 255, blue: 60 / 255))
    }

    @Test func theOldGreyCouldNotBeReadOnTheStartingBlue() {
        // The measurements behind the fix: the grey nav-bar items on the 80% blue a new player starts with.
        let light = Contrast.background(hex: "0000FF", opacity: 0.8, colorScheme: .light)
        let dark = Contrast.background(hex: "0000FF", opacity: 0.8, colorScheme: .dark)
        #expect(abs(Contrast.ratio(Contrast.systemGrey, light) - 2.11) < 0.01)
        #expect(abs(Contrast.ratio(Contrast.systemGrey, dark) - 3.44) < 0.01)
    }

    @Test func theNavigationBarCanBeReadOnEveryBackground() {
        for scheme in [ColorScheme.light, .dark] {
            for background in Self.backgrounds {
                let behind = Contrast.background(hex: background.hex, opacity: background.opacity, colorScheme: scheme)
                let grey = Contrast.readableGrey(on: behind)
                #expect(Contrast.ratio(grey, behind) >= 4.5, "\(background) \(scheme)")
                // It stays a grey: the same amount of red, green and blue, give or take the system grey's tint.
                #expect(abs(grey.red - grey.green) < 0.001 && grey.blue >= grey.red)
            }
        }
    }

    @Test func theGreyIsOnlyChangedWhereItCannotBeRead() {
        let behind = Contrast.RGB(red: 0.05, green: 0.05, blue: 0.1)
        #expect(Contrast.ratio(Contrast.systemGrey, behind) >= 4.55)
        #expect(Contrast.readableGrey(on: behind) == Contrast.systemGrey)
    }

    @Test func shopPricesCanBeReadOnEverySwatch() {
        for scheme in [ColorScheme.light, .dark] {
            for background in Self.backgrounds {
                let behind = Contrast.background(hex: background.hex, opacity: background.opacity, colorScheme: scheme)
                for colour in colours {
                    for option in colour.opacities {
                        let swatch = ShopView.swatchColour(colour, option, on: behind)
                        let price = ShopView.priceColour(on: swatch)
                        #expect(Contrast.ratio(price, swatch) >= 4.5, "\(colour.name) \(option.opacity) on \(background) \(scheme)")
                        // Black, as before, wherever black can be read.
                        if Contrast.ratio(Contrast.black, swatch) >= 4.5 {
                            #expect(price == Contrast.black)
                        }
                        // The ticks on chosen and unlocked colours are icons, so they need 3:1.
                        #expect(Contrast.ratio(Contrast.blackOrWhite(on: swatch, minimum: 3), swatch) >= 3)
                        #expect(Contrast.ratio(Contrast.readableGrey(on: swatch, minimum: 3), swatch) >= 3)
                    }
                }
            }
        }
    }

    @Test func theDarkSwatchesThatHadBlackPricesNowHaveWhite() {
        let start = Contrast.background(hex: "0000FF", opacity: 0.8, colorScheme: .light)
        for name in ["Purple", "Indigo", "Violet"] {
            let colour = colours.first { $0.name == name }!
            let swatch = ShopView.swatchColour(colour, colour.opacities[3], on: start)
            #expect(Contrast.ratio(Contrast.black, swatch) < 4.5)
            #expect(ShopView.priceColour(on: swatch) == Contrast.white)
        }
        let green = colours.first { $0.name == "Green" }!
        #expect(ShopView.priceColour(on: ShopView.swatchColour(green, green.opacities[0], on: start)) == Contrast.black)
    }

    @Test func shopMessagesCanBeReadOnEveryBackground() {
        for scheme in [ColorScheme.light, .dark] {
            for background in Self.backgrounds {
                let behind = Contrast.background(hex: background.hex, opacity: background.opacity, colorScheme: scheme)
                #expect(Contrast.ratio(Contrast.blackOrWhite(on: behind, minimum: 3), behind) >= 3)
            }
        }
    }

    @Test func shopPricesAreUnchanged() {
        // Stage 5D changes only colours. Blue 80% is priced 0 in the catalogue (written "00"), as it has been since
        // the first commit.
        for colour in colours {
            let prices = colour.opacities.map(\.price)
            #expect(colour.opacities.map(\.opacity) == [0.7, 0.8, 0.9, 1.0], "\(colour.name)")
            #expect(prices == (colour.name == "Blue" ? [25, 0, 75, 100] : [25, 50, 75, 100]), "\(colour.name)")
        }
        #expect(colours.count == 15)
    }
}

// MARK: - Fraction answer boxes

struct Stage5DFractionTapAreaTests {
    private typealias TapArea = AnswerBoxMargin.TapArea

    /// The two boxes on a screen `screenHeight` points tall, as Year 3 Fractions and Year 6 Probability lay them out.
    private static func boxes(screenHeight: CGFloat, boxHeight: CGFloat? = nil) -> (numerator: CGRect, denominator: CGRect) {
        let frame = screenHeight * 0.04
        let height = boxHeight ?? frame
        let apart = frame + screenHeight * 0.005 + 10
        let numerator = CGRect(x: 0, y: 100 + (frame - height) / 2, width: 100, height: height)
        let areas = (
            TapArea(minHeight: 44, nextBox: .bottom, centresApart: apart).area(of: numerator),
            TapArea(minHeight: 44, nextBox: .top, centresApart: apart).area(of: numerator.offsetBy(dx: 0, dy: apart))
        )
        return areas
    }

    @Test func onTheIPhoneSETheTapAreasUsedToOverlapByFourPoints() {
        // The old tap area, the same amount above and below: 667 points is the iPhone SE's screen height.
        let frame = 667 * 0.04, apart = frame + 667 * 0.005 + 10
        let old = TapArea(minHeight: 44)
        let numerator = old.area(of: CGRect(x: 0, y: 0, width: 100, height: frame))
        let denominator = old.area(of: CGRect(x: 0, y: apart, width: 100, height: frame))
        #expect(abs((numerator.maxY - denominator.minY) - 4.0) < 0.05)
    }

    @Test func theTapAreasMeetWithoutOverlappingOnEveryScreen() {
        // iPhone SE, 13 mini, 17, 17 Pro, 17 Pro Max, iPad mini, iPad Pro 11-inch and 13-inch.
        for height: CGFloat in [667, 812, 844, 874, 956, 1133, 1210, 1376] {
            // The text field may be a little taller or shorter than the white box it sits in.
            for boxHeight in [height * 0.04, height * 0.04 + 4, height * 0.04 - 4] {
                let (numerator, denominator) = Self.boxes(screenHeight: height, boxHeight: boxHeight)
                #expect(numerator.maxY <= denominator.minY + 0.001, "\(height): \(numerator) \(denominator)")
                #expect(numerator.height >= 44 - 0.001 && denominator.height >= 44 - 0.001)
            }
        }
    }

    @Test func eachBoxStillReaches22PointsFromItsMiddleOnItsOuterSide() {
        let (numerator, denominator) = Self.boxes(screenHeight: 667)
        let numeratorMiddle = 100 + 667 * 0.04 / 2
        #expect(numeratorMiddle - numerator.minY >= 22)
        #expect(denominator.maxY - (numeratorMiddle + 667 * 0.04 + 667 * 0.005 + 10) >= 22)
    }

    @Test func whereThereIsRoomTheTapAreaIsTheSameAsBefore() {
        // On a 17 Pro the boxes are far enough apart that nothing changes.
        let frame = 874 * 0.04, apart = frame + 874 * 0.005 + 10
        let box = CGRect(x: 0, y: 0, width: 100, height: frame)
        #expect(TapArea(minHeight: 44, nextBox: .bottom, centresApart: apart).area(of: box) == TapArea(minHeight: 44).area(of: box))
        // A box that's already tall enough isn't changed at all.
        let tall = CGRect(x: 0, y: 0, width: 100, height: 50)
        #expect(TapArea(minHeight: 44, nextBox: .top, centresApart: 40).area(of: tall) == tall)
    }
}

// MARK: - The clock's and ruler's adjustable actions, used as VoiceOver uses them

/// A view hosted in a window, so its accessibility elements can be used the way VoiceOver uses them: swiping up or
/// down calls `accessibilityIncrement()` or `accessibilityDecrement()`, and the actions rotor calls a custom action.
@MainActor
private final class HostedElements {
    private let window: UIWindow

    init<Content: View>(_ view: Content, size: CGSize = CGSize(width: 390, height: 844)) {
        enableAccessibility()
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first!
        window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = UIHostingController(rootView: view)
        window.isHidden = false
        settle()
    }

    deinit {
        MainActor.assumeIsolated { window.isHidden = true }
    }

    func settle() {
        window.rootViewController?.view.setNeedsLayout()
        window.rootViewController?.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    }

    /// The element VoiceOver reads as `label`, found afresh each time, as SwiftUI may replace it after a change.
    func element(labelled label: String) -> NSObject? {
        func find(_ object: NSObject) -> NSObject? {
            if object.isAccessibilityElement {
                return object.accessibilityLabel == label ? object : nil
            }
            if let elements = object.accessibilityElements as? [NSObject], !elements.isEmpty {
                return elements.lazy.compactMap(find).first
            }
            if case let count = object.accessibilityElementCount(), count > 0, count != NSNotFound {
                return (0..<count).lazy.compactMap { object.accessibilityElement(at: $0) as? NSObject }.compactMap(find).first
            }
            return (object as? UIView)?.subviews.lazy.compactMap(find).first
        }
        return window.rootViewController.flatMap { find($0.view) }
    }

    func value(of label: String) -> String? {
        element(labelled: label)?.accessibilityValue
    }

    func increment(_ label: String) {
        element(labelled: label)?.accessibilityIncrement()
        settle()
    }

    func decrement(_ label: String) {
        element(labelled: label)?.accessibilityDecrement()
        settle()
    }

    func perform(_ action: String, on label: String) -> Bool {
        guard let custom = element(labelled: label)?.accessibilityCustomActions?.first(where: { $0.name == action }) else {
            return false
        }
        let done: Bool
        if let handler = custom.actionHandler {
            done = handler(custom)
        } else if let target = custom.target as? NSObject {
            done = target.perform(custom.selector, with: custom) != nil
        } else {
            done = false
        }
        settle()
        return done
    }
}

private struct SettableClock: View {
    @State var hour: Int
    @State var minute: Int

    var body: some View {
        InteractiveClockView(minute: $minute, hour: $hour)
            .frame(width: 300, height: 300)
    }
}

private struct BarOnTheRuler: View {
    let length: Int
    let scale: CGFloat
    @State private var offset: CGFloat = 0

    var body: some View {
        DraggableRectangleView(objectLength: length, scale: scale, offsetX: $offset)
            .frame(width: 15 * scale, height: 60)
    }
}

@MainActor
struct Stage5DAdjustableActionTests {
    private static let clock = "Clock to set"
    private static let bar = "Red bar to measure"

    @Test func theClockCanBeSetBySwipingUpAndDown() {
        let screen = HostedElements(SettableClock(hour: 3, minute: 58))
        let element = screen.element(labelled: Self.clock)
        #expect(element?.accessibilityTraits.contains(.adjustable) == true, "The clock isn't adjustable.")
        #expect(screen.value(of: Self.clock) == ClockMaths.handPositions(hour: 3, minute: 58))
        // Up a minute at a time, carrying the hour hand past the 4, then back down.
        var time = (hour: 3, minute: 58)
        for _ in 1...3 {
            screen.increment(Self.clock)
            time = ClockMaths.turning(hour: time.hour, minute: time.minute, by: 1)
            #expect(screen.value(of: Self.clock) == ClockMaths.handPositions(hour: time.hour, minute: time.minute))
        }
        #expect(time == (hour: 4, minute: 1))
        screen.decrement(Self.clock)
        #expect(screen.value(of: Self.clock) == ClockMaths.handPositions(hour: 4, minute: 0))
    }

    @Test func theClockGoesRoundPastTwelve() {
        let screen = HostedElements(SettableClock(hour: 0, minute: 0))
        screen.decrement(Self.clock)
        #expect(screen.value(of: Self.clock) == ClockMaths.handPositions(hour: 11, minute: 59))
        screen.increment(Self.clock)
        #expect(screen.value(of: Self.clock) == ClockMaths.handPositions(hour: 0, minute: 0))
    }

    @Test func theClocksActionsTurnItFiveMinutesOrAnHour() {
        let screen = HostedElements(SettableClock(hour: 6, minute: 30))
        let names = screen.element(labelled: Self.clock)?.accessibilityCustomActions?.map(\.name) ?? []
        #expect(names == ["Forward 5 minutes", "Back 5 minutes", "Forward 1 hour", "Back 1 hour"])
        for (action, expected) in [("Forward 5 minutes", (6, 35)), ("Forward 1 hour", (7, 35)),
                                   ("Back 5 minutes", (7, 30)), ("Back 1 hour", (6, 30))] {
            #expect(screen.perform(action, on: Self.clock), "\(action) didn't run.")
            #expect(screen.value(of: Self.clock) == ClockMaths.handPositions(hour: expected.0, minute: expected.1), "\(action)")
        }
    }

    @Test(arguments: [3, 7, 12])
    func theBarMovesACentimetreAtATimeAndStopsAtTheEnds(length: Int) {
        let scale: CGFloat = 20
        let placement = RulerPlacement(objectLength: length, scale: scale)
        let screen = HostedElements(BarOnTheRuler(length: length, scale: scale))
        #expect(screen.element(labelled: Self.bar)?.accessibilityTraits.contains(.adjustable) == true, "The bar isn't adjustable.")
        func left() -> Int? {
            screen.value(of: Self.bar)?.firstMatch(of: #/^Left end at (\d+) centimetres, right end at (\d+) centimetres$/#)
                .map { Int($0.1)! }
        }
        let start = Int(placement.leftEdgeMark(at: placement.startOffset).rounded())
        #expect(screen.value(of: Self.bar) == placement.spokenPosition(at: placement.startOffset))
        screen.increment(Self.bar)
        #expect(left() == start + 1)
        screen.decrement(Self.bar)
        screen.decrement(Self.bar)
        #expect(left() == start - 1)
        // Down to 0 and no further, then up to 15 and no further.
        for _ in 0..<20 { screen.decrement(Self.bar) }
        #expect(left() == 0)
        for _ in 0..<20 { screen.increment(Self.bar) }
        #expect(left() == RulerPlacement.rulerLength - length)
        #expect(screen.value(of: Self.bar) == "Left end at \(15 - length) centimetres, right end at 15 centimetres")
    }
}
