//
//  Stage6EPolishTests.swift
//  Maths QuestTests
//
//  Stage 6E: the final gameplay and layout polish. The layout tests check the sizes and positions the
//  clock, the volume diagram and the fraction boxes are drawn from, at every text size and on the
//  smallest and largest screens, so crowded or clipped parts fail here and not only in a screenshot.
//  The gameplay tests check that a blank answer is asked for, never marked, in every activity, that
//  the clock to set starts at 12:00 for each question, and the wording fixed in this stage.
//  Everything here is pure logic or reads ContentView.swift, so it runs without the simulator UI,
//  StoreKit or Firebase. Random questions come from SeededGenerator, so a failure can be reproduced.
//

import CoreGraphics
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Maths_Quest

// MARK: - Helpers

private enum Stage6ESource {
    static let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Maths Quest")
        .appendingPathComponent("ContentView.swift")

    static var isAvailable: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    static let activityViews = [
        "Year1CountingView", "Year1AdditionView", "Year1SubtractionView",
        "Year2MultiplicationView", "Year2DivisionView", "Year2ShapesView",
        "Year3FractionsView", "Year3MeasurementView", "Year3TimeView",
        "Year4DecimalsView", "Year4GeometryView", "Year4MoneyView",
        "Year5PercentagesView", "Year5StatisticsView", "Year5VolumeView",
        "Year6AlgebraView", "Year6ProbabilityView", "Year6RatiosView",
    ]

    struct Missing: Error {
        var name: String
    }

    static func source() throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    /// A top-level declaration, from `start` to the first closing brace at the start of a line.
    static func declaration(startingWith start: String) throws -> String {
        let source = try source()
        guard let begin = source.range(of: start),
              let end = source.range(of: "\n}\n", range: begin.upperBound..<source.endIndex) else {
            throw Missing(name: start)
        }
        return String(source[begin.lowerBound..<end.upperBound])
    }

    static func body(of view: String) throws -> String {
        try declaration(startingWith: "\nstruct \(view): View {")
    }

    /// The function whose declaration starts with `signature`, up to the brace that closes it.
    static func function(_ signature: String, in text: String) throws -> String {
        guard let begin = text.range(of: signature),
              let open = text[begin.upperBound...].firstIndex(of: "{") else {
            throw Missing(name: signature)
        }
        var depth = 0
        var index = open
        while index < text.endIndex {
            if text[index] == "{" {
                depth += 1
            } else if text[index] == "}" {
                depth -= 1
                if depth == 0 {
                    return String(text[begin.lowerBound...index])
                }
            }
            index = text.index(after: index)
        }
        throw Missing(name: signature)
    }

    static func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    static func lines(of text: String) -> [String] {
        text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

private enum Geometry {
    /// Allows for floating point rounding in positions worked out with square roots.
    static let tolerance: CGFloat = 0.001

    static func corners(of rect: CGRect) -> [CGPoint] {
        [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
         CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
    }

    /// True if the rectangles share more than an edge.
    static func overlap(_ a: CGRect, _ b: CGRect) -> Bool {
        min(a.maxX, b.maxX) - max(a.minX, b.minX) > tolerance && min(a.maxY, b.maxY) - max(a.minY, b.minY) > tolerance
    }

    static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }

    static func distance(from point: CGPoint, to segment: (CGPoint, CGPoint)) -> CGFloat {
        let (a, b) = segment
        let along = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let lengthSquared = along.x * along.x + along.y * along.y
        let t = lengthSquared == 0
            ? 0
            : max(0, min(1, ((point.x - a.x) * along.x + (point.y - a.y) * along.y) / lengthSquared))
        return hypot(point.x - (a.x + t * along.x), point.y - (a.y + t * along.y))
    }

    /// Whether any part of the segment is inside the rectangle or on its edge (Liang–Barsky clipping).
    static func crosses(_ segment: (CGPoint, CGPoint), _ rect: CGRect) -> Bool {
        let (a, b) = segment
        let dx = b.x - a.x
        let dy = b.y - a.y
        var entering: CGFloat = 0
        var leaving: CGFloat = 1
        for (p, q) in [(-dx, a.x - rect.minX), (dx, rect.maxX - a.x), (-dy, a.y - rect.minY), (dy, rect.maxY - a.y)] {
            if p == 0 {
                if q < 0 { return false }
            } else if p < 0 {
                entering = max(entering, q / p)
            } else {
                leaving = min(leaving, q / p)
            }
            if entering > leaving { return false }
        }
        return true
    }

    /// The shortest distance between a line and a rectangle: 0 if they touch. Otherwise it's from an end of the line
    /// to the rectangle, or from a corner of the rectangle to the line.
    static func distance(from segment: (CGPoint, CGPoint), to rect: CGRect) -> CGFloat {
        if crosses(segment, rect) { return 0 }
        let fromEnds = [segment.0, segment.1].map { distance(from: $0, to: rect) }
        let fromCorners = corners(of: rect).map { distance(from: $0, to: segment) }
        return (fromEnds + fromCorners).min()!
    }
}

/// The screens the app is laid out for: iPhone SE, iPhone 17 Pro, iPhone 17 Pro Max, iPad mini, iPad Air 11-inch and
/// iPad Pro 13-inch, in portrait.
private let screens = [
    CGSize(width: 375, height: 667), CGSize(width: 402, height: 874), CGSize(width: 440, height: 956),
    CGSize(width: 744, height: 1133), CGSize(width: 820, height: 1180), CGSize(width: 1032, height: 1376),
]

// MARK: - Geometry helpers

struct Stage6EGeometryHelperTests {
    /// The distance checks below are only as good as these.
    @Test func distancesBetweenLinesAndRectanglesAreExact() {
        let box = CGRect(x: 10, y: 10, width: 20, height: 10)
        #expect(Geometry.distance(from: (CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 0)), to: box) == 10)
        #expect(Geometry.distance(from: (CGPoint(x: 35, y: 15), CGPoint(x: 50, y: 15)), to: box) == 5)
        #expect(Geometry.distance(from: (CGPoint(x: 0, y: 15), CGPoint(x: 40, y: 15)), to: box) == 0)
        #expect(Geometry.distance(from: (CGPoint(x: 15, y: 12), CGPoint(x: 16, y: 13)), to: box) == 0)
        // Diagonal, passing the top right corner: the corner is closest.
        let diagonal = Geometry.distance(from: (CGPoint(x: 30, y: 0), CGPoint(x: 40, y: 10)), to: box)
        #expect(abs(diagonal - 10 / CGFloat(2).squareRoot()) < Geometry.tolerance)
        // Diagonal, crossing the rectangle without either end inside it.
        #expect(Geometry.distance(from: (CGPoint(x: 5, y: 5), CGPoint(x: 35, y: 25)), to: box) == 0)
        #expect(!Geometry.overlap(box, CGRect(x: 30, y: 10, width: 5, height: 5)))
        #expect(Geometry.overlap(box, CGRect(x: 29, y: 19, width: 5, height: 5)))
    }
}

// MARK: - The clock face

struct Stage6EClockFaceTests {
    /// The clocks are 200 to 300 points across.
    static let radii: [CGFloat] = [100, 110, 125, 137.5, 150]
    /// While the player types the time, the clock to read is drawn beside its instructions: 150 points across at
    /// the least, 181 on an iPhone SE and 197.2 on an iPhone 17 Pro (Stage 9B).
    static let compactRadii: [CGFloat] = [75, 77, 79, 90.5, 98.6]

    private static func box(of number: Int, in layout: ClockFaceLayout) -> CGRect {
        let size = ClockFaceLayout.numeralBox(number, size: layout.numeralSize)
        let centre = layout.centre(ofNumeral: number)
        return CGRect(x: centre.x - size.width / 2, y: centre.y - size.height / 2, width: size.width, height: size.height)
    }

    /// At the largest text sizes the numbers ran into the hour marks.
    @Test func numbersStayClearOfTheHourMarksAtEveryTextSize() {
        for dynamicTypeSize in DynamicTypeSize.allCases {
            let textSize = ScaledFont.pointSize(17, maximum: .greatestFiniteMagnitude, for: dynamicTypeSize)
            for radius in Self.radii + Self.compactRadii {
                let layout = ClockFaceLayout(radius: radius, textSize: textSize)
                let label = "\(dynamicTypeSize), radius \(radius)"
                #expect(layout.numeralSize == min(textSize, radius * ClockFaceLayout.largestNumeralSize), "\(label)")
                #expect(layout.numeralDistance > 0, "\(label)")
                let limit = ClockFaceLayout.hourMarksInnerEnd(radius: radius) - ClockFaceLayout.gap
                for number in 1...12 {
                    let farthest = Geometry.corners(of: Self.box(of: number, in: layout))
                        .map { hypot($0.x - radius, $0.y - radius) }
                        .max()!
                    #expect(farthest <= limit + Geometry.tolerance, "\(label): \(number) reaches \(farthest) of \(limit)")
                }
            }
        }
    }

    @Test func numbersNeverOverlapEachOther() {
        for dynamicTypeSize in DynamicTypeSize.allCases {
            let textSize = ScaledFont.pointSize(17, maximum: .greatestFiniteMagnitude, for: dynamicTypeSize)
            for radius in Self.radii + Self.compactRadii {
                let layout = ClockFaceLayout(radius: radius, textSize: textSize)
                for number in 1...12 {
                    let next = number % 12 + 1
                    #expect(!Geometry.overlap(Self.box(of: number, in: layout), Self.box(of: next, in: layout)),
                            "\(dynamicTypeSize), radius \(radius): \(number) and \(next)")
                }
            }
        }
    }

    /// At the usual text size the numbers are the size they've always been, and they only shrink below the reader's
    /// text size on a clock too small for it.
    @Test func numbersFollowTheTextSize() {
        for radius in Self.radii {
            #expect(ClockFaceLayout(radius: radius, textSize: 17).numeralSize == 17)
        }
        var previous: CGFloat = 0
        for dynamicTypeSize in DynamicTypeSize.allCases {
            let size = ClockFaceLayout(radius: 150, textSize: ScaledFont.pointSize(
                17, maximum: .greatestFiniteMagnitude, for: dynamicTypeSize)).numeralSize
            #expect(size >= previous, "\(dynamicTypeSize)")
            #expect(size <= 150 * ClockFaceLayout.largestNumeralSize)
            previous = size
        }
        // Each number is placed at its hour, clockwise from 12 at the top.
        let layout = ClockFaceLayout(radius: 100, textSize: 17)
        #expect(abs(layout.centre(ofNumeral: 12).x - 100) < Geometry.tolerance)
        #expect(layout.centre(ofNumeral: 12).y < 100)
        #expect(layout.centre(ofNumeral: 3).x > 100)
        #expect(abs(layout.centre(ofNumeral: 3).y - 100) < Geometry.tolerance)
        #expect(layout.centre(ofNumeral: 6).y > 100)
        #expect(layout.centre(ofNumeral: 9).x < 100)
    }
}

// MARK: - The volume diagram

struct Stage6EVolumeDiagramTests {
    private static func sizes(_ widths: [CGFloat], _ heights: [CGFloat]) -> [CGSize] {
        widths.flatMap { width in heights.map { CGSize(width: width, height: $0) } }
    }

    /// Measurements such as "3 cm" at the usual text size up to "12 cm" at the largest, with an outline or without.
    static let manySizes = sizes([20, 26, 34, 45, 60, 80, 100, 130, 160, 200], [14, 18, 20, 24, 29, 35, 41, 50, 60])
    static let someSizes = sizes([20, 45, 100, 200], [14, 29, 60])
    static let usualSize = CGSize(width: 40, height: 20)

    static let clearance = VolumeShapeLayout.lineWidth / 2 + VolumeShapeLayout.gap

    private static func labels(of layout: VolumeShapeLayout) -> [(String, CGRect)] {
        [("width", layout.widthLabel), ("length", layout.lengthLabel), ("height", layout.heightLabel)]
    }

    private static func lines(of layout: VolumeShapeLayout) -> [(CGPoint, CGPoint)] {
        let origin = layout.drawing.origin
        return VolumeShapeLayout.lines.map { start, end in
            (CGPoint(x: start.x + origin.x, y: start.y + origin.y), CGPoint(x: end.x + origin.x, y: end.y + origin.y))
        }
    }

    /// At the largest text sizes the measurements crowded the edges of the drawing, and the height sat on the dashed
    /// edge.
    @Test func everyMeasurementIsClearOfEveryLine() {
        for size in Self.manySizes {
            for changed in 0..<3 {
                var sizes = [Self.usualSize, Self.usualSize, Self.usualSize]
                sizes[changed] = size
                let layout = VolumeShapeLayout(width: sizes[0], length: sizes[1], height: sizes[2])
                for (name, frame) in Self.labels(of: layout) {
                    let closest = Self.lines(of: layout).map { Geometry.distance(from: $0, to: frame) }.min()!
                    #expect(closest >= Self.clearance - Geometry.tolerance, "\(name) at \(sizes): \(closest) from a line")
                }
            }
        }
    }

    @Test func theHeightIsBesideTheDashedEdgeAndClearOfIt() {
        for size in Self.manySizes {
            let layout = VolumeShapeLayout(width: Self.usualSize, length: Self.usualSize, height: size)
            let origin = layout.drawing.origin
            let dashed = (CGPoint(x: VolumeShapeLayout.heightEdge[0].x + origin.x, y: VolumeShapeLayout.heightEdge[0].y + origin.y),
                          CGPoint(x: VolumeShapeLayout.heightEdge[1].x + origin.x, y: VolumeShapeLayout.heightEdge[1].y + origin.y))
            let distance = Geometry.distance(from: dashed, to: layout.heightLabel)
            #expect(abs(distance - Self.clearance) < Geometry.tolerance, "\(size): \(distance)")
            // Level with the middle of the edge, so it's clear which edge it measures.
            #expect(abs(layout.heightLabel.midY - (dashed.0.y + dashed.1.y) / 2) < Geometry.tolerance)
        }
    }

    @Test func measurementsNeverOverlapAndAlwaysFitTheDiagram() {
        for width in Self.someSizes {
            for length in Self.someSizes {
                for height in Self.someSizes {
                    let layout = VolumeShapeLayout(width: width, length: length, height: height)
                    let bounds = CGRect(origin: .zero, size: layout.size)
                        .insetBy(dx: -Geometry.tolerance, dy: -Geometry.tolerance)
                    let labels = Self.labels(of: layout)
                    #expect(bounds.contains(layout.drawing))
                    for (index, (name, frame)) in labels.enumerated() {
                        #expect(bounds.contains(frame), "\(name) at \(width), \(length), \(height)")
                        // Moving the frames into place can change a size in the 14th decimal place, no more.
                        let measured = [width, length, height][index]
                        #expect(abs(frame.width - measured.width) < Geometry.tolerance
                                && abs(frame.height - measured.height) < Geometry.tolerance)
                        for (otherName, other) in labels[(index + 1)...] {
                            #expect(!Geometry.overlap(frame, other),
                                    "\(name) and \(otherName) at \(width), \(length), \(height)")
                        }
                    }
                    // Nothing spare round the edge: the diagram is as small as its parts allow, with room for their
                    // ink (the points of the drawing's corners and the measurements' outlines; see Stage 9B's
                    // `everythingTheCuboidDrawsIsInsideItsDiagram`).
                    let ink = VolumeShapeLayout.inkOverhang, outline = VolumeShapeLayout.outlineWidth
                    let everything = labels.map { $0.1.insetBy(dx: -outline, dy: -outline) }
                        .reduce(layout.drawing.insetBy(dx: -ink, dy: -ink)) { $0.union($1) }
                    #expect(abs(everything.minX) < Geometry.tolerance && abs(everything.minY) < Geometry.tolerance)
                    #expect(abs(everything.width - layout.size.width) < Geometry.tolerance)
                    #expect(abs(everything.height - layout.size.height) < Geometry.tolerance)
                }
            }
        }
    }
}

// MARK: - Fraction answer boxes

struct Stage6EFractionBoxTests {
    /// At the largest text sizes on the iPhone SE the placeholders and typed numbers were cut off.
    @Test func boxesFitTheirTextAtEveryTextSizeOnEveryScreen() {
        var previous: CGFloat = 0
        for dynamicTypeSize in DynamicTypeSize.allCases {
            let textSize = FractionBoxLayout.textSize(for: dynamicTypeSize)
            #expect(textSize >= previous && textSize >= 17 && textSize <= ScaledFont.usualMaximum)
            previous = textSize
            let font = UIFont.systemFont(ofSize: textSize)
            let widest = FractionBoxLayout.placeholders
                .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
                .max()!
            for screen in screens {
                let layout = FractionBoxLayout(textSize: textSize, screen: screen)
                let label = "\(dynamicTypeSize) on \(screen)"
                #expect(layout.textSize == textSize)
                #expect(layout.boxSize.height >= font.lineHeight + 2 * FractionBoxLayout.margin, "\(label)")
                #expect(layout.boxSize.width >= widest + 2 * FractionBoxLayout.margin, "\(label)")
                #expect(layout.boxSize.width <= screen.width - 32, "\(label)")
                #expect(layout.roomHeight >= layout.boxSize.height, "\(label)")
                #expect(layout.roomHeight >= screen.height * 0.04, "\(label)")
            }
        }
        #expect(FractionBoxLayout.textSize(for: .large) == 17)
    }

    /// At the usual text size the boxes are where they always were, except on the iPhone SE, where the old room was
    /// shorter than a line of text.
    @Test func theUsualTextSizeKeepsTheOldSpacing() {
        for screen in screens.dropFirst() {
            let layout = FractionBoxLayout(textSize: 17, screen: screen)
            #expect(layout.roomHeight == screen.height * 0.04, "\(screen)")
            #expect(layout.boxSize.width == screen.width * 0.3, "\(screen)")
            #expect(abs(layout.centresApart - (screen.height * 0.045 + 10)) < Geometry.tolerance, "\(screen)")
        }
        let iPhoneSE = FractionBoxLayout(textSize: 17, screen: screens[0])
        #expect(iPhoneSE.roomHeight == iPhoneSE.boxSize.height)
        #expect(iPhoneSE.roomHeight > screens[0].height * 0.04)
    }

    /// Each box can be tapped over at least 44 points, and the two never take each other's taps, however tall the
    /// text field inside the box turns out to be.
    @Test func tapAreasAreTallEnoughAndNeverOverlap() {
        for dynamicTypeSize in DynamicTypeSize.allCases {
            for screen in screens {
                let layout = FractionBoxLayout(textSize: FractionBoxLayout.textSize(for: dynamicTypeSize), screen: screen)
                for height in [layout.boxSize.height - 4, layout.boxSize.height, layout.boxSize.height + 4] {
                    let numerator = CGRect(x: 0, y: -height / 2, width: layout.boxSize.width, height: height)
                    let denominator = numerator.offsetBy(dx: 0, dy: layout.centresApart)
                    let numeratorArea = AnswerBoxMargin.TapArea(minHeight: 44, nextBox: .bottom,
                                                                centresApart: layout.centresApart).area(of: numerator)
                    let denominatorArea = AnswerBoxMargin.TapArea(minHeight: 44, nextBox: .top,
                                                                  centresApart: layout.centresApart).area(of: denominator)
                    let label = "\(dynamicTypeSize) on \(screen), field \(height) high"
                    #expect(numeratorArea.height >= 44 - Geometry.tolerance, "\(label)")
                    #expect(denominatorArea.height >= 44 - Geometry.tolerance, "\(label)")
                    let allowance = -Geometry.tolerance
                    #expect(numeratorArea.insetBy(dx: allowance, dy: allowance).contains(numerator), "\(label)")
                    #expect(denominatorArea.insetBy(dx: allowance, dy: allowance).contains(denominator), "\(label)")
                    #expect(numeratorArea.maxY <= denominatorArea.minY + Geometry.tolerance, "\(label)")
                }
            }
        }
    }
}

// MARK: - Blank answers

struct Stage6EBlankAnswerTests {
    static let blanks = ["", " ", "   ", "\n", " \t "]

    /// A blank answer is asked for in every activity, rather than marked wrong in some and asked for in others.
    @Test func blankAnswersAreUnansweredInEveryQuestionModel() {
        var generator = SeededGenerator(seed: 0x6E01)
        var setClocks = 0
        for _ in 0..<600 {
            let multiplication = Year2MultiplicationQuestion.random(using: &generator)
            let shape = Year2ShapeQuestion.random(using: &generator)
            let time = Year3TimeQuestion.random(using: &generator)
            let decimals = Year4DecimalsQuestion.random(using: &generator)
            let geometry = Year4GeometryQuestion.random(using: &generator)
            let probability = Year6ProbabilityQuestion.random(using: &generator)
            let ratio = Year6RatioQuestion.random(using: &generator)
            if case .setClock = time.kind { setClocks += 1 }
            for blank in Self.blanks {
                #expect(multiplication.evaluate(blank) == .unanswered)
                #expect(shape.evaluate(blank) == .unanswered)
                // The clock to set is answered with its hands; untouched, they're no answer.
                #expect(time.evaluate(hours: blank, minutes: blank) == .unanswered, "\(time.kind)")
                #expect(decimals.evaluate(blank) == .unanswered)
                #expect(geometry.evaluate(answer: blank, unit: geometry.correctUnit ?? "") == .unanswered)
                #expect(probability.evaluate(numerator: blank, denominator: blank) == .unanswered)
                #expect(ratio.evaluate(first: blank, second: blank, missing: blank) == .unanswered)
            }
        }
        #expect(setClocks > 50)
    }

    /// Only both boxes empty is no answer. One box filled in is still asked to be finished.
    @Test func aHalfFinishedProbabilityIsInvalidNotUnanswered() {
        let question = Year6ProbabilityQuestion.die(faces: 6, target: 2)
        #expect(question.evaluate(numerator: "1", denominator: "") == .invalidInput)
        #expect(question.evaluate(numerator: " ", denominator: "6") == .invalidInput)
        #expect(question.evaluate(numerator: "1", denominator: "0") == .invalidInput)
        #expect(question.evaluate(numerator: "", denominator: "") == .unanswered)
        #expect(question.evaluate(numerator: "1", denominator: "6") == .correct)
    }

    @Test func aBlankAngleNameIsUnanswered() {
        let angle = Year4GeometryQuestion(question: 3, shapeType: 3, sides: [3, 4, 5], angleMeasure: 45, unitType: "cm")
        for blank in Self.blanks {
            #expect(angle.evaluate(answer: blank, unit: "") == .unanswered)
        }
        #expect(angle.evaluate(answer: "Acute", unit: "") == .correct)
        #expect(angle.evaluate(answer: "obtuse", unit: "") == .incorrect)
    }
}

@Suite(.enabled(if: Stage6ESource.isAvailable, "ContentView.swift isn't reachable from this test run"))
struct Stage6EBlankAnswerWiringTests {
    static let message = "responseMessage = \"Please enter an answer!\""

    /// Every activity asks for an answer the same way: before anything is marked, without a point, and without the
    /// press counting towards Skip.
    @Test(arguments: Stage6ESource.activityViews)
    func aBlankAnswerIsAskedForBeforeAnythingIsMarked(view: String) throws {
        let check = try Stage6ESource.function("func checkAnswer(", in: Stage6ESource.body(of: view))
        #expect(Stage6ESource.count(Self.message, in: check) == 1, "\(view)")
        let lines = Stage6ESource.lines(of: check)
        guard let ignoreLine = lines.firstIndex(of: "guard !progress.isAdvancing else { return }"),
              let messageLine = lines.firstIndex(of: Self.message),
              let firstMark = lines.firstIndex(where: {
                  $0.contains("progress.record") || $0.contains("gameData.points += 1")
              }) else {
            Issue.record("\(view) doesn't ask for a blank answer before marking")
            return
        }
        #expect(ignoreLine < messageLine, "\(view)")
        #expect(messageLine < firstMark, "\(view)")
        let next = lines[(messageLine + 1)...].filter { !$0.isEmpty }.prefix(2)
        #expect(next.first == "showFeedback()", "\(view)")
        let after = next.dropFirst().first ?? ""
        #expect(after == "return" || after.hasPrefix("case "), "\(view): \(after)")
    }
}

// MARK: - The clock to set

struct Stage6EClockToSetTests {
    /// The clock used to keep where the last question's hands were left, so the next question could be right, or
    /// half set, before the child touched it.
    @Test func untouchedHandsAreNoAnswerAndTheTargetIsNeverTwelve() {
        var generator = SeededGenerator(seed: 0x6E02)
        var setClocks = 0
        for _ in 0..<5_000 {
            let question = Year3TimeQuestion.random(using: &generator)
            guard case let .setClock(hour, minute) = question.kind else { continue }
            setClocks += 1
            #expect(!(hour % 12 == 0 && minute == 0), "\(hour):\(minute)")
            #expect(question.evaluate(hours: "", minutes: "", clockHour: 0, clockMinute: 0) == .unanswered)
            #expect(question.evaluate(hours: "", minutes: "", clockHour: 12, clockMinute: 0) == .unanswered)
            #expect(question.evaluate(hours: "", minutes: "", clockHour: hour % 12, clockMinute: minute) == .correct)
            let wrong = ClockMaths.turning(hour: hour % 12, minute: minute, by: hour % 12 == 11 && minute == 59 ? -1 : 1)
            #expect(question.evaluate(hours: "", minutes: "", clockHour: wrong.hour, clockMinute: wrong.minute) == .incorrect)
        }
        #expect(setClocks > 500)
    }

    @Test func aFreshClockSaysItPointsAtTwelve() {
        #expect(ClockMaths.handPositions(hour: 0, minute: 0)
                == "The short hour hand points at the 12. The long minute hand points at the 12.")
    }
}

@Suite(.enabled(if: Stage6ESource.isAvailable, "ContentView.swift isn't reachable from this test run"))
struct Stage6EClockStateWiringTests {
    @Test func theHandsBelongToTheTimeScreenAndGoBackToTwelve() throws {
        let view = try Stage6ESource.body(of: "Year3TimeView")
        #expect(view.contains("@State private var clockHour = 0"))
        #expect(view.contains("@State private var clockMinute = 0"))
        #expect(view.contains("minute: $clockMinute"))
        #expect(view.contains("hour: $clockHour"))
        let reset = try Stage6ESource.function("private func resetQuestion(", in: view)
        #expect(reset.contains("clockHour = 0"))
        #expect(reset.contains("clockMinute = 0"))
        // A correct answer and a skip both start the next question through resetQuestion.
        #expect(view.contains("gameData.skipQuestion(resetQuestion: resetQuestion)"))
        let check = try Stage6ESource.function("func checkAnswer(", in: view)
        #expect(check.contains("resetQuestion()"))
        #expect(check.contains("clockHour: clockHour, clockMinute: clockMinute"))

        // Nothing about the clock is kept app-wide, where it outlived the screen.
        let gameData = try Stage6ESource.declaration(startingWith: "\nclass GameData: ObservableObject {")
        #expect(!gameData.lowercased().contains("clock"))
        let clock = try Stage6ESource.declaration(startingWith: "\nstruct InteractiveClockView: View {")
        #expect(clock.contains("@Binding var minute: Int"))
        #expect(clock.contains("@Binding var hour: Int"))
        #expect(!clock.contains("@State"))
        #expect(!clock.contains("gameData"))
    }
}

// MARK: - Reading the clock and other typed numbers

struct Stage6ETypedNumberTests {
    /// "+3" was read as 3 when reading a clock.
    @Test func onlyDigitsAreReadAsAClockTime() {
        // 3:15 PM, answered in 12-hour time.
        for hours in ["+3", "3.", " +3", "-3", "３", "15", "3 0", "three", "3:15"] {
            #expect(!ClockMaths.isCorrectReading(hours: hours, minutes: "15", hour24: 15, minute: 15), "\(hours)")
        }
        for minutes in ["+15", "15.", "-15", "１５", "1 5", "75"] {
            #expect(!ClockMaths.isCorrectReading(hours: "3", minutes: minutes, hour24: 15, minute: 15), "\(minutes)")
        }
        for (hours, minutes) in [("3", "15"), (" 3 ", "15"), ("03", "15"), ("3", " 15 ")] {
            #expect(ClockMaths.isCorrectReading(hours: hours, minutes: minutes, hour24: 15, minute: 15),
                    "\(hours):\(minutes)")
        }
        #expect(ClockMaths.isCorrectReading(hours: "12", minutes: "05", hour24: 0, minute: 5))
        #expect(!ClockMaths.isCorrectReading(hours: "0", minutes: "05", hour24: 0, minute: 5))

        let question = Year3TimeQuestion(kind: .readClock(hour: 15, minute: 15))
        #expect(question.evaluate(hours: "+3", minutes: "15") == .incorrect)
        #expect(question.evaluate(hours: "3", minutes: "+15") == .incorrect)
        #expect(question.evaluate(hours: "3", minutes: "15") == .correct)
        #expect(question.evaluate(hours: "", minutes: "") == .unanswered)
    }

    /// Geometry read "+12" as 12; every other activity reads digits only.
    @Test func geometryReadsOnlyDigits() {
        let triangle = Year4GeometryQuestion(question: 1, shapeType: 3, sides: [3, 4, 5], angleMeasure: 45, unitType: "cm")
        #expect(triangle.perimeter == 12)
        #expect(triangle.evaluate(answer: "+12", unit: "cm") == .incorrect)
        #expect(triangle.evaluate(answer: "12.0", unit: "cm") == .incorrect)
        #expect(triangle.evaluate(answer: "1 2", unit: "cm") == .incorrect)
        #expect(triangle.evaluate(answer: "12", unit: "cm") == .correct)
        #expect(triangle.evaluate(answer: " 12 ", unit: "cm") == .correct)
        #expect(triangle.evaluate(answer: "012", unit: "cm") == .correct)
        #expect(triangle.evaluate(answer: "12", unit: "mm") == .wrongUnit)
    }
}

// MARK: - Wording

struct Stage6EWordingTests {
    /// "Square." and "hexagon!" were marked wrong.
    @Test func shapeNamesIgnorePunctuationAtEitherEnd() {
        let hexagon = Year2ShapeQuestion(kind: .name, figureIndex: 4)
        #expect(hexagon.figure.name == "hexagon")
        for typed in ["Hexagon.", "hexagon!", " hexagon? ", "HEXAGON", "hexa gon", "hexagon", "\"hexagon\"", "hexagon..."] {
            #expect(hexagon.evaluate(typed) == .correct, "\(typed)")
        }
        for typed in [".", "hex-agon", "hexagons", "pentagon", "hexagon 6", "!?"] {
            #expect(hexagon.evaluate(typed) == .incorrect, "\(typed)")
        }
        for (index, figure) in Year2ShapeQuestion.figures.enumerated() {
            let question = Year2ShapeQuestion(kind: .name, figureIndex: index)
            #expect(question.evaluate(figure.name.capitalized + ".") == .correct, "\(figure.name)")
            #expect(question.evaluate(" " + figure.name + "! ") == .correct, "\(figure.name)")
        }
        // Counting answers are still digits only.
        let sides = Year2ShapeQuestion(kind: .sides, figureIndex: 4)
        #expect(sides.evaluate("6") == .correct)
        #expect(sides.evaluate("6.") == .incorrect)
    }

    /// Year 2 Multiplication was written "7 x 5" with the letter x.
    @Test func multiplicationIsWrittenWithATimesSign() throws {
        let pattern = try Regex(#"^\d+ × \d+$"#)
        var generator = SeededGenerator(seed: 0x6E03)
        for _ in 0..<500 {
            let question = Year2MultiplicationQuestion.random(using: &generator)
            #expect(question.text.wholeMatch(of: pattern) != nil, "\(question.text)")
            #expect(question.text == "\(question.first) × \(question.second)")
            #expect(question.spokenText == "\(question.first) times \(question.second)")
            #expect(question.evaluate("\(question.product)") == .correct)
        }
        let decimals = Year4DecimalsQuestion(kind: .multiply, first: 25, second: 0, multiplier: 4)
        #expect(decimals.text == "What is 2.5 × 4?")
        #expect(decimals.spokenText == "What is 2.5 times 4?")
        #expect(decimals.evaluate("10") == .correct)
    }

    /// Ratios were written "6:12" in some questions and "6 : 12" in others, and "Divide 18 into the ratio" read as
    /// dividing into parts.
    @Test func ratiosAreWrittenTheSameWayEverywhere() {
        var generator = SeededGenerator(seed: 0x6E04)
        var kinds = [String: Int]()
        for _ in 0..<5_000 {
            let question = Year6RatioQuestion.random(using: &generator)
            let (f, s, m) = (question.first, question.second, question.multiplier)
            let text = question.text
            kinds["\(question.kind)", default: 0] += 1
            #expect(text.filter { $0 == ":" }.count == Stage6ESource.count(" : ", in: text), "\(text)")
            #expect(!text.contains("  ") && !text.contains("into"), "\(text)")
            switch question.kind {
            case .simplify:
                #expect(text == "Simplify the ratio \(f * m) : \(s * m)")
            case .share:
                #expect(text == "Divide \((f + s) * m) in the ratio \(f) : \(s)")
                #expect(question.spokenText == "Divide \((f + s) * m) in the ratio \(f) to \(s)")
                #expect(question.evaluate(first: "\(f * m)", second: "\(s * m)", missing: "") == .correct)
            case .missingFirst:
                #expect(text == "Find the missing number.\n___ : \(s * m) = \(f) : \(s)")
                #expect(question.evaluate(first: "", second: "", missing: "\(f * m)") == .correct)
            case .missingSecond:
                #expect(text == "Find the missing number.\n\(f * m) : ___ = \(f) : \(s)")
                #expect(question.evaluate(first: "", second: "", missing: "\(s * m)") == .correct)
            }
            let spoken = question.spokenText
            #expect(!spoken.contains(":") && !spoken.contains("_") && !spoken.contains("  "), "\(spoken)")
        }
        #expect(kinds.count == 4)
    }

    /// "A fair die has 7 faces" left it to the child to assume the faces are equally likely.
    @Test func everyDieSaysEachNumberIsEquallyLikely() {
        for faces in 4...10 {
            for target in 1...faces {
                let die = Year6ProbabilityQuestion.die(faces: faces, target: target)
                #expect(die.text == "A fair die has \(faces) faces, numbered 1 to \(faces). "
                        + "Each number is equally likely to be rolled. What is the probability of rolling a \(target)?")
                #expect(die.probability.numerator == 1 && die.probability.denominator == faces)
                #expect(die.evaluate(numerator: "1", denominator: "\(faces)") == .correct)
                #expect(die.evaluate(numerator: "2", denominator: "\(2 * faces)") == .correct)
                let expected: Year6ProbabilityQuestion.Outcome = target == 1 ? .correct : .incorrect
                #expect(die.evaluate(numerator: "\(target)", denominator: "\(faces)") == expected)
            }
        }
        var generator = SeededGenerator(seed: 0x6E05)
        var dice = 0
        for _ in 0..<5_000 {
            guard case let .die(faces, target) = Year6ProbabilityQuestion.random(using: &generator) else { continue }
            dice += 1
            #expect((4...10).contains(faces) && (1...faces).contains(target))
        }
        #expect(dice > 500)
    }
}

// MARK: - Layout wiring

struct Stage6EBarChartTests {
    /// The tallest bar is the chart's height, so a chart made shorter to fit the screen still shows every bar.
    @Test func noBarIsTallerThanTheTallestBar() {
        var generator = SeededGenerator(seed: 0x6E06)
        for _ in 0..<2_000 {
            let bars = Year5StatisticsQuestion.barData(using: &generator)
            #expect(bars.count == 4)
            #expect(bars.values.allSatisfy { (1...15).contains($0) })
            #expect(Set(bars.values).count == 4)
        }
    }
}

@Suite(.enabled(if: Stage6ESource.isAvailable, "ContentView.swift isn't reachable from this test run"))
struct Stage6ELayoutWiringTests {
    /// At the largest text sizes "Points: 5,000" wrapped and ran into the screen's title.
    ///
    /// Updated deliberately in Stage 9B. The points moved from the middle of the bar to one chip at the right, beside
    /// Settings, in the same place on every screen. So the narrow row has one flexible gap (after the leading button),
    /// not one on each side of the points, and `Spacer(minLength: 4)` appears once instead of twice. Every other check
    /// is unchanged. The new checks below hold the Stage 9A defect D4: the bar used to fill the empty side with an
    /// invisible, disabled gear and a blank text, which VoiceOver still found and which made the header taller.
    ///
    /// Updated deliberately again in the Stage 9B final corrections. Before the points go under the buttons, the narrow
    /// row is tried once more with the chip's star left out, so there are two narrow rows, each with one flexible gap:
    /// `Spacer(minLength: 4)` appears twice and `compact: true)` four times, and the new row must come after the first
    /// narrow row and before the points under the buttons. Every other check is unchanged.
    @Test func theHeaderOnlyStacksThePointsWhenTheyDontFitBesideTheButtons() throws {
        let bar = try Stage6ESource.declaration(startingWith: "\nstruct NavigationBar: View {")
        let body = try Stage6ESource.function("var body: some View", in: bar)
        #expect(body.contains("ViewThatFits(in: .horizontal)"))
        #expect(Stage6ESource.count("Spacer(minLength: 4)", in: body) == 2)
        #expect(body.contains(".fixedSize(horizontal: false, vertical: true)"))
        // One points chip, and nothing invisible standing in for a missing button.
        #expect(bar.contains("PointsChip("))
        #expect(!bar.contains("Text(\" \")"))
        #expect(!bar.contains(".disabled(true)"))
        #expect(!bar.contains("accessibilityHidden(true)"))
        // The usual row first, then the row with narrower button margins, then that row with the narrow chip, then
        // the points under the buttons.
        let usual = try #require(body.range(of: "leadingButton(compact: false)"))
        let compact = try #require(body.range(of: "leadingButton(compact: true)"))
        let stacked = try #require(body.range(of: "VStack(spacing: 0)"))
        #expect(usual.lowerBound < compact.lowerBound && compact.lowerBound < stacked.lowerBound)
        let narrow = try #require(body.range(of: "pointsChip(height: rowHeight, narrow: true)"))
        #expect(compact.lowerBound < narrow.lowerBound && narrow.lowerBound < stacked.lowerBound)
        #expect(Stage6ESource.count("compact: true)", in: body) == 4)
        // Narrower margins never make a button smaller than 44 points to tap.
        #expect(bar.contains(".frame(minWidth: compact ? 44 : nil)"))
        #expect(bar.contains(".contentShape(Rectangle())"))
    }

    /// The bar chart's numbers and letters overlapped the answer box at the largest text sizes.
    @Test func barChartsShrinkToFitAndKeepTheirTextInBounds() throws {
        let chart = try Stage6ESource.declaration(startingWith: "\nstruct BarGraphView: View {")
        #expect(Stage6ESource.count(".scaledFont(size: 17)", in: chart) == 2)
        #expect(chart.contains("CGFloat(value) * tallestBar / 15"))
        let statistics = try Stage6ESource.body(of: "Year5StatisticsView")
        #expect(statistics.contains("BarGraphView(data: current.bars, tallestBar: tallestBar)"))
        #expect(statistics.contains(".fitOnScreen(by: $tallestBar"))
        #expect(!statistics.contains(".frame(height: 200)"))
    }

    /// The probability question scrolled under the header and its feedback appeared below the screen.
    ///
    /// Updated deliberately in Stage 9B (D9): the working-out pad now goes below Enter, so the end of the question is
    /// the pad, not the row with Enter. Scrolling to the end, as iOS 18 and later did, would pass the row and on a
    /// small screen hide the top of the question, so every version now scrolls to the row itself once the message is
    /// in. Every other check is unchanged.
    @Test func probabilityKeepsItsQuestionAnswerAndFeedbackOnScreen() throws {
        let probability = try Stage6ESource.body(of: "Year6ProbabilityView")
        #expect(probability.contains("WorkingOutView(canvasView: $canvasView, padHeight: padHeight)"))
        #expect(probability.contains(".fitOnScreen(by: $padHeight"))
        #expect(probability.contains("FractionAnswerBoxes(numerator: $numerator, denominator: $denominator)"))
        let feedback = try Stage6ESource.declaration(startingWith: "\nstruct AnswerFeedbackText: View {")
        #expect(feedback.contains("revealSubmitRow()"))
        let layout = try Stage6ESource.declaration(startingWith: "\nstruct QuestionLayout<Content: View>: View {")
        #expect(layout.contains(".modifier(RevealSubmitRowByScrolling(scroller: scroller))"))
        // The scroll waits until the message is in the question, so it isn't stopped at the question's old height.
        let reveal = try Stage6ESource.declaration(startingWith: "\nprivate struct RevealSubmitRowByScrolling: ViewModifier {")
        #expect(reveal.contains(".environment(\\.revealSubmitRow, RevealSubmitRow {"))
        #expect(reveal.contains("DispatchQueue.main.async"))
        #expect(reveal.contains("scroller.scrollTo(QuestionSubmitRow.id, anchor: .bottom)"))
        let source = try Stage6ESource.source()
        #expect(!source.contains("ScrollToTheEnd"))
        #expect(!source.contains("scrollTo(edge:"))
    }

    @Test func volumeIsLaidOutFromItsMeasurementsAndFitsItsPad() throws {
        let volume = try Stage6ESource.body(of: "Year5VolumeView")
        #expect(volume.contains("WorkingOutView(canvasView: $canvasView, padHeight: padHeight)"))
        #expect(volume.contains(".fitOnScreen(by: $padHeight"))
        let shape = try Stage6ESource.declaration(startingWith: "\nstruct VolumeShapeView: View {")
        #expect(shape.contains("VolumeShapeArrangement"))
    }

    /// Multiplication is never written with the letter x. The only x left is the unknown in algebra.
    @Test func noQuestionWritesTimesAsTheLetterX() throws {
        let source = try Stage6ESource.source()
        #expect(!source.contains(") x \\("))
    }
}
