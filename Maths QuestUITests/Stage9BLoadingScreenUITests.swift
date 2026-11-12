//
//  Stage9BLoadingScreenUITests.swift
//  Maths QuestUITests
//

import UIKit
import XCTest

/// Stage 9B, D7: the first of the two loading screens was always the starting blue, whatever colour the child had
/// chosen, so the app opened in blue and then jumped to their colour. With Everglow (gold) chosen, every screenshot
/// from launch to the main menu must be gold, and there must be screenshots of both loading screens. XCUITest can't see
/// colours, so this reads the screenshots' pixels.
///
/// iOS shows its own blank screen before the app's code runs; `launch()` returns after that, so it isn't checked here.
final class Stage9BLoadingScreenUITests: MathsQuestUITestCase {
    /// A save with Everglow at full strength bought and chosen, in exactly the form the app writes it, so the app reads
    /// it without writing anything back. A launch argument comes before the app's own save in UserDefaults, so the
    /// simulator's save isn't touched.
    private static var goldSave: [String] {
        let save: [String: Any] = [
            "points": 0, "totalQuestionsAnswered": 0, "sfxvolume": 0.0, "username": "",
            "backgroundColourHex": "#FFD700", "backgroundOpacity": 1.0,
            "unlockedColours": ["#0000FF": [0.8], "#FFD700": [1.0]], "adsRemoved": false,
        ]
        let data = try! JSONSerialization.data(withJSONObject: save)
        return ["-GameSettings", "<" + data.map { String(format: "%02x", $0) }.joined() + ">"]
    }

    /// Everglow at full strength covers whatever is behind it, so it's the same in light and dark mode.
    private static let gold = (red: 255, green: 215, blue: 0)

    private struct Moment {
        let after: TimeInterval
        let colour: (red: Int, green: Int, blue: Int)
        let menuShowing: Bool
        let title: CGRect?
        /// How many elements are above the title, from the app down. The app's own loading screen isn't inside
        /// ContentView's NavigationStack, so its title has fewer above it than the title on ContentView's.
        let titleDepth: Int
        let screenshot: XCUIScreenshot

        var line: String {
            String(format: "%5.2fs  rgb(%3d,%3d,%3d)  menu=%@  title=%@", after,
                   colour.red, colour.green, colour.blue, menuShowing ? "yes" : "no",
                   title.map { String(format: "(%.0f,%.0f %.0fx%.0f)", $0.minX, $0.minY, $0.width, $0.height) } ?? "-")
                + "  titleDepth=\(titleDepth)"
        }
    }

    @MainActor
    func testEveryScreenshotFromLaunchToTheMenuIsTheChosenColour() throws {
        let app = XCUIApplication()
        app.launchArguments = [Self.launchArgument, "-AppleLanguages", "(en)", "-AppleLocale", "en_GB"] + Self.goldSave
        app.launch()
        self.app = app
        let launched = Date()

        var moments: [Moment] = []
        while Date().timeIntervalSince(launched) < 30 {
            let current = try moment(since: launched)
            moments.append(current)
            if current.menuShowing { break }
        }
        // Once the menu has settled.
        pause(0.5)
        moments.append(try moment(since: launched))
        let timeline = moments.map(\.line).joined(separator: "\n")
        print("D7|\n" + timeline)
        attachText("Screenshots from launch to the main menu", timeline)

        // The first screenshot must be of the app's own loading screen and the last loading one of ContentView's, so
        // the test can't pass by starting after the screen that used to be blue.
        XCTAssertFalse(moments[0].menuShowing, "The menu was already showing, so the loading screens weren't seen.\n\(timeline)")
        let loading = moments.filter { !$0.menuShowing }
        let first = try XCTUnwrap(loading.first)
        let last = try XCTUnwrap(loading.last)
        XCTAssertLessThan(first.titleDepth, last.titleDepth,
                          "There aren't screenshots of both loading screens, the app's and then ContentView's.\n\(timeline)")
        // The two look the same, so they read as one loading screen, with nothing jumping as the second takes over.
        XCTAssertEqual(first.title, last.title, "The words moved between the two loading screens.\n\(timeline)")
        let menu = try XCTUnwrap(moments.last)
        XCTAssertTrue(menu.menuShowing, "The main menu didn't appear.\n\(timeline)")
        for moment in moments {
            XCTAssertTrue(Self.isGold(moment.colour), "Not the chosen gold at \(moment.line)\n\(timeline)")
        }

        let contentViews = try XCTUnwrap(loading.first { $0.titleDepth == last.titleDepth })
        for (name, moment) in [("1 The app's loading screen", first), ("2 ContentView's loading screen", contentViews),
                               ("3 The main menu", menu)] {
            let attachment = XCTAttachment(screenshot: moment.screenshot)
            attachment.name = String(format: "%@ at %.2fs", name, moment.after)
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private static func isGold(_ colour: (red: Int, green: Int, blue: Int)) -> Bool {
        abs(colour.red - gold.red) <= 8 && abs(colour.green - gold.green) <= 8 && abs(colour.blue - gold.blue) <= 8
    }

    /// A screenshot's background colour, and what was on the screen, read from one snapshot.
    @MainActor
    private func moment(since launched: Date) throws -> Moment {
        let screenshot = XCUIScreen.main.screenshot()
        let after = Date().timeIntervalSince(launched)
        let colour = try backgroundColour(in: screenshot)
        var menuShowing = false
        var title: CGRect?
        var titleDepth = 0
        func visit(_ element: XCUIElementSnapshot, depth: Int) {
            switch element.elementType {
            case .button where element.label == "Year 1": menuShowing = true
            case .staticText where element.label == "Maths Quest" && title == nil:
                title = element.frame
                titleDepth = depth
            default: break
            }
            element.children.forEach { visit($0, depth: depth + 1) }
        }
        visit(try app.snapshot(), depth: 0)
        return Moment(after: after, colour: colour, menuShowing: menuShowing, title: title, titleDepth: titleDepth,
                      screenshot: screenshot)
    }

    /// The average colour of a few pixels at the left edge, halfway down: background on both loading screens and on
    /// the main menu, whose cards have a margin.
    private func backgroundColour(in screenshot: XCUIScreenshot) throws -> (red: Int, green: Int, blue: Int) {
        let image = screenshot.image
        let pixels = try XCTUnwrap(image.cgImage)
        let pixelsPerPoint = CGFloat(pixels.width) / image.size.width
        let side = 4
        let patch = try XCTUnwrap(pixels.cropping(to: CGRect(x: Int(4 * pixelsPerPoint), y: pixels.height / 2,
                                                             width: side, height: side)))
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let sRGB = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: sRGB,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(patch, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        XCTAssertTrue(drawn, "Couldn't read the screenshot's pixels.")
        func average(_ channel: Int) -> Int {
            stride(from: channel, to: bytes.count, by: 4).map { Int(bytes[$0]) }.reduce(0, +) / (side * side)
        }
        return (average(0), average(1), average(2))
    }
}
