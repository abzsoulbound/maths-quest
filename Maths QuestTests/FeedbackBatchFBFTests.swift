//
//  FeedbackBatchFBFTests.swift
//  Maths QuestTests
//
//  User feedback, batch FB-F: "Surprise me" in the Shop (FB-09, approved 15 November).
//  - It picks a background at random from the colours the child has already unlocked, never the one in use.
//  - It never spends points, never unlocks or buys anything, and the save keeps the same fields.
//  - With no other colour unlocked it is turned off, and a line says why.
//  - It sits under "Background Colours", before the swatches, so VoiceOver still reads the header, Spend Points and
//    the heading first, and then every swatch.
//

import Foundation
import Testing
@testable import Maths_Quest

// SeededGenerator (SplitMix64, repeatable picks) is the one in MathematicalCorrectnessTests.swift.

@MainActor
struct FBFSurpriseTests {
    /// A new game in a save of its own: Blue 80% unlocked and chosen, as every player starts, and 100 points.
    static func newGame() -> (GameData, UserDefaults, () -> Void) {
        let suite = "FBF-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let gameData = GameData(defaults: defaults)
        gameData.points = 100
        gameData.saveData()
        return (gameData, defaults, { defaults.removePersistentDomain(forName: suite) })
    }

    /// The game as saved, field by field.
    static func saved(_ defaults: UserDefaults) throws -> [String: Any] {
        let data = try #require(defaults.data(forKey: gameSettingsKey))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    static let red70 = ShopView.SurpriseOption(name: "Red", hexCode: "#FF0000", opacity: 0.7)
    static let orange80 = ShopView.SurpriseOption(name: "Orange", hexCode: "#FFA500", opacity: 0.8)
    static let blue80 = ShopView.SurpriseOption(name: "Blue", hexCode: "#0000FF", opacity: 0.8)

    /// Every swatch in the shop.
    static var everySwatch: [ShopView.SurpriseOption] {
        colours.flatMap { colour in
            colour.opacities.map { ShopView.SurpriseOption(name: colour.name, hexCode: colour.hexCode, opacity: $0.opacity) }
        }
    }

    static func current(_ gameData: GameData) -> ShopView.SurpriseOption? {
        everySwatch.first { gameData.isColourSelected($0.hexCode, opacity: $0.opacity) }
    }

    // MARK: What it can pick

    @Test func withOnlyTheStartingColourThereIsNothingToPick() throws {
        let (gameData, defaults, cleanUp) = Self.newGame()
        defer { cleanUp() }
        let before = try Self.saved(defaults)
        #expect(ShopView.surpriseOptions(in: gameData).isEmpty)
        var generator = SeededGenerator(seed: 1)
        #expect(ShopView.surprise(gameData, using: &generator) == nil)
        #expect(Self.current(gameData) == Self.blue80)
        #expect(gameData.points == 100)
        #expect(NSDictionary(dictionary: try Self.saved(defaults)) == NSDictionary(dictionary: before))
    }

    @Test func itOffersOnlyUnlockedColoursAndNotTheOneInUse() {
        let (gameData, _, cleanUp) = Self.newGame()
        defer { cleanUp() }
        gameData.unlockedColours["#FF0000"] = [0.7]
        gameData.unlockedColours["#FFA500"] = [0.8]
        let options = ShopView.surpriseOptions(in: gameData)
        #expect(Set(options.map(\.hexCode)) == ["#FF0000", "#FFA500"])
        #expect(options.contains(Self.red70) && options.contains(Self.orange80))
        #expect(options.count == 2)
        #expect(!options.contains(Self.blue80))
        for option in options {
            #expect(gameData.isColourUnlocked(option.hexCode, opacity: option.opacity))
        }
    }

    /// A colour unlocked in the save but not sold in the shop is never offered: only swatches the child can see.
    @Test func itOffersOnlyColoursTheShopShows() {
        let (gameData, _, cleanUp) = Self.newGame()
        defer { cleanUp() }
        gameData.unlockedColours["#123456"] = [0.7]
        gameData.unlockedColours["#FF0000"] = [0.55]
        #expect(ShopView.surpriseOptions(in: gameData).isEmpty)
        gameData.unlockedColours["#FF0000"] = [0.55, 1.0]
        #expect(ShopView.surpriseOptions(in: gameData) == [ShopView.SurpriseOption(name: "Red", hexCode: "#FF0000", opacity: 1.0)])
    }

    // MARK: Picking

    @Test func aPickChangesOnlyTheBackgroundAndSpendsNothing() throws {
        let (gameData, defaults, cleanUp) = Self.newGame()
        defer { cleanUp() }
        gameData.unlockedColours["#FF0000"] = [0.7]
        gameData.unlockedColours["#FFA500"] = [0.8]
        gameData.username = "Sam"
        gameData.totalQuestionsAnswered = 42
        gameData.saveData()
        let unlockedBefore = gameData.unlockedColours
        let before = try Self.saved(defaults)

        var generator = SeededGenerator(seed: 7)
        let pick = try #require(ShopView.surprise(gameData, using: &generator))
        #expect(pick == Self.red70 || pick == Self.orange80)
        #expect(Self.current(gameData) == pick)
        #expect(gameData.points == 100)
        #expect(gameData.unlockedColours == unlockedBefore)

        // The save has the same fields, and only the two background fields changed.
        let after = try Self.saved(defaults)
        #expect(Set(after.keys) == Set(before.keys))
        for key in before.keys where key != "backgroundColourHex" && key != "backgroundOpacity" {
            #expect(NSDictionary(dictionary: [key: after[key] as Any]) == NSDictionary(dictionary: [key: before[key] as Any]),
                    "\(key)")
        }
        #expect(after["backgroundColourHex"] as? String == pick.hexCode)
        #expect(after["backgroundOpacity"] as? Double == pick.opacity)
        #expect(savedSettingsReadableBy13(in: defaults))

        // A new launch reads the same choice back.
        let reloaded = GameData(defaults: defaults)
        #expect(Self.current(reloaded) == pick)
        #expect(reloaded.points == 100)
    }

    @Test func itNeverPicksTheColourInUseOrALockedOne() throws {
        let (gameData, _, cleanUp) = Self.newGame()
        defer { cleanUp() }
        gameData.unlockedColours["#FF0000"] = [0.7]
        gameData.unlockedColours["#FFA500"] = [0.8]
        let unlocked: Set<String> = ["#FF0000@0.7", "#FFA500@0.8", "#0000FF@0.8"]
        var generator = SeededGenerator(seed: 2026)
        var seen: Set<String> = []
        for _ in 0..<300 {
            let before = try #require(Self.current(gameData))
            let pick = try #require(ShopView.surprise(gameData, using: &generator))
            #expect(pick != before)
            let key = "\(pick.hexCode)@\(pick.opacity)"
            #expect(unlocked.contains(key), "\(key)")
            seen.insert(key)
        }
        #expect(seen == unlocked)
        #expect(gameData.points == 100)
    }

    /// With every swatch unlocked, each one comes up, so none is left out of the draw.
    @Test func everyUnlockedSwatchCanComeUp() throws {
        let (gameData, _, cleanUp) = Self.newGame()
        defer { cleanUp() }
        for colour in colours {
            gameData.unlockedColours[colour.hexCode] = colour.opacities.map(\.opacity)
        }
        #expect(ShopView.surpriseOptions(in: gameData).count == 59)
        var generator = SeededGenerator(seed: 15)
        var seen: [String: Int] = [:]
        for _ in 0..<6000 {
            let pick = try #require(ShopView.surprise(gameData, using: &generator))
            seen["\(pick.hexCode)@\(pick.opacity)", default: 0] += 1
        }
        #expect(seen.count == 60)
        // Roughly even: each of the 60 comes up about 100 times in 6,000.
        #expect(seen.values.min()! >= 50 && seen.values.max()! <= 160, "\(seen.values.sorted())")
    }

    /// It is not the purchase path: it can't take points even when it has the chance.
    @Test func itNeverBuysAColour() throws {
        let (gameData, _, cleanUp) = Self.newGame()
        defer { cleanUp() }
        gameData.points = 10_000
        let unlockedBefore = gameData.unlockedColours
        var generator = SeededGenerator(seed: 3)
        for _ in 0..<50 {
            #expect(ShopView.surprise(gameData, using: &generator) == nil)
        }
        #expect(gameData.points == 10_000)
        #expect(gameData.unlockedColours == unlockedBefore)
        #expect(Self.current(gameData) == Self.blue80)
    }

    // MARK: Words

    @Test func theWords() {
        #expect(ShopView.surpriseButtonTitle == "Surprise me")
        #expect(ShopView.surpriseHint == "Picks one of your unlocked colours.")
        #expect(ShopView.surpriseNeedsAnotherColour == "Unlock another colour to use Surprise me.")
        #expect(ShopView.surpriseMessage(for: Self.red70) == "Surprise! Your background is now Red 70%.")
        #expect(ShopView.surpriseMessage(for: Self.orange80) == "Surprise! Your background is now Orange 80%.")
        for option in Self.everySwatch {
            let message = ShopView.surpriseMessage(for: option)
            // Never mistaken for the points chip, nor counted as a swatch by the VoiceOver tests.
            #expect(!message.hasPrefix("Points:"))
            #expect(!message.hasSuffix(" percent"))
            #expect(message.split(separator: " ").count <= 8, "\(message)")
        }
    }

    // MARK: How the Shop is built

    static func shopSource() throws -> String {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Maths Quest/ContentView.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        let start = try #require(source.range(of: "struct ShopView: View {"))
        let end = try #require(source.range(of: "\nstruct ", range: start.upperBound..<source.endIndex))
        return String(source[start.lowerBound..<end.lowerBound])
    }

    @Test func itSitsBetweenTheHeadingAndTheSwatches() throws {
        let shop = try Self.shopSource()
        let heading = try #require(shop.range(of: "Text(\"Background Colours\")"))
        let button = try #require(shop.range(of: "            surpriseMe\n", range: heading.upperBound..<shop.endIndex))
        let banner = try #require(shop.range(of: "message.place == .surprise", range: button.upperBound..<shop.endIndex))
        let grid = try #require(shop.range(of: "            swatchGrid\n", range: banner.upperBound..<shop.endIndex))
        #expect(heading.upperBound <= button.lowerBound && banner.upperBound <= grid.lowerBound)
    }

    /// Turned off when there's nothing to pick, with the reason under it, and it only ever chooses with
    /// `selectColour`, never with `purchaseColour` or `spendPoints`.
    @Test func itIsTurnedOffWithAReasonAndOnlyChooses() throws {
        let shop = try Self.shopSource()
        let view = try #require(shop.range(of: "private var surpriseMe: some View {"))
        let viewEnd = try #require(shop.range(of: "\n    }\n", range: view.upperBound..<shop.endIndex))
        let body = shop[view.upperBound..<viewEnd.lowerBound]
        #expect(body.contains("let canSurprise = !Self.surpriseOptions(in: gameData).isEmpty"))
        #expect(body.contains(".disabled(!canSurprise)"))
        #expect(body.contains("if !canSurprise {"))
        #expect(body.contains("Text(Self.surpriseNeedsAnotherColour)"))
        #expect(body.contains(".foregroundStyle(.onBackground)"))
        #expect(!body.contains("lineLimit"))

        let pick = try #require(shop.range(of: "static func surprise<G: RandomNumberGenerator>"))
        let pickEnd = try #require(shop.range(of: "\n    }\n", range: pick.upperBound..<shop.endIndex))
        let picking = shop[pick.upperBound..<pickEnd.lowerBound]
        #expect(picking.contains("gameData.selectColour("))
        #expect(!picking.contains("purchaseColour"))
        #expect(!picking.contains("spendPoints"))
        #expect(!picking.contains("points"))
    }
}
