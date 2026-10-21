//
//  MathematicalCorrectnessTests.swift
//  Maths QuestTests
//
//  Regression tests for the Year 3 Time clocks and Year 4 Geometry questions. Everything here
//  is pure maths, so it runs without the simulator UI, StoreKit or Firebase.
//

import CoreGraphics
import Foundation
import Testing
@testable import Maths_Quest

/// SplitMix64, so the large sampled tests are reproducible.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Year 3 Time: reading a clock (MQ-07)

struct ClockReadingTests {
    @Test func twelveHourConversion() {
        #expect(ClockMaths.twelveHour(0) == 12)
        #expect(ClockMaths.twelveHour(1) == 1)
        #expect(ClockMaths.twelveHour(11) == 11)
        #expect(ClockMaths.twelveHour(12) == 12)
        #expect(ClockMaths.twelveHour(13) == 1)
        #expect(ClockMaths.twelveHour(23) == 11)
    }

    @Test func amPmLabel() {
        #expect(!ClockMaths.isPM(0))
        #expect(!ClockMaths.isPM(11))
        #expect(ClockMaths.isPM(12))
        #expect(ClockMaths.isPM(23))
    }

    /// Every time the question can generate accepts its 12-hour reading, with or without a
    /// leading zero, and rejects the 24-hour form whenever that differs.
    @Test func everyTimeOfDayAcceptsItsTwelveHourReading() {
        for hour24 in 0..<24 {
            for minute in 0..<60 {
                let hour12 = ClockMaths.twelveHour(hour24)
                #expect(ClockMaths.isCorrectReading(hours: "\(hour12)", minutes: "\(minute)", hour24: hour24, minute: minute))
                #expect(ClockMaths.isCorrectReading(hours: String(format: "%02d", hour12), minutes: String(format: "%02d", minute), hour24: hour24, minute: minute))

                if hour24 != hour12 {
                    #expect(!ClockMaths.isCorrectReading(hours: "\(hour24)", minutes: "\(minute)", hour24: hour24, minute: minute))
                }
                let wrongHour = hour12 % 12 + 1
                #expect(!ClockMaths.isCorrectReading(hours: "\(wrongHour)", minutes: "\(minute)", hour24: hour24, minute: minute))
                let wrongMinute = (minute + 1) % 60
                #expect(!ClockMaths.isCorrectReading(hours: "\(hour12)", minutes: "\(wrongMinute)", hour24: hour24, minute: minute))
            }
        }
    }

    @Test func midnightAndNoonAreTwelve() {
        // 00:05 is shown as 12:05 AM; 12:30 is shown as 12:30 PM.
        #expect(ClockMaths.isCorrectReading(hours: "12", minutes: "05", hour24: 0, minute: 5))
        #expect(!ClockMaths.isCorrectReading(hours: "0", minutes: "05", hour24: 0, minute: 5))
        #expect(!ClockMaths.isCorrectReading(hours: "00", minutes: "05", hour24: 0, minute: 5))
        #expect(ClockMaths.isCorrectReading(hours: "12", minutes: "30", hour24: 12, minute: 30))
        #expect(!ClockMaths.isCorrectReading(hours: "0", minutes: "30", hour24: 12, minute: 30))
        #expect(ClockMaths.isCorrectReading(hours: "12", minutes: "0", hour24: 12, minute: 0))
        #expect(ClockMaths.isCorrectReading(hours: "11", minutes: "59", hour24: 23, minute: 59))
        #expect(!ClockMaths.isCorrectReading(hours: "23", minutes: "59", hour24: 23, minute: 59))
        #expect(ClockMaths.isCorrectReading(hours: "1", minutes: "00", hour24: 13, minute: 0))
        #expect(!ClockMaths.isCorrectReading(hours: "13", minutes: "00", hour24: 13, minute: 0))
    }

    @Test func malformedReadingsAreRejected() {
        let rejected: [(String, String)] = [
            ("", ""), ("", "15"), ("3", ""), ("abc", "15"), ("3", "x"),
            ("-3", "15"), ("15", "15"), ("3", "60"), ("3", "-15"), ("3.0", "15"), ("3", "15.0")
        ]
        for (hours, minutes) in rejected {
            #expect(!ClockMaths.isCorrectReading(hours: hours, minutes: minutes, hour24: 15, minute: 15), "\(hours):\(minutes)")
        }
        #expect(ClockMaths.isCorrectReading(hours: " 3 ", minutes: " 15 ", hour24: 15, minute: 15))
    }

    /// Validation is a pure function, so marking an answer can no longer change the question.
    @Test func markingIsRepeatable() {
        for _ in 0..<3 {
            #expect(ClockMaths.isCorrectReading(hours: "10", minutes: "52", hour24: 22, minute: 52))
            #expect(!ClockMaths.isCorrectReading(hours: "22", minutes: "52", hour24: 22, minute: 52))
        }
    }
}

// MARK: - Year 3 Time: setting a clock (MQ-07, MQ-08)

struct ClockSettingTests {
    @Test func settingAnyTimeMatchesModuloTwelveHours() {
        for hour24 in 0..<24 {
            for minute in 0..<60 {
                let clockHour = hour24 % 12
                #expect(ClockMaths.isCorrectlySet(clockHour: clockHour, clockMinute: minute, hour24: hour24, minute: minute))
                #expect(!ClockMaths.isCorrectlySet(clockHour: (clockHour + 1) % 12, clockMinute: minute, hour24: hour24, minute: minute))
                #expect(!ClockMaths.isCorrectlySet(clockHour: clockHour, clockMinute: (minute + 1) % 60, hour24: hour24, minute: minute))
            }
        }
        // The interactive clock shows 12 o'clock as hour 0.
        #expect(ClockMaths.isCorrectlySet(clockHour: 0, clockMinute: 0, hour24: 0, minute: 0))
        #expect(ClockMaths.isCorrectlySet(clockHour: 0, clockMinute: 0, hour24: 12, minute: 0))
        #expect(ClockMaths.isCorrectlySet(clockHour: 10, clockMinute: 52, hour24: 22, minute: 52))
    }

    @Test func handAngles() {
        #expect(ClockMaths.minuteHandDegrees(minute: 0) == 0)
        #expect(ClockMaths.minuteHandDegrees(minute: 15) == 90)
        #expect(ClockMaths.minuteHandDegrees(minute: 45) == 270)
        #expect(ClockMaths.hourHandDegrees(hour: 0, minute: 0) == 0)
        #expect(ClockMaths.hourHandDegrees(hour: 3, minute: 0) == 90)
        #expect(ClockMaths.hourHandDegrees(hour: 3, minute: 30) == 105)
        #expect(ClockMaths.hourHandDegrees(hour: 12, minute: 0) == 0)
        #expect(ClockMaths.hourHandDegrees(hour: 15, minute: 0) == 90)
        #expect(ClockMaths.hourHandDegrees(hour: 23, minute: 59) == 359.5)
    }

    private let center = CGPoint(x: 150, y: 150)

    /// A point on the face at the given angle clockwise from 12, in screen coordinates (y down).
    private func point(atDegrees degrees: Double, radius: Double = 100) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: center.x + radius * sin(radians), y: center.y - radius * cos(radians))
    }

    @Test func touchQuadrantsMapToTheRightMinutes() {
        #expect(ClockMaths.minute(at: CGPoint(x: 150, y: 50), center: center) == 0)
        #expect(ClockMaths.minute(at: CGPoint(x: 250, y: 150), center: center) == 15)
        #expect(ClockMaths.minute(at: CGPoint(x: 150, y: 250), center: center) == 30)
        #expect(ClockMaths.minute(at: CGPoint(x: 50, y: 150), center: center) == 45)
    }

    /// Touching where the minute hand is drawn for minute m selects minute m, so dragging and
    /// drawing share one coordinate system.
    @Test func touchAndDrawingAgreeForEveryMinute() {
        for minute in 0..<60 {
            let degrees = ClockMaths.minuteHandDegrees(minute: Double(minute))
            for nudge in [-2.9, 0, 2.9] {
                for radius in [40.0, 100, 140] {
                    #expect(ClockMaths.minute(at: point(atDegrees: degrees + nudge, radius: radius), center: center) == minute)
                }
            }
        }
    }

    @Test func touchJustBeforeTwelveWrapsToZero() {
        #expect(ClockMaths.minute(at: point(atDegrees: 359), center: center) == 0)
        #expect(ClockMaths.minute(at: point(atDegrees: 357.5), center: center) == 0)
        #expect(ClockMaths.minute(at: point(atDegrees: 356), center: center) == 59)
        #expect(ClockMaths.minute(at: point(atDegrees: 1), center: center) == 0)
    }

    @Test func touchesNearTheCentreAreIgnored() {
        #expect(ClockMaths.minute(at: center, center: center) == nil)
        #expect(ClockMaths.minute(at: point(atDegrees: 90, radius: 10), center: center, deadZone: 22.5) == nil)
        #expect(ClockMaths.minute(at: point(atDegrees: 90, radius: 30), center: center, deadZone: 22.5) == 15)
    }

    @Test func movingTheMinuteHandCarriesTheHour() {
        #expect(ClockMaths.movingMinuteHand(hour: 3, minute: 0, to: 15) == (3, 15))
        // Forwards and backwards past 12.
        #expect(ClockMaths.movingMinuteHand(hour: 3, minute: 55, to: 5) == (4, 5))
        #expect(ClockMaths.movingMinuteHand(hour: 4, minute: 5, to: 55) == (3, 55))
        // Past 12 o'clock on the hour hand as well.
        #expect(ClockMaths.movingMinuteHand(hour: 11, minute: 58, to: 2) == (0, 2))
        #expect(ClockMaths.movingMinuteHand(hour: 0, minute: 2, to: 58) == (11, 58))
        #expect(ClockMaths.movingMinuteHand(hour: 0, minute: 0, to: 59) == (11, 59))
        // Staying put changes nothing.
        #expect(ClockMaths.movingMinuteHand(hour: 7, minute: 20, to: 20) == (7, 20))
    }

    /// Feeds a continuous drag of the given number of turns (negative is anticlockwise) through
    /// the same functions the view uses.
    private func drag(from start: (hour: Int, minute: Int), turns: Double, stepDegrees: Double = 3) -> (hour: Int, minute: Int) {
        var clock = start
        let startDegrees = ClockMaths.minuteHandDegrees(minute: Double(start.minute))
        let steps = Int((abs(turns) * 360 / stepDegrees).rounded())
        for step in 1...steps {
            let degrees = startDegrees + Double(step) * stepDegrees * (turns < 0 ? -1 : 1)
            guard let target = ClockMaths.minute(at: point(atDegrees: degrees), center: center) else { continue }
            clock = ClockMaths.movingMinuteHand(hour: clock.hour, minute: clock.minute, to: target)
            #expect((0..<12).contains(clock.hour))
            #expect((0..<60).contains(clock.minute))
        }
        return clock
    }

    @Test func dragRevolutionsAdvanceTheHourByOne() {
        #expect(drag(from: (3, 0), turns: 1) == (4, 0))
        #expect(drag(from: (3, 0), turns: 2) == (5, 0))
        #expect(drag(from: (3, 0), turns: -1) == (2, 0))
        #expect(drag(from: (11, 30), turns: 1) == (0, 30))
        #expect(drag(from: (0, 30), turns: -1) == (11, 30))
        #expect(drag(from: (3, 0), turns: 12) == (3, 0))
        #expect(drag(from: (3, 0), turns: 0.25) == (3, 15))
        #expect(drag(from: (3, 0), turns: 1.25) == (4, 15))
    }

    /// After any sequence of moves the hour hand sits exactly where the minute hand says it should.
    @Test func handsStayInSyncOverRandomDrags() {
        var generator = SeededGenerator(seed: 0x3A_0708)
        var clock = (hour: 0, minute: 0)
        var totalMinutes = 0
        for _ in 0..<20_000 {
            let target = Int.random(in: 0..<60, using: &generator)
            var delta = (target - clock.minute) % 60
            if delta > 30 { delta -= 60 } else if delta <= -30 { delta += 60 }
            totalMinutes += delta

            clock = ClockMaths.movingMinuteHand(hour: clock.hour, minute: clock.minute, to: target)
            #expect(clock.minute == target)
            #expect(clock.hour * 60 + clock.minute == ((totalMinutes % 720) + 720) % 720)

            let hourDegrees = ClockMaths.hourHandDegrees(hour: Double(clock.hour), minute: Double(clock.minute))
            let minuteDegrees = ClockMaths.minuteHandDegrees(minute: Double(clock.minute))
            #expect(abs(hourDegrees.truncatingRemainder(dividingBy: 30) * 12 - minuteDegrees) < 1e-9)
        }
    }
}

// MARK: - Year 4 Geometry questions (MQ-12, MQ-15)

struct Year4GeometryQuestionTests {
    private func satisfiesPolygonInequality(_ sides: [Int]) -> Bool {
        let total = sides.reduce(0, +)
        return sides.allSatisfy { $0 < total - $0 }
    }

    @Test func constructibilityMatchesTheTriangleInequalityExhaustively() {
        for a in 1...13 {
            for b in 1...13 {
                for c in 1...13 {
                    let expected = a + b > c && a + c > b && b + c > a
                    #expect(Year4GeometryQuestion.isConstructible([a, b, c]) == expected, "\(a), \(b), \(c)")
                }
            }
        }
    }

    @Test func impossibleAndDegenerateShapesAreRejected() {
        #expect(!Year4GeometryQuestion.isConstructible([2, 3, 12]))
        #expect(!Year4GeometryQuestion.isConstructible([2, 3, 5]))  // flat: 2 + 3 == 5
        #expect(!Year4GeometryQuestion.isConstructible([2, 2, 2, 2, 8]))
        #expect(!Year4GeometryQuestion.isConstructible([12, 2, 2, 2, 2]))
        #expect(!Year4GeometryQuestion.isConstructible([3, 4]))
        #expect(!Year4GeometryQuestion.isConstructible([]))
        #expect(!Year4GeometryQuestion.isConstructible([0, 3, 3]))
        #expect(Year4GeometryQuestion.isConstructible([2, 3, 4]))
        #expect(Year4GeometryQuestion.isConstructible([2, 2, 2, 2, 7]))
        #expect(Year4GeometryQuestion.isConstructible([6, 9, 7, 11, 5]))
    }

    /// Generates a large deterministic sample and checks every question is well formed and answerable.
    @Test func generatedQuestionsAreAlwaysValid() throws {
        var generator = SeededGenerator(seed: 0x3A_0012)
        var seenQuestions = Set<Int>()
        var seenShapes = Set<Int>()
        var seenAngleTypes = Set<String>()
        var seenUnits = Set<String>()
        var areaQuestions = 0

        for _ in 0..<100_000 {
            let q = Year4GeometryQuestion.random(using: &generator)
            seenQuestions.insert(q.question)
            seenShapes.insert(q.shapeType)
            seenUnits.insert(q.unitType)

            #expect((1...3).contains(q.question))
            #expect((3...5).contains(q.shapeType))
            #expect(q.sides.count == q.shapeType)
            #expect(q.sides.allSatisfy { Year4GeometryQuestion.sideLengths.contains($0) })
            #expect(satisfiesPolygonInequality(q.sides), "\(q.sides)")
            #expect(Year4GeometryQuestion.angles.contains(q.angleMeasure))
            #expect(Year4GeometryQuestion.units.contains(q.unitType))
            if q.shapeType == 4 {
                #expect(q.sides[0] == q.sides[2] && q.sides[1] == q.sides[3])
            }

            switch q.question {
            case 1:
                #expect(q.perimeter == q.sides.reduce(0, +))
                #expect(q.evaluate(answer: "\(q.perimeter)", unit: q.unitType) == .correct)
            case 2:
                areaQuestions += 1
                #expect(q.shapeType == 4)
                let area = try #require(q.area)
                #expect(area == q.sides[0] * q.sides[1])
                #expect(q.evaluate(answer: "\(area)", unit: q.unitType + "²") == .correct)
            default:
                seenAngleTypes.insert(q.angleType)
                #expect(q.evaluate(answer: q.angleType, unit: "") == .correct)
            }
        }

        #expect(seenQuestions == [1, 2, 3])
        #expect(seenShapes == [3, 4, 5])
        #expect(seenAngleTypes == ["acute", "right", "obtuse"])
        #expect(seenUnits == Set(Year4GeometryQuestion.units))
        #expect(areaQuestions > 0)
    }

    @Test func perimeterMarking() {
        let q = Year4GeometryQuestion(question: 1, shapeType: 3, sides: [3, 4, 5], angleMeasure: 45, unitType: "cm")
        #expect(q.correctUnit == "cm")
        #expect(q.evaluate(answer: "12", unit: "cm") == .correct)
        #expect(q.evaluate(answer: " 12 ", unit: "cm") == .correct)
        #expect(q.evaluate(answer: "012", unit: "cm") == .correct)
        #expect(q.evaluate(answer: "12", unit: "mm") == .wrongUnit)
        #expect(q.evaluate(answer: "12", unit: "cm²") == .wrongUnit)
        // No unit chosen yet: the wheel's placeholder row is tagged "".
        #expect(q.evaluate(answer: "12", unit: "") == .wrongUnit)
        #expect(q.evaluate(answer: "13", unit: "cm") == .incorrect)
        // Since Stage 6E nothing typed is asked for again rather than marked wrong.
        #expect(q.evaluate(answer: "", unit: "cm") == .unanswered)
        #expect(q.evaluate(answer: " \n", unit: "cm") == .unanswered)
        #expect(q.evaluate(answer: "abc", unit: "cm") == .incorrect)
        #expect(q.evaluate(answer: "12 cm", unit: "cm") == .incorrect)
    }

    @Test func pentagonPerimeterUsesAllFiveSides() {
        let q = Year4GeometryQuestion(question: 1, shapeType: 5, sides: [6, 9, 7, 11, 5], angleMeasure: 45, unitType: "mm")
        #expect(q.evaluate(answer: "38", unit: "mm") == .correct)
    }

    @Test func areaMarking() {
        let q = Year4GeometryQuestion(question: 2, shapeType: 4, sides: [5, 3, 5, 3], angleMeasure: 45, unitType: "m")
        #expect(q.correctUnit == "m²")
        #expect(q.area == 15)
        #expect(q.perimeter == 16)
        #expect(q.evaluate(answer: "15", unit: "m²") == .correct)
        #expect(q.evaluate(answer: "15", unit: "m") == .wrongUnit)
        #expect(q.evaluate(answer: "15", unit: "") == .wrongUnit)
        #expect(q.evaluate(answer: "16", unit: "m²") == .incorrect)
        #expect(q.evaluate(answer: "", unit: "m²") == .unanswered)
    }

    @Test func areaIsOnlyDefinedForRectangles() {
        let triangle = Year4GeometryQuestion(question: 2, shapeType: 3, sides: [3, 4, 5], angleMeasure: 45, unitType: "m")
        #expect(triangle.area == nil)
        #expect(triangle.evaluate(answer: "0", unit: "m²") == .incorrect)
        #expect(triangle.evaluate(answer: "", unit: "m²") == .unanswered)
    }

    @Test func angleMarking() {
        func angle(_ degrees: Int) -> Year4GeometryQuestion {
            Year4GeometryQuestion(question: 3, shapeType: 3, sides: [3, 4, 5], angleMeasure: degrees, unitType: "cm")
        }
        #expect(angle(1).angleType == "acute")
        #expect(angle(89).angleType == "acute")
        #expect(angle(90).angleType == "right")
        #expect(angle(91).angleType == "obtuse")
        #expect(angle(179).angleType == "obtuse")

        #expect(angle(45).correctUnit == nil)
        #expect(angle(45).evaluate(answer: "acute", unit: "") == .correct)
        #expect(angle(45).evaluate(answer: " Acute ", unit: "") == .correct)
        #expect(angle(45).evaluate(answer: "ACUTE", unit: "km") == .correct)
        #expect(angle(90).evaluate(answer: "Right", unit: "") == .correct)
        #expect(angle(120).evaluate(answer: "obtuse", unit: "") == .correct)
        #expect(angle(45).evaluate(answer: "obtuse", unit: "") == .incorrect)
        #expect(angle(90).evaluate(answer: "acute", unit: "") == .incorrect)
        #expect(angle(120).evaluate(answer: "right", unit: "") == .incorrect)
    }

    /// Non-numeric input used to compare nil == nil against the angle answer and be marked correct.
    @Test func blankOrNonsenseAngleAnswersAreNeverCorrect() {
        for degrees in [30, 90, 150] {
            let q = Year4GeometryQuestion(question: 3, shapeType: 3, sides: [3, 4, 5], angleMeasure: degrees, unitType: "cm")
            // Since Stage 6E nothing typed is asked for again rather than marked wrong.
            for answer in ["", "   "] {
                #expect(q.evaluate(answer: answer, unit: "") == .unanswered, "\(degrees)°: \"\(answer)\"")
            }
            for answer in ["hello", "?", "45", "\(degrees)", "acutee"] {
                #expect(q.evaluate(answer: answer, unit: "") == .incorrect, "\(degrees)°: \"\(answer)\"")
            }
        }
    }
}

// MARK: - Year 4 Geometry drawings (MQ-12)

struct ShapeGeometryTests {
    private let frame = CGRect(x: 26, y: 26, width: 108, height: 108)

    private func edgeLengths(_ points: [CGPoint]) -> [Double] {
        points.indices.map { i in
            let a = points[i], b = points[(i + 1) % points.count]
            return Double(hypot(b.x - a.x, b.y - a.y))
        }
    }

    private func turns(_ points: [CGPoint]) -> [Double] {
        points.indices.map { i in
            let a = points[i], b = points[(i + 1) % points.count], c = points[(i + 2) % points.count]
            return Double((b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x))
        }
    }

    /// Checks a drawn polygon against its side lengths and the layout rules.
    private func checkDrawing(_ sides: [Int], sourceLocation: SourceLocation = #_sourceLocation) {
        guard let points = ShapeGeometry.polygon(sides: sides.map(Double.init), fittingIn: frame) else {
            Issue.record("No drawing for \(sides)", sourceLocation: sourceLocation)
            return
        }
        #expect(points.count == sides.count, sourceLocation: sourceLocation)

        // To scale: every edge is the same multiple of its labelled length.
        let lengths = edgeLengths(points)
        let scale = lengths[0] / Double(sides[0])
        for (length, side) in zip(lengths, sides) {
            #expect(abs(length / Double(side) - scale) < 1e-6 * scale, "\(sides)", sourceLocation: sourceLocation)
        }

        // Convex, so the labels and the outline make sense.
        let turnSigns = turns(points)
        #expect(turnSigns.allSatisfy { $0 > 1e-6 } || turnSigns.allSatisfy { $0 < -1e-6 }, "\(sides)", sourceLocation: sourceLocation)

        // The longest side is a horizontal base at the bottom.
        let base = sides.firstIndex(of: sides.max()!)!
        let start = points[base], end = points[(base + 1) % points.count]
        let lowest = points.map(\.y).max()!
        #expect(abs(start.y - end.y) < 1e-6, "\(sides)", sourceLocation: sourceLocation)
        #expect(abs(start.y - lowest) < 1e-6, "\(sides)", sourceLocation: sourceLocation)

        // Fits inside the frame and fills it in at least one direction.
        let xs = points.map(\.x), ys = points.map(\.y)
        #expect(xs.min()! >= frame.minX - 1e-6 && xs.max()! <= frame.maxX + 1e-6, sourceLocation: sourceLocation)
        #expect(ys.min()! >= frame.minY - 1e-6 && ys.max()! <= frame.maxY + 1e-6, sourceLocation: sourceLocation)
        let fillsWidth = abs((xs.max()! - xs.min()!) - frame.width) < 1e-6
        let fillsHeight = abs((ys.max()! - ys.min()!) - frame.height) < 1e-6
        #expect(fillsWidth || fillsHeight, sourceLocation: sourceLocation)

        // Each label sits 20pt out from its own side, on the outside.
        let labels = ShapeGeometry.labelPositions(for: points, offset: 20)
        let centre = CGPoint(x: xs.reduce(0, +) / CGFloat(xs.count), y: ys.reduce(0, +) / CGFloat(ys.count))
        for i in points.indices {
            let a = points[i], b = points[(i + 1) % points.count]
            let midpoint = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            #expect(abs(hypot(labels[i].x - midpoint.x, labels[i].y - midpoint.y) - 20) < 1e-6, sourceLocation: sourceLocation)
            let labelSide = (b.x - a.x) * (labels[i].y - a.y) - (b.y - a.y) * (labels[i].x - a.x)
            let centreSide = (b.x - a.x) * (centre.y - a.y) - (b.y - a.y) * (centre.x - a.x)
            #expect(labelSide * centreSide < 0, "label \(i) of \(sides)", sourceLocation: sourceLocation)
        }
    }

    @Test func everyPossibleTriangleIsDrawnToScale() {
        for a in Year4GeometryQuestion.sideLengths {
            for b in Year4GeometryQuestion.sideLengths {
                for c in Year4GeometryQuestion.sideLengths where Year4GeometryQuestion.isConstructible([a, b, c]) {
                    checkDrawing([a, b, c])
                }
            }
        }
    }

    @Test func everyPossibleRectangleIsDrawnToScaleWithRightAngles() {
        for width in Year4GeometryQuestion.sideLengths {
            for height in Year4GeometryQuestion.sideLengths {
                let sides = [width, height, width, height]
                checkDrawing(sides)
                let points = ShapeGeometry.polygon(sides: sides.map(Double.init), fittingIn: frame)!
                for i in points.indices {
                    let a = points[i], b = points[(i + 1) % 4], c = points[(i + 2) % 4]
                    let dot = (b.x - a.x) * (c.x - b.x) + (b.y - a.y) * (c.y - b.y)
                    #expect(abs(dot) < 1e-6, "\(width) x \(height)")
                }
            }
        }
    }

    @Test func sampledPentagonsAreDrawnToScale() {
        var generator = SeededGenerator(seed: 0x3A_0005)
        for _ in 0..<5_000 {
            checkDrawing(Year4GeometryQuestion.randomSides(shapeType: 5, using: &generator))
        }
        // Lopsided pentagons where the circle's centre falls outside the shape.
        for sides in [[12, 4, 3, 3, 3], [12, 12, 2, 2, 2], [2, 2, 2, 2, 7], [6, 9, 7, 11, 5]] {
            checkDrawing(sides)
        }
    }

    @Test func thinAndRightTrianglesAreDrawnToScale() {
        for sides in [[2, 11, 12], [12, 12, 2], [2, 2, 3], [12, 12, 12], [3, 4, 5], [6, 8, 10]] {
            checkDrawing(sides)
        }
        // 3-4-5 has its right angle between the 3 and 4 sides.
        let points = ShapeGeometry.polygon(sides: [3, 4, 5], fittingIn: frame)!
        let a = points[0], b = points[1], c = points[2]
        let dot = (b.x - a.x) * (c.x - b.x) + (b.y - a.y) * (c.y - b.y)
        #expect(abs(dot) < 1e-6)
    }

    @Test func cyclicPolygonHasTheExactSideLengths() throws {
        for sides in [[3.0, 4, 5], [2, 11, 12], [5, 3, 5, 3], [6, 9, 7, 11, 5], [12, 4, 3, 3, 3]] {
            let points = try #require(ShapeGeometry.cyclicPolygon(sides: sides))
            for (length, side) in zip(edgeLengths(points), sides) {
                #expect(abs(length - side) < 1e-9 * side, "\(sides)")
            }
            let radius = hypot(points[0].x, points[0].y)
            #expect(points.allSatisfy { abs(hypot($0.x, $0.y) - radius) < 1e-9 * radius })
        }
    }

    @Test func impossibleShapesHaveNoDrawing() {
        #expect(ShapeGeometry.cyclicPolygon(sides: [2, 3, 12]) == nil)
        #expect(ShapeGeometry.cyclicPolygon(sides: [2, 3, 5]) == nil)
        #expect(ShapeGeometry.cyclicPolygon(sides: [3, 4]) == nil)
        #expect(ShapeGeometry.polygon(sides: [2, 2, 2, 2, 8], fittingIn: frame) == nil)
        #expect(ShapeGeometry.labelPositions(for: [], offset: 20).isEmpty)
    }
}
