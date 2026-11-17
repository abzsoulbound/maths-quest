//
//  Stage9BDesignTests.swift
//  Maths QuestTests
//
//  Stage 9B: the screens share one header, with the points on a chip at the top right, plain bold titles, cards that
//  are white or dark grey whatever the background colour, and messages that stay where the child is looking until
//  they do something else. These tests check what VoiceOver reads on the new screens and in what order, that every
//  colour the new pieces use can be read in light and dark mode, the words of the new messages, and that the defects
//  fixed in this stage (messages drawn over the shop's colours, messages that vanished on a timer, the private
//  Settings link) can't come back unnoticed.
//

import SwiftUI
import Testing
@testable import Maths_Quest

// MARK: - Helpers

/// SwiftUI only builds its accessibility elements when something such as VoiceOver or UI testing is using them. This
/// turns that on for the test, as accessibility snapshot tools do. (The same as Stage 5C's.)
private func enableAccessibility() {
    guard let library = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
          let symbol = dlsym(library, "_AXSSetAutomationEnabled") else { return }
    typealias SetEnabled = @convention(c) (Int32) -> Void
    unsafeBitCast(symbol, to: SetEnabled.self)(1)
}

/// A game with its own throwaway save, so the tests never touch the real one.
@MainActor
private func throwawayGame(points: Int = 7) -> (GameData, () -> Void) {
    let suite = "Stage9B-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let gameData = GameData(defaults: defaults)
    gameData.points = points
    return (gameData, { defaults.removePersistentDomain(forName: suite) })
}

/// What VoiceOver reads, in the order it reads it, and where each item is on the screen: the view is put in a window
/// the size of the screen the tests run on and its accessibility elements are walked the way VoiceOver walks them.
///
/// The window used to be 390 by 844 points, an iPhone's, on every device. The header's buttons are sized from the
/// screen, so on an iPad they were too wide for that window and the points went on a line of their own under them, and
/// were read after Settings, which doesn't happen on the iPad's own screen.
@MainActor
private func spokenItems<Content: View>(of view: Content, gameData: GameData,
                                        size: CGSize? = nil) -> [(label: String, frame: CGRect)] {
    enableAccessibility()
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first!
    let window = UIWindow(windowScene: scene)
    window.frame = CGRect(origin: .zero, size: size ?? UIScreen.main.bounds.size)
    let host = UIHostingController(rootView: view.environmentObject(AppNavigator()).environmentObject(gameData))
    window.rootViewController = host
    window.isHidden = false
    host.view.setNeedsLayout()
    host.view.layoutIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    defer { window.isHidden = true }

    var items: [(label: String, frame: CGRect)] = []
    func visit(_ object: NSObject) {
        if object.accessibilityElementsHidden { return }
        if let view = object as? UIView, view.isHidden { return }
        if object.isAccessibilityElement {
            items.append((spokenName(of: object), object.accessibilityFrame))
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
    return items
}

/// What VoiceOver says first for an item: its label, or if it has none, its value, or for an empty text box, its
/// placeholder, which VoiceOver reads in place of a name. The Shop's "Points to spend" box, like the answer boxes, has
/// no label of its own; XCUITest finds it by its placeholder too. An item with none of the three is "".
@MainActor
private func spokenName(of object: NSObject) -> String {
    let placeholder = (object as? UITextField).flatMap { $0.text?.isEmpty ?? true ? $0.placeholder : nil }
    for name in [object.accessibilityLabel, object.accessibilityValue, placeholder] {
        if let name, !name.isEmpty {
            return name
        }
    }
    return ""
}

@MainActor
private func spokenLabels<Content: View>(of view: Content, gameData: GameData) -> [String] {
    spokenItems(of: view, gameData: gameData).map(\.label)
}

/// The app's source, for the few checks that are about how a screen is built rather than what it shows.
private enum Stage9BSource {
    static let appFolder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Maths Quest")

    static func file(_ name: String) throws -> String {
        try String(contentsOf: appFolder.appendingPathComponent(name), encoding: .utf8)
    }

    /// From `struct <name>` at the start of a line to the next closing brace in the first column.
    static func view(_ name: String) throws -> String {
        try declaration(startingWith: "\nstruct \(name): View {")
    }

    /// From `opening` to the next closing brace in the first column.
    static func declaration(startingWith opening: String) throws -> String {
        let source = try file("ContentView.swift")
        let start = try #require(source.range(of: opening), "\(opening) not found")
        let end = try #require(source.range(of: "\n}\n", range: start.upperBound..<source.endIndex))
        return String(source[start.lowerBound..<end.upperBound])
    }

    static func count(_ needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }
}

/// Records the heights views are given, by name.
private final class HeightRecorder {
    var heights: [String: CGFloat] = [:]
}

// MARK: - The header

@MainActor
struct Stage9BHeaderTests {
    @Test func aMenuScreenReadsTheMenuButtonThenThePoints() {
        let (gameData, cleanUp) = throwawayGame()
        defer { cleanUp() }
        let labels = spokenLabels(of: NavigationBar(Back: false, Points: true, isSidebarOpen: .constant(false)),
                                  gameData: gameData)
        // No hidden Settings button standing in for the missing one, and no blank item for VoiceOver to stop on.
        #expect(labels == ["Menu", "Points: 7"])
    }

    @Test func aQuestionScreenReadsHomeThePointsThenSettings() {
        let (gameData, cleanUp) = throwawayGame()
        defer { cleanUp() }
        let labels = spokenLabels(of: NavigationBar(Back: true, Points: true, isSidebarOpen: .constant(false)),
                                  gameData: gameData)
        #expect(labels == ["Home", "Points: 7", "Settings"])
    }

    @Test func aScreenWithoutPointsHasNoEmptyItem() {
        let (gameData, cleanUp) = throwawayGame()
        defer { cleanUp() }
        let labels = spokenLabels(of: NavigationBar(Back: false, Points: false, isSidebarOpen: .constant(false)),
                                  gameData: gameData)
        #expect(labels == ["Menu"])
    }

    @Test func thePointsChipIsOneItem() {
        let (gameData, cleanUp) = throwawayGame()
        defer { cleanUp() }
        // The star is part of the chip, not an item of its own. The number is grouped the way the device's language
        // groups it, as the header has done since 1.3: "1,234" in English.
        #expect(spokenLabels(of: PointsChip(points: 1234), gameData: gameData) == ["Points: \(1234.formatted())"])
        #expect(spokenLabels(of: PointsChip(points: 1234, narrow: true), gameData: gameData)
                == ["Points: \(1234.formatted())"])
    }

    /// Stage 9B final corrections. At the largest text sizes the chip didn't fit beside the buttons on an iPhone SE
    /// once a child had 100 points, or on an iPhone 17 Pro once they had 1,000, so the points went on a line of their
    /// own under the buttons and the question had 53 points less room above the keyboard. The chip now leaves out its
    /// star there instead. This checks both headers (Home and Settings, on the year menus and questions; the menu
    /// button, on the main menu and the screens it opens) at the usual text size, the largest usual one and three
    /// accessibility sizes up to the largest, on the screen of each device it runs on: from 7 to 9,999 points the chip
    /// stays on the buttons' row and between them, is read in the order it's seen, and the buttons stay at least 44
    /// points square.
    @Test(arguments: [DynamicTypeSize.large, .xxxLarge, .accessibility1, .accessibility2, .accessibility5])
    func thePointsStayOnTheButtonsRow(size: DynamicTypeSize) throws {
        for back in [true, false] {
            for points in [7, 72, 100, 999, 1_000, 9_999] {
                let (gameData, cleanUp) = throwawayGame(points: points)
                defer { cleanUp() }
                let bar = NavigationBar(Back: back, Points: true, isSidebarOpen: .constant(false))
                    .environment(\.dynamicTypeSize, size)
                let items = spokenItems(of: bar, gameData: gameData)
                let label = "Points: \(points.formatted())"
                let header = "\(points) points at \(size) with \(back ? "Home" : "the menu button")"
                #expect(items.map(\.label) == (back ? ["Home", label, "Settings"] : ["Menu", label]), "\(header)")
                let chip = try #require(items.first { $0.label == label })
                let buttons = items.filter { $0.label != label }
                let leading = try #require(buttons.first)
                #expect(abs(chip.frame.midY - leading.frame.midY) < 1,
                        "\(header): the chip at \(chip.frame) isn't beside \(leading.label) at \(leading.frame)")
                let rightEdge = buttons.count > 1 ? buttons[1].frame.minX : UIScreen.main.bounds.width
                #expect(chip.frame.minX >= leading.frame.maxX && chip.frame.maxX <= rightEdge,
                        "\(header): the chip at \(chip.frame) runs into a button or off the screen")
                for button in buttons {
                    #expect(isATouchTarget(button.frame), "\(header): \(button.label) is only \(button.frame.size)")
                }
            }
        }
    }

    /// Stage 9B final corrections. From 10,000 points the chip, even without its star, can still be too wide for the
    /// buttons' row at the largest text sizes on a small iPhone, and then it goes on a line of its own under the
    /// buttons, as it did before. Wherever it goes, the whole number is shown and read, the chip stays on the screen
    /// and clear of the buttons, it's read in the order it's seen, and the buttons stay at least 44 points square.
    /// Where the chip went is printed, for the report.
    @Test(arguments: [DynamicTypeSize.large, .accessibility1, .accessibility5])
    func largerTotalsStayWholeAndClearOfTheButtons(size: DynamicTypeSize) throws {
        for back in [true, false] {
            for points in [10_000, 99_999, 100_000, 1_000_000] {
                let (gameData, cleanUp) = throwawayGame(points: points)
                defer { cleanUp() }
                let bar = NavigationBar(Back: back, Points: true, isSidebarOpen: .constant(false))
                    .environment(\.dynamicTypeSize, size)
                let items = spokenItems(of: bar, gameData: gameData)
                let label = "Points: \(points.formatted())"
                let header = "\(points) points at \(size) with \(back ? "Home" : "the menu button")"
                let chip = try #require(items.first { $0.label == label }, "\(header): \(items.map(\.label))")
                let buttons = items.filter { $0.label != label }
                let leading = try #require(buttons.first)
                let beside = abs(chip.frame.midY - leading.frame.midY) < 1
                let buttonNames = buttons.map(\.label)
                if beside {
                    var inOrder = buttonNames
                    inOrder.insert(label, at: 1)
                    #expect(items.map(\.label) == inOrder, "\(header)")
                    let rightEdge = buttons.count > 1 ? buttons[1].frame.minX : UIScreen.main.bounds.width
                    #expect(chip.frame.minX >= leading.frame.maxX && chip.frame.maxX <= rightEdge,
                            "\(header): the chip at \(chip.frame) runs into a button or off the screen")
                } else {
                    #expect(items.map(\.label) == buttonNames + [label], "\(header)")
                    #expect(chip.frame.minY >= buttons.map(\.frame.maxY).max()! - 1,
                            "\(header): the chip at \(chip.frame) isn't under the buttons")
                    #expect(chip.frame.minX >= 0 && chip.frame.maxX <= UIScreen.main.bounds.width,
                            "\(header): the chip at \(chip.frame) runs off the screen")
                }
                #expect(buttonNames == (back ? ["Home", "Settings"] : ["Menu"]), "\(header)")
                for button in buttons {
                    #expect(isATouchTarget(button.frame), "\(header): \(button.label) is only \(button.frame.size)")
                }
                print("Stage 9B header, \(Int(UIScreen.main.bounds.width))-point-wide screen: \(header): "
                      + (beside ? "beside the buttons" : "under the buttons"))
            }
        }
    }

    /// At least 44 points each way, allowing for the frame being rounded to the screen's pixels.
    private func isATouchTarget(_ frame: CGRect) -> Bool {
        frame.width >= 44 - 0.01 && frame.height >= 44 - 0.01
    }

    @Test func theShopWritesPointsAsTheHeaderDoes() {
        let (gameData, cleanUp) = throwawayGame()
        defer { cleanUp() }
        for points in [7, 1234, 98765] {
            let header = spokenLabels(of: PointsChip(points: points), gameData: gameData)
            #expect(header == ["Points: " + ShopView.pointsText(points).replacingOccurrences(of: " points", with: "")])
        }
    }
}

// MARK: - Menus

@MainActor
struct Stage9BMenuTests {
    @Test func aYearMenuReadsItsTitleAgesAndActivities() {
        let (gameData, cleanUp) = throwawayGame()
        defer { cleanUp() }
        let labels = spokenLabels(of: YearMenu(year: 3), gameData: gameData)
        #expect(labels == ["Home", "Points: 7", "Settings", "Year 3", "Ages 7 to 8. Choose an activity.",
                           "Fractions", "Measurement", "Time"])
    }

    /// The heights cards with these subtitles are given in a grid of `width`, in the same order.
    private func cardHeights(_ subtitles: [String], columns: Int, width: CGFloat, gameData: GameData) -> [CGFloat] {
        let recorder = HeightRecorder()
        let grid = EqualCardGrid(columns: columns) {
            ForEach(subtitles, id: \.self) { subtitle in
                MenuCard(title: "Title", subtitle: subtitle, icon: .symbol("plus"), titleSize: 24, minHeight: 60)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { recorder.heights[subtitle] = $0 }
            }
        }
        .frame(width: width)
        _ = spokenItems(of: grid, gameData: gameData)
        return subtitles.compactMap { recorder.heights[$0] }
    }

    @Test func cardsInAGridAreAllAsTallAsTheTallest() {
        let (gameData, cleanUp) = throwawayGame()
        defer { cleanUp() }
        let long = "A much longer line of words, which wraps onto two or three lines on a phone"
        let alone = cardHeights(["Short"], columns: 1, width: 300, gameData: gameData)
        let together = cardHeights(["Short", long, "Mid"], columns: 1, width: 300, gameData: gameData)
        #expect(alone.count == 1)
        #expect(together.count == 3)
        // Every card is as tall as the one with the most words, which is taller than a short card on its own.
        #expect(Set(together.map { ($0 * 2).rounded() }).count == 1, "\(together)")
        #expect((together.first ?? 0) > (alone.first ?? .infinity) + 10, "\(alone) \(together)")
        let pair = cardHeights(["Short", long], columns: 2, width: 350, gameData: gameData)
        #expect(pair.count == 2)
        #expect(Set(pair.map { ($0 * 2).rounded() }).count == 1, "\(pair)")
    }

    @Test func everyActivityHasItsOwnShortSummaryAndIcon() {
        #expect(Activity.allCases.count == 18)
        let summaries = Activity.allCases.map(\.summary)
        #expect(Set(summaries).count == 18)
        for summary in summaries {
            // One line on a card on the smallest iPhone, at the usual text size.
            #expect(!summary.isEmpty && summary.count <= 32, "\(summary)")
        }
        let icons = Activity.allCases.map { "\($0.icon)" }
        #expect(Set(icons).count == 18)
        for year in 1...6 {
            #expect(Activity.activities(inYear: year).count == 3)
        }
    }

    @Test func agesAreWrittenAndReadForEachYear() {
        #expect(SchoolYear.ages(1) == "Ages 5–6")
        #expect(SchoolYear.spokenAges(1) == "Ages 5 to 6")
        #expect(SchoolYear.ages(6) == "Ages 10–11")
        #expect(SchoolYear.spokenAges(6) == "Ages 10 to 11")
    }
}

// MARK: - Colours

@MainActor
struct Stage9BColourTests {
    private static let schemes: [ColorScheme] = [.light, .dark]

    /// Every background colour the shop sells, at every strength, and the one every player starts with.
    private static let backgrounds: [(hex: String, opacity: Double)] =
        colours.flatMap { colour in colour.opacities.map { (hex: colour.hexCode, opacity: $0.opacity) } }
            + [(hex: "0000FF", opacity: 0.8)]

    @Test func wordsOnACardCanBeReadInLightAndDarkMode() {
        for scheme in Self.schemes {
            let surface = CardColour.rgb(.surface, in: scheme)
            let iconBackground = CardColour.rgb(.iconBackground, in: scheme)
            #expect(Contrast.ratio(CardColour.rgb(.words, in: scheme), surface) >= 7, "\(scheme)")
            #expect(Contrast.ratio(CardColour.rgb(.quietWords, in: scheme), surface) >= 7, "\(scheme)")
            #expect(Contrast.ratio(CardColour.rgb(.quietWords, in: scheme), iconBackground) >= 4.5, "\(scheme)")
            #expect(Contrast.ratio(CardColour.rgb(.accent, in: scheme), iconBackground) >= 4.5, "\(scheme)")
            #expect(Contrast.ratio(CardColour.rgb(.accent, in: scheme), surface) >= 4.5, "\(scheme)")
        }
    }

    @Test func aCardIsWhiteInLightModeAndDarkGreyInDarkMode() {
        #expect(CardColour.rgb(.surface, in: .light) == Contrast.white)
        #expect(CardColour.rgb(.surface, in: .dark) == Contrast.RGB(bytes: 44, 44, 46))
    }

    @Test func iconsOnACardCanBeSeen() {
        for scheme in Self.schemes {
            let surface = CardColour.rgb(.surface, in: scheme)
            #expect(Contrast.ratio(CardColour.readable(PointsChip.starColour, minimum: 3, in: scheme), surface) >= 3)
            for tone in [StatusBanner.Tone.success, .problem, .information] {
                #expect(Contrast.ratio(CardColour.readable(tone.colour, minimum: 3, in: scheme), surface) >= 3,
                        "\(tone) \(scheme)")
            }
        }
    }

    @Test func eachKindOfMessageHasItsOwnSymbol() {
        // So the colour is never the only sign of whether it went well.
        let symbols = [StatusBanner.Tone.success, .problem, .information].map(\.symbol)
        #expect(Set(symbols).count == 3)
    }

    @Test func whiteWordsCanBeReadOnEveryFilledButton() {
        for colour in [Contrast.systemBlue.light, Contrast.systemGreen.light, Contrast.systemGrey] {
            #expect(Contrast.ratio(Contrast.white, Contrast.boxForWhiteWords(colour)) >= 4.5)
        }
    }

    @Test func aTextBoxsHintAndEdgeCanBeSeenOnItsWhite() {
        #expect(Contrast.ratio(Contrast.readableGrey(on: Contrast.white), Contrast.white) >= 4.5)
        // The box's edge is drawn in light mode whatever the system's mode, as the box is always white.
        #expect(Contrast.ratio(CardColour.rgb(.quietWords, in: .light), Contrast.white) >= 3)
    }

    @Test func shopSwatchesCanBeReadOnTheSystemsWhiteAndBlack() {
        for scheme in Self.schemes {
            let behind = scheme == .dark ? Contrast.black : Contrast.white
            for colour in colours {
                for option in colour.opacities {
                    let swatch = ShopView.swatchColour(colour, option, on: behind)
                    let name = "\(colour.name) \(option.opacity) \(scheme)"
                    #expect(Contrast.ratio(ShopView.priceColour(on: swatch), swatch) >= 4.5, "\(name)")
                    #expect(Contrast.ratio(Contrast.blackOrWhite(on: swatch, minimum: 3), swatch) >= 3, "\(name)")
                    #expect(Contrast.ratio(Contrast.readableGrey(on: swatch, minimum: 3), swatch) >= 3, "\(name)")
                }
            }
        }
    }

    @Test func aSwatchsEdgeCanBeSeenOnEveryBackground() {
        for scheme in Self.schemes {
            for background in Self.backgrounds {
                let behind = Contrast.background(hex: background.hex, opacity: background.opacity, colorScheme: scheme)
                #expect(Contrast.ratio(Contrast.readableGrey(on: behind, minimum: 3), behind) >= 3,
                        "\(background) \(scheme)")
            }
        }
    }

    @Test func swatchesAreBigEnoughToTapAndFourFitInARow() {
        #expect(ShopView.swatchSide >= Metrics.minimumTapSize)
        // Four swatches, the gaps between them and the page's margins.
        #expect(4 * ShopView.swatchSide + 3 * 10 + 2 * 16 <= Metrics.contentWidth)
    }
}

// MARK: - The loading screens

/// Stage 9B, D7: the first loading screen, which the app shows before ContentView, was always the starting blue, so a
/// child who had chosen another colour saw blue for two seconds before their own colour. Both loading screens now use
/// the colour GameData reads from the save as it's made.
@MainActor
struct Stage9BLoadingScreenTests {
    /// Every background colour the shop sells, at every strength, and the one every player starts with.
    private static let backgrounds: [ChosenBackground] =
        colours.flatMap { colour in colour.opacities.map { ChosenBackground(hex: colour.hexCode, opacity: $0.opacity) } }
            + [ChosenBackground(hex: "0000FF", opacity: 0.8)]

    /// A save with Everglow (gold) at full strength bought and chosen in the shop, as a child would leave it.
    private func goldSave() -> (UserDefaults, () -> Void) {
        let suite = "Stage9B-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let shop = GameData(defaults: defaults)
        shop.points = 100
        #expect(shop.purchaseColour(hex: "#FFD700", opacity: 1, price: 100) == .purchased)
        #expect(shop.selectColour(hex: "#FFD700", opacity: 1))
        return (defaults, { defaults.removePersistentDomain(forName: suite) })
    }

    @Test func aSavedColourIsReadAsTheGameIsMade() {
        let (defaults, cleanup) = goldSave()
        defer { cleanup() }
        // What the app does at launch: it makes its one GameData, then draws the first loading screen. Nothing has to
        // run in between for the colour to be there.
        let launched = GameData(defaults: defaults)
        #expect(launched.chosenBackground == ChosenBackground(hex: "#FFD700", opacity: 1))
    }

    @Test func aFreshInstallStartsOnTheStartingBlue() {
        let suite = "Stage9B-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let launched = GameData(defaults: defaults)
        #expect(launched.chosenBackground == ChosenBackground())
        #expect(launched.chosenBackground.hex == GameSettings.defaultColourHex)
        #expect(launched.chosenBackground.opacity == GameSettings.defaultOpacity)
    }

    @Test func bothLoadingScreensAreGivenTheSavedColour() throws {
        // The app's own loading screen, shown before ContentView exists.
        let app = try Stage9BSource.file("Maths_QuestApp.swift")
        let first = try #require(app.range(of: "LoadingView(isLoading: $isLoading)"))
        let end = try #require(app.range(of: "} else {", range: first.upperBound..<app.endIndex))
        #expect(app[first.upperBound..<end.lowerBound].contains(".environment(\\.chosenBackground, gameData.chosenBackground)"))
        // ContentView's, inside the NavigationStack it gives the colour to (as it does each screen pushed onto it).
        let contentView = try Stage9BSource.view("ContentView")
        #expect(contentView.contains("LoadingView(isLoading: $isLoading)"))
        #expect(Stage9BSource.count(".environment(\\.chosenBackground, gameData.chosenBackground)", in: contentView) == 2)
        // The loading screen draws that colour at its strength, and words and a spinner worked out from it.
        let loadingView = try Stage9BSource.view("LoadingView")
        #expect(loadingView.contains("Color(hex: chosenBackground.hex).opacity(chosenBackground.opacity)"))
        #expect(loadingView.contains(".foregroundStyle(.onBackground)"))
        #expect(loadingView.contains("ReadableOnBackground.onBackground.rgb(on: chosenBackground, colorScheme: colorScheme)"))
    }

    @Test func theWordsAndSpinnerCanBeReadOnEveryBackground() {
        for scheme in [ColorScheme.light, .dark] {
            for chosen in Self.backgrounds {
                // The words are `.onBackground`, and the spinner is drawn in the same colour. If there were none, the
                // spinner would be white, which can't be seen on light colours such as Everglow.
                let words = ReadableOnBackground.onBackground.rgb(on: chosen, colorScheme: scheme)
                #expect(words != nil, "\(chosen) \(scheme)")
                if let words {
                    #expect(Contrast.ratio(words, chosen.rgb(in: scheme)) >= 4.5, "\(chosen) \(scheme)")
                }
            }
        }
    }
}

// MARK: - Messages

@MainActor
struct Stage9BMessageTests {
    private let red = colours.first { $0.name == "Red" }!

    @Test func pointsAreCountedInWords() {
        #expect(ShopView.pointsText(0) == "0 points")
        #expect(ShopView.pointsText(1) == "1 point")
        #expect(ShopView.pointsText(25) == "25 points")
    }

    @Test func notEnoughPointsSaysWhatItCostsAndWhatTheChildHas() {
        #expect(ShopView.notEnoughPointsMessage(for: red, red.opacities[0], points: 3)
                == "Not enough points! Red 70% costs 25 points. You have 3 points.")
        #expect(ShopView.notEnoughPointsMessage(for: red, red.opacities[3], points: 1)
                == "Not enough points! Red 100% costs 100 points. You have 1 point.")
    }

    @Test func unlockingSaysHowToUseTheColour() {
        // Buying a colour doesn't choose it, so the message says how to.
        #expect(ShopView.unlockedMessage(for: red, red.opacities[1]) == "Red 80% unlocked! Tap it again to use it.")
    }

    @Test func spendingPointsSaysWhatsLeft() {
        #expect(ShopView.spentMessage(1, left: 0) == "1 point taken. You have 0 points left.")
        #expect(ShopView.spentMessage(5, left: 1) == "5 points taken. You have 1 point left.")
        #expect(ShopView.notEnoughToSpendMessage(points: 2) == "Not enough points. You have 2 points.")
        #expect(ShopView.invalidPointsMessage == "Please enter a valid number of points.")
        #expect(ShopView.cannotBuyMessage == "That colour can't be bought.")
    }

    @Test func everyStrengthIsAWholePercent() {
        for colour in colours {
            #expect(colour.opacities.map(ShopView.percent) == [70, 80, 90, 100], "\(colour.name)")
        }
    }

    @Test func feedbackSaysWhatHappenedWhenEnterWasPressed() {
        typealias Status = FeedbackView.SendStatus
        #expect(Status.empty.message == "Please type a message first.")
        #expect(Status.sending.message == "Sending…")
        #expect(Status.failed.message == "That didn't send. Check the internet and try again.")
        #expect(Status.sent.message == "Thank you! Your message was sent.")
        #expect(Status.empty.tone == .information)
        #expect(Status.sending.tone == .information)
        #expect(Status.failed.tone == .problem)
        #expect(Status.sent.tone == .success)
    }

    @Test func noMessageCanBeMistakenForThePoints() {
        // The points chip is the only thing that reads "Points: …", which the UI tests rely on.
        var messages = [ShopView.cannotBuyMessage, ShopView.invalidPointsMessage, "Name saved.",
                        ShopView.notEnoughToSpendMessage(points: 0), ShopView.spentMessage(1, left: 1)]
        messages += [FeedbackView.SendStatus.empty, .sending, .failed, .sent].map(\.message)
        for colour in colours {
            for option in colour.opacities {
                messages.append(ShopView.notEnoughPointsMessage(for: colour, option, points: 0))
                messages.append(ShopView.unlockedMessage(for: colour, option))
            }
        }
        for message in messages {
            #expect(!message.hasPrefix("Points:"), "\(message)")
            #expect(!message.isEmpty)
        }
    }
}

// MARK: - Form screens

@MainActor
struct Stage9BFormScreenTests {
    @Test func aBannerIsReadAsOneItem() {
        let (gameData, cleanUp) = throwawayGame()
        defer { cleanUp() }
        #expect(spokenLabels(of: StatusBanner(message: "Name saved.", tone: .success), gameData: gameData)
                == ["Name saved."])
    }

    @Test func settingsReadsTheHeaderThenEachCardInOrder() {
        let (gameData, cleanUp) = throwawayGame()
        defer { cleanUp() }
        let labels = spokenLabels(of: SettingsView(), gameData: gameData)
        #expect(labels == ["Menu", "Points: 7", "Settings", "Name", "Name", "Enter", "SFX Volume",
                           "Sound effects volume"])
    }

    @Test func settingsNameIsBelowThePoints() throws {
        let (gameData, cleanUp) = throwawayGame()
        defer { cleanUp() }
        let items = spokenItems(of: SettingsView(), gameData: gameData)
        let points = try #require(items.first { $0.label == "Points: 7" })
        // Nothing on the form is drawn over the points.
        for item in items where item.label != "Points: 7" && item.label != "Menu" {
            #expect(!item.frame.intersects(points.frame), "\(item.label) \(item.frame) \(points.frame)")
            #expect(item.frame.minY >= points.frame.maxY - 1, "\(item.label) \(item.frame) \(points.frame)")
        }
    }

    @Test func theShopReadsTheHeaderThenSpendPointsThenEveryColour() throws {
        let (gameData, cleanUp) = throwawayGame()
        defer { cleanUp() }
        let items = spokenItems(of: ShopView(), gameData: gameData)
        let labels = items.map(\.label)
        #expect(Array(labels.prefix(8)) == ["Menu", "Points: 7", "Shop", "Spend points on background colours",
                                            "Spend Points", "Points to spend", "Enter", "Background Colours"])
        let swatches = labels.filter { $0.hasSuffix(" percent") }
        // Every colour at every strength, none left out, as none are in a lazy stack.
        #expect(swatches.count == 60)
        #expect(swatches.first == "Red, 70 percent")
        let points = try #require(items.first { $0.label == "Points: 7" })
        for item in items where item.label != "Points: 7" && item.label != "Menu" {
            #expect(!item.frame.intersects(points.frame), "\(item.label)")
        }
    }

    @Test func informationReadsItsTitleThenTheMessage() throws {
        let (gameData, cleanUp) = throwawayGame()
        defer { cleanUp() }
        let labels = spokenLabels(of: InformationView(), gameData: gameData)
        #expect(Array(labels.prefix(3)) == ["Menu", "Points: 7", "Information"])
        let message = try #require(labels.dropFirst(3).first)
        #expect(message.hasPrefix("Message from the creator."))
        #expect(message.contains("Hi there Player!"))
        // FB-E: the whole message is one item, read in full.
        #expect(message == InformationView.message(for: ""))
    }
}

// MARK: - How the screens are built

struct Stage9BSourceTests {
    static let forms = ["ShopView", "FeedbackView", "InformationView", "RemoveAdsView", "SettingsView"]

    @Test func everyFormHasTheSameHeaderAndColumn() throws {
        for form in Self.forms {
            let body = try Stage9BSource.view(form)
            #expect(Stage9BSource.count("FormScreen(selectedTab:", in: body) == 1, "\(form)")
            // The header comes from FormScreen, so no form draws one of its own over its content.
            #expect(!body.contains("NavigationBar("), "\(form)")
        }
    }

    @Test func formMessagesStayUntilTheChildDoesSomethingElse() throws {
        // Messages used to vanish after one or two seconds, before a child could read them.
        for form in Self.forms {
            let body = try Stage9BSource.view(form)
            #expect(!body.contains("asyncAfter"), "\(form)")
        }
    }

    @Test func noFormLeavesItemsOutForVoiceOver() throws {
        // A lazy stack only makes the items on screen, so VoiceOver and the UI tests couldn't find the rest.
        for form in Self.forms {
            let body = try Stage9BSource.view(form)
            #expect(!body.contains("Lazy"), "\(form)")
        }
    }

    @Test func noInternetOpensTheAppsOwnSettingsPage() throws {
        let body = try Stage9BSource.view("NoInternetView")
        #expect(body.contains("UIApplication.openSettingsURLString"))
        // A private link to a page in Settings, which Apple doesn't allow.
        #expect(!body.contains("App-Prefs"))
        let app = try Stage9BSource.file("ContentView.swift") + Stage9BSource.file("DesignComponents.swift")
        #expect(!app.contains("App-Prefs"))
    }

    @Test func feedbackCanOnlySendOneMessageAtATime() throws {
        let body = try Stage9BSource.view("FeedbackView")
        #expect(body.contains("guard !isSending"))
        // The connection is checked once per Enter: the handler is set before the monitor starts, and acted on once.
        let handler = try #require(body.range(of: "monitor.pathUpdateHandler"))
        let start = try #require(body.range(of: "monitor.start(queue:"))
        #expect(handler.lowerBound < start.lowerBound)
        #expect(body.contains("guard isChecking else { return }"))
    }

    /// Feedback sent a message of only spaces, because it only checked that the box wasn't empty (D6). Spaces and empty
    /// lines alone now say "Please type a message first." and send nothing: Enter checks for them before it does anything
    /// that sends, and nothing else sends.
    @Test func feedbackSendsNothingThatIsOnlySpaces() throws {
        let body = try Stage9BSource.view("FeedbackView")
        let send = try #require(body.range(of: "private func send() {"))
        let rest = send.upperBound..<body.endIndex
        let blank = try #require(body.range(
            of: "guard !feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {", range: rest))
        // It says why and stops.
        let branchEnd = try #require(body.range(of: "}", range: blank.upperBound..<body.endIndex))
        let branch = body[blank.upperBound..<branchEnd.lowerBound]
        #expect(branch.contains("show(.empty)"))
        #expect(branch.contains("return"))
        // Before everything that sends.
        for step in ["guard !isSending", "isSending = true", "checkInternetConnection {", "submitFeedback()"] {
            let found = try #require(body.range(of: step, range: rest), "\(step)")
            #expect(branchEnd.upperBound <= found.lowerBound, "\(step)")
        }
        // Nothing else sends: Enter is the only caller of send(), submitFeedback() is declared once and called once (in
        // send(), checked above), and it is the only place that adds a message.
        #expect(Stage9BSource.count("{ send() }", in: body) == 1)
        #expect(Stage9BSource.count("submitFeedback()", in: body) == 2)
        #expect(Stage9BSource.count("addDocument(", in: body) == 1)
    }

    /// The activities with a working-out pad hid their question when the keyboard came up (D9). The question scrolls
    /// the row with Enter up to the keyboard, and the pad was above that row, so it pushed the question off the top.
    /// Each pad is now below the row, where the keyboard can cover it instead.
    ///
    /// Updated deliberately in Stage 9C: after Skip, Year 6 Ratio's Next Question takes the place of the row with Enter
    /// and is marked as the row instead, so Ratio has two rows, one for each case. The pad must be below both.
    /// Updated deliberately in Stage 9C Batch 2 (B2-1): Algebra and Probability now show a worked solution and Next
    /// Question after Skip too, so they also have two rows.
    @Test func everyWorkingOutPadIsBelowEnter() throws {
        let activities = ["Year3FractionsView", "Year3MeasurementView", "Year3TimeView", "Year4DecimalsView",
                          "Year4MoneyView", "Year5PercentagesView", "Year5StatisticsView", "Year5VolumeView",
                          "Year6AlgebraView", "Year6ProbabilityView", "Year6RatiosView"]
        let withNextQuestion: Set = ["Year6RatiosView", "Year6AlgebraView", "Year6ProbabilityView"]
        for activity in activities {
            let body = try Stage9BSource.view(activity)
            #expect(Stage9BSource.count("WorkingOutView(", in: body) == 1, "\(activity)")
            let rows = withNextQuestion.contains(activity) ? 2 : 1
            #expect(Stage9BSource.count(".questionSubmitRow()", in: body) == rows, "\(activity)")
            let row = try #require(body.range(of: ".questionSubmitRow()", options: .backwards), "\(activity)")
            let pad = try #require(body.range(of: "WorkingOutView("), "\(activity)")
            #expect(row.upperBound <= pad.lowerBound, "\(activity)")
        }
        // Every pad is in one of those activities.
        let source = try Stage9BSource.file("ContentView.swift")
        #expect(Stage9BSource.count("WorkingOutView(canvasView:", in: source) == activities.count)
    }

    /// On iPad every question was a phone screen scaled up to the iPad's width (I13). Questions now sit in the same
    /// centred column as the menus and forms, with their sizes worked out from the column's width. Every iPhone is
    /// narrower than the column, so on iPhone nothing changes.
    @Test func questionsAreSizedFromTheColumnOnIPad() throws {
        let activities = ["Year1CountingView", "Year1AdditionView", "Year1SubtractionView", "Year2MultiplicationView",
                          "Year2DivisionView", "Year2ShapesView", "Year3FractionsView", "Year3MeasurementView",
                          "Year3TimeView", "Year4DecimalsView", "Year4GeometryView", "Year4MoneyView",
                          "Year5PercentagesView", "Year5StatisticsView", "Year5VolumeView", "Year6AlgebraView",
                          "Year6ProbabilityView", "Year6RatiosView"]
        let sharedParts = ["WorkingOutView", "AnswerFeedbackText", "RulerView", "ShapeView", "FractionAnswerBoxes"]
        for name in activities + sharedParts {
            let body = try Stage9BSource.view(name)
            #expect(!body.contains("UIScreen.main.bounds.width"), "\(name)")
            #expect(!body.contains("UIScreen.main.bounds.size"), "\(name)")
        }
        for activity in activities {
            #expect(try Stage9BSource.view(activity).contains("Metrics.contentWidth"), "\(activity)")
        }
        #expect(try Stage9BSource.view("QuestionLayout<Content: View>").contains(".readableColumn()"))
        // The widest iPhones, the Pro Max and Plus models, are 440 points wide.
        #expect(440 <= Metrics.columnWidth)
    }
}

// MARK: - Questions laid out more tightly while the player types

/// Stage 9B, D9: the questions that were still too tall to fit above the keyboard on an iPhone SE.
struct Stage9BTypingLayoutTests {
    /// The angle to name is drawn in a frame half as tall as it is wide, with the corner at the bottom, because the
    /// second arm always points up. Every angle the questions use is drawn inside that frame, at its angle, with arms
    /// as long as they were in the square frame it replaced.
    @Test func everyAngleIsDrawnInsideItsHalfHeightFrame() {
        for contentWidth: CGFloat in [320, 375, 402, 440, 600] {
            let frame = CGRect(x: 0, y: 0, width: contentWidth * 0.4, height: contentWidth * 0.2 + 4)
            let armInTheSquareFrame = contentWidth * 0.4 / 2 - 20
            for angle in Year4GeometryQuestion.angles {
                let path = AngleDrawingView(angle: angle).path(in: frame)
                let label = "\(angle)° at width \(contentWidth)"
                // The lines are 2 points wide, so they reach a point either side of the path.
                let drawn = path.boundingRect.insetBy(dx: -1, dy: -1)
                #expect(frame.contains(drawn), "\(label): \(drawn) isn't inside \(frame)")

                var points: [CGPoint] = []
                path.forEach { element in
                    switch element {
                    case .move(to: let point), .line(to: let point):
                        points.append(point)
                    default:
                        break
                    }
                }
                // The corner, the end of the arm pointing right, the corner again and the end of the turned arm.
                guard points.count == 4 else {
                    Issue.record("\(label): \(points.count) points")
                    continue
                }
                let corner = points[0]
                for end in [points[1], points[3]] {
                    #expect(abs(hypot(end.x - corner.x, end.y - corner.y) - armInTheSquareFrame) < 0.001, "\(label)")
                }
                #expect(abs(points[1].y - corner.y) < 0.001 && points[1].x > corner.x, "\(label)")
                let turned = atan2(corner.y - points[3].y, points[3].x - corner.x) * 180 / .pi
                #expect(abs(turned - CGFloat(angle)) < 0.001, "\(label): drawn at \(turned)°")
            }
        }
    }

    /// The clock to read, a shape with its sides, the bar chart and a cube or cuboid each have a tighter layout for
    /// while the player types. Each marks where its question starts, so the layout knows how tall the question is.
    @Test func theTallestQuestionsHaveATighterLayoutForTyping() throws {
        for activity in ["Year3TimeView", "Year4GeometryView", "Year5StatisticsView", "Year5VolumeView"] {
            let body = try Stage9BSource.view(activity)
            #expect(Stage9BSource.count(".compactWhileTyping($isCompact", in: body) == 1, "\(activity)")
            #expect(Stage9BSource.count(".questionTop()", in: body) == 1, "\(activity)")
        }
        // Each switches between layouts that keep the same views, so the answer box being typed in keeps the keyboard.
        for activity in ["Year4GeometryView", "Year5StatisticsView", "Year5VolumeView"] {
            #expect(try Stage9BSource.view(activity).contains("AnyLayout(HStackLayout("), "\(activity)")
        }
    }

    /// With the largest text on an iPhone SE (on an iPhone 17 Pro, the ruler question), the words of these questions
    /// only just didn't fit above the keyboard. So
    /// while the player types, if the question doesn't fit, the gaps are smaller, and nothing else changes. With the
    /// keyboard down, and wherever the question fits above it, the layout is as before.
    @Test func questionsThatOnlyJustDontFitHaveSmallerGapsWhileThePlayerTypes() throws {
        for activity in ["Year1AdditionView", "Year1SubtractionView", "Year2MultiplicationView", "Year2DivisionView"] {
            let body = try Stage9BSource.view(activity)
            #expect(Stage9BSource.count(".compactWhileTyping($isCompact)", in: body) == 1, "\(activity)")
            #expect(Stage9BSource.count(".questionTop()", in: body) == 1, "\(activity)")
            #expect(body.contains("VStack(spacing: isCompact ? 8 : 20) {"), "\(activity)")
        }

        // The picture is the top of the question, so the question is measured from the top of the screen's content.
        let shapes = try Stage9BSource.view("Year2ShapesView")
        #expect(Stage9BSource.count(".compactWhileTyping($isCompact)", in: shapes) == 1)
        #expect(!shapes.contains(".questionTop()"))
        #expect(shapes.contains("VStack(spacing: isCompact ? 4 : nil) {"))

        // The three time questions without a clock: their words and the instructions of "What is the time … after".
        // The clock beside its instructions is fitted only on the clock to read.
        let time = try Stage9BSource.view("Year3TimeView")
        #expect(Stage9BSource.count(".padding(.vertical, isCompact ? 4 : nil)", in: time) == 4)
        #expect(time.contains("allowed: isReadingAClock ? !dynamicTypeSize.isAccessibilitySize : !showsAClock)"))
        #expect(time.contains("paused: showMessage || !isCompact || !isReadingAClock, aboveKeyboard: true)"))

        // Perimeter and area: smaller gaps, and a smaller margin above and below Enter, as well as the shape beside
        // the answer box.
        let geometry = try Stage9BSource.view("Year4GeometryView")
        #expect(geometry.contains("VStack(spacing: isCompact ? 4 : 12) {"))
        #expect(Stage9BSource.count(".padding(.vertical, isCompact ? 8 : nil)", in: geometry) == 1)

        // Measuring with the ruler: a smaller margin above and below Enter, measured from the top of the screen's
        // content, which is the top of the question.
        let measurement = try Stage9BSource.view("Year3MeasurementView")
        #expect(Stage9BSource.count(".compactWhileTyping($isCompact)", in: measurement) == 1)
        #expect(!measurement.contains(".questionTop()"))
        #expect(Stage9BSource.count(".padding(.vertical, isCompact ? 8 : nil)", in: measurement) == 1)
    }

    /// A player can tap the answer box again while "Incorrect. Try Again!" shows. The keyboard then comes up with the
    /// message still above Enter, and scrolling Enter above the keyboard could push the question's words off the top.
    /// So the question scrolls only as far as the message's first line, and Enter comes back above the keyboard once
    /// the message has gone, after "Correct!" too. The message isn't counted when choosing the tighter layout.
    /// The UI tests in `Stage9BInteractionUITests` check what the player sees.
    @Test func tappingTheAnswerBoxDuringTheMessageKeepsTheQuestionInView() throws {
        let layout = try Stage9BSource.declaration(startingWith: "\nstruct QuestionLayout<Content: View>: View {")
        #expect(layout.contains("bounds.message != nil"))
        #expect(layout.contains("scroller.scrollTo(AnswerFeedbackFirstLine.id, anchor: .bottom)"))
        #expect(layout.contains("scroller.scrollTo(QuestionSubmitRow.id, anchor: .bottom)"))

        let message = try Stage9BSource.view("AnswerFeedbackText")
        #expect(message.contains(".id(AnswerFeedbackFirstLine.id)"))
        #expect(message.contains("QuestionBounds.Value(message: $0)"))
        #expect(message.contains("if !isCorrect || roomAboveKeyboard > 0 {"))

        let compact = try Stage9BSource.declaration(startingWith: "\nprivate struct CompactWhileTyping: ViewModifier {")
        #expect(compact.contains("if !isCompact, !isMessageShowing {"))
    }
}

// MARK: - The cuboid's corners

struct Stage9BVolumeDiagramInkTests {
    /// The box round everything the cuboid's lines draw, with the drawing's top left corner at 0, 0: the faces'
    /// outlines and the solid left edge 2 points wide and the dashed edge 1, stroked as Core Graphics strokes them with
    /// SwiftUI's `stroke` defaults (flat ends, and mitred corners up to 10 times the line's width). The dashed edge is
    /// measured as if it were solid, which can only make the box bigger.
    private static let ink: CGRect = {
        func stroked(_ points: [CGPoint], closed: Bool, width: CGFloat) -> CGRect {
            let path = CGMutablePath()
            path.addLines(between: points)
            if closed {
                path.closeSubpath()
            }
            return path.copy(strokingWithWidth: width, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
                .boundingBoxOfPath
        }
        let faces = [VolumeShapeLayout.topFace, VolumeShapeLayout.frontFace, VolumeShapeLayout.rightFace,
                     VolumeShapeLayout.bottomFace]
        return faces.map { stroked($0, closed: true, width: VolumeShapeLayout.lineWidth) }
            .reduce(stroked(VolumeShapeLayout.leftEdge, closed: false, width: VolumeShapeLayout.lineWidth)) {
                $0.union($1)
            }
            .union(stroked(VolumeShapeLayout.heightEdge, closed: false, width: 1))
    }()

    /// The cuboid's lines meet in mitred corners, which come to points beyond the corners themselves: 2.4 points out
    /// at the 45° ones. The diagram used to end at the corners, so on the iPhone SE, where it's at the top of the
    /// screen and, while the player types, at the left edge, those points were cut off by the header and the edge of
    /// the screen (the UI test measured the picture 2.4 points past the left edge). Now everything the cuboid draws,
    /// and the measurements' outlines, are inside the diagram, whatever size the measurements are.
    @Test func everythingTheCuboidDrawsIsInsideItsDiagram() {
        // The check catches the points: they reach past the drawing on every side.
        #expect(Self.ink.minX < -2 && Self.ink.minY < -2, "\(Self.ink)")
        #expect(Self.ink.maxX > 152 && Self.ink.maxY > 152, "\(Self.ink)")

        let sizes = Stage6EVolumeDiagramTests.someSizes
        let outline = VolumeShapeLayout.outlineWidth
        for width in sizes {
            for length in sizes {
                for height in sizes {
                    let layout = VolumeShapeLayout(width: width, length: length, height: height)
                    let diagram = CGRect(origin: .zero, size: layout.size).insetBy(dx: -0.001, dy: -0.001)
                    let ink = Self.ink.offsetBy(dx: layout.drawing.minX, dy: layout.drawing.minY)
                    #expect(diagram.contains(ink), "lines at \(width), \(length), \(height)")
                    for label in [layout.widthLabel, layout.lengthLabel, layout.heightLabel] {
                        #expect(diagram.contains(label.insetBy(dx: -outline, dy: -outline)),
                                "outline at \(width), \(length), \(height)")
                    }
                }
            }
        }
    }
}

// MARK: - The numbers to count

/// Stage 9B final corrections: on an iPhone SE at the largest text size, about half the numbers on the Counting tiles
/// were cut short to "…". Each number had only the middle of its tile, and grew with the text size without limit, so
/// even drawn at half size two digits didn't fit. The numbers now have the whole tile, less a small margin, and on an
/// iPhone stop growing at the size the question's words stop at. On iPad, which has room, they grow as body text does,
/// as they did before. The tiles are the size they were.
@MainActor
struct Stage9BCountingTileTests {
    /// The width of the content on every iPhone from the SE to the Pro Max, and the iPad's column.
    static let contentWidths: [CGFloat] = [375, 390, 393, 402, 414, 428, 430, 440, Metrics.columnWidth]

    /// Every number a question can show.
    static let numbers = (Year1CountingQuestion.starts.lowerBound
                          ... Year1CountingQuestion.starts.upperBound + Year1CountingQuestion.length - 1).map(String.init)

    /// How wide a number is at a size, in the system font the tile draws it in, rounded up.
    static func width(of number: String, size: CGFloat) -> CGFloat {
        ceil(width(of: number, in: UIFont.systemFont(ofSize: size)))
    }

    /// How wide a number is in a font.
    static func width(of number: String, in font: UIFont) -> CGFloat {
        (number as NSString).size(withAttributes: [.font: font]).width
    }

    /// The size a tile draws its number at on a screen, before drawing it smaller to fit.
    static func fontSize(for dynamicTypeSize: DynamicTypeSize, contentWidth: CGFloat) -> CGFloat {
        CountingTile.fontSize(for: dynamicTypeSize, contentWidth: contentWidth)
    }

    /// The size of the system's body text, which the numbers were drawn in before.
    static func bodySize(for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
        return UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits).pointSize
    }

    @Test func theNumbersGoUpTo100() {
        #expect(Self.numbers.first == "0")
        #expect(Self.numbers.last == "100")
    }

    /// Every number, at every text size and on every screen, fits on its tile without being cut short: drawn smaller
    /// if it must be, but never smaller than the tile allows, and never smaller than it is at the usual text size.
    @Test func everyNumberFitsOnItsTileAtEveryTextSize() {
        for contentWidth in Self.contentWidths {
            let room = CountingTile.roomForNumber(for: contentWidth)
            for dynamicTypeSize in DynamicTypeSize.allCases {
                let size = Self.fontSize(for: dynamicTypeSize, contentWidth: contentWidth)
                for number in Self.numbers {
                    let width = Self.width(of: number, size: size)
                    #expect(width * CountingTile.minimumScaleFactor <= room,
                            "\(number) is \(width) points wide at \(size) points, at \(dynamicTypeSize), with \(room) points of room on a \(contentWidth)-point screen.")
                    let drawn = size * min(1, room / width)
                    #expect(drawn >= CountingTile.usualFontSize,
                            "\(number) is drawn at \(drawn) points at \(dynamicTypeSize) on a \(contentWidth)-point screen.")
                }
            }
        }
    }

    /// Up to the largest of the usual text sizes every number is drawn at full size, with room to spare.
    @Test func numbersAreFullSizeAtTheUsualTextSizes() {
        for contentWidth in Self.contentWidths {
            let room = CountingTile.roomForNumber(for: contentWidth)
            for dynamicTypeSize in DynamicTypeSize.allCases where !dynamicTypeSize.isAccessibilitySize {
                let size = Self.fontSize(for: dynamicTypeSize, contentWidth: contentWidth)
                for number in Self.numbers {
                    #expect(Self.width(of: number, size: size) <= room,
                            "\(number) at \(dynamicTypeSize) on a \(contentWidth)-point screen.")
                }
            }
        }
    }

    /// At every text size, on every screen, every number up to 99 is drawn at full size, so the numbers in a row are
    /// the same size; only 100 is sometimes drawn a little smaller to fit.
    @Test func everyNumberUpTo99IsFullSizeAtEveryTextSize() {
        for contentWidth in Self.contentWidths {
            let room = CountingTile.roomForNumber(for: contentWidth)
            for dynamicTypeSize in DynamicTypeSize.allCases {
                let size = Self.fontSize(for: dynamicTypeSize, contentWidth: contentWidth)
                for number in Self.numbers where number.count < 3 {
                    #expect(Self.width(of: number, size: size) <= room,
                            "\(number) is \(Self.width(of: number, size: size)) points wide at \(size) points, at \(dynamicTypeSize), with \(room) points of room on a \(contentWidth)-point screen.")
                }
            }
        }
    }

    /// The numbers stop growing only where the tiles need them to: on an iPhone at the question's largest size, and on
    /// iPad not before body text does, so they're as big there as they were before.
    @Test func theNumbersStopGrowingOnlyOnAnIPhone() {
        for contentWidth in Self.contentWidths {
            let isIPad = contentWidth >= Metrics.columnWidth
            for dynamicTypeSize in DynamicTypeSize.allCases {
                let size = Self.fontSize(for: dynamicTypeSize, contentWidth: contentWidth)
                let body = max(CountingTile.usualFontSize, Self.bodySize(for: dynamicTypeSize))
                let expected = isIPad ? body : min(body, ScaledFont.usualMaximum)
                #expect(abs(size - expected) < 0.01,
                        "\(size) points at \(dynamicTypeSize) on a \(contentWidth)-point screen; body text is \(body).")
            }
        }
        #expect(Self.fontSize(for: .accessibility5, contentWidth: 375) == ScaledFont.usualMaximum)
        #expect(Self.fontSize(for: .accessibility5, contentWidth: Metrics.columnWidth) > 50)
    }

    /// At the usual text size the numbers are body text's size, as they always were, on tiles the size they always
    /// were, so the screen looks as it did.
    @Test func theTilesLookAsTheyDidAtTheUsualTextSize() {
        for contentWidth in Self.contentWidths {
            #expect(Self.fontSize(for: .large, contentWidth: contentWidth) == 17)
            #expect(CountingTile.width(for: contentWidth) == contentWidth / 12 + 32)
        }
    }

    /// The check would have caught the old tiles. They drew each number in body text, which grew with the text size
    /// without limit, in only the middle of the tile, a twelfth of the screen's width, and a number that didn't fit
    /// even drawn at half size was cut short. A screenshot from before the fix, on an iPhone SE at the largest text
    /// size, shows 51, 52 and 57 on their tiles and "…" where 53, 54, 55, 56 and 58 should be; the check agrees.
    @Test func theCheckCatchesTheOldTiles() {
        let oldRoom: CGFloat = 375 / 12
        let traits = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        let oldFont = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits)
        let cutShort = Set(Self.numbers.filter { Self.width(of: $0, in: oldFont) * 0.5 > oldRoom })
        let widths = (50...58).map { "\($0): \(Self.width(of: String($0), in: oldFont))" }
        let details = "\(oldFont.pointSize)-point \(oldFont.fontName); \(widths); cut short: \(cutShort.sorted())"
        #expect(cutShort.isSuperset(of: ["53", "54", "55", "56", "58", "100"]), "\(details)")
        #expect(cutShort.isDisjoint(with: ["51", "52", "57"]), "\(details)")
        #expect(cutShort.count > 10, "\(details)")
    }
}
