//
//  Stage6BSavedProgressTests.swift
//  Maths QuestTests
//
//  Stage 6B: saved progress and the shop. Every test uses its own throwaway UserDefaults suite, so none of them touches
//  the app's real save. The "old save" fixtures are the JSON the first published code wrote: its GameSettings had the
//  seven fields below plus `adsRemoved`, the shop saved "#RRGGBB" colour keys, the starting colour was saved as
//  "0000FF", and `totalQuestionsAnswered` was written but never read back.
//

import Foundation
import Testing
@testable import Maths_Quest

private func makeDefaults(_ name: String = #function) -> UserDefaults {
    // Each suite leaves a plist in the test app's Preferences folder, so earlier runs' files are swept first.
    if let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first {
        let folder = library.appendingPathComponent("Preferences")
        for file in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        where file.hasPrefix("MathsQuestTests.6B.") {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(file))
        }
    }
    let suite = "MathsQuestTests.6B.\(name).\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

/// A player who bought Red 70% and 90%, picked Red 90%, and whose save also holds the old Remove Ads flag.
private let originalFormatSave = """
{"points":120,"totalQuestionsAnswered":0,"sfxvolume":0.3,"username":"Sam","backgroundColourHex":"#FF0000",\
"backgroundOpacity":0.9,"unlockedColours":{"0000FF":[0.8],"#FF0000":[0.7,0.9]},"adsRemoved":true}
"""

@Suite("Stage 6B saved progress", .serialized)
@MainActor
struct Stage6BSavedProgressTests {
    private func store(_ json: String, in defaults: UserDefaults) {
        defaults.set(Data(json.utf8), forKey: gameSettingsKey)
    }

    private func stored(_ defaults: UserDefaults) -> GameSettings? {
        defaults.data(forKey: gameSettingsKey).flatMap { try? JSONDecoder().decode(GameSettings.self, from: $0) }
    }

    @Test func freshInstallStartsWithDefaultsAndSavesThem() {
        let defaults = makeDefaults()
        let game = GameData(defaults: defaults)
        #expect(game.points == 0)
        #expect(game.totalQuestionsAnswered == 0)
        #expect(game.sfxvolume == 0.5)
        #expect(game.username == "")
        #expect(game.backgroundColourHex == "#0000FF")
        #expect(game.backgroundOpacity == 0.8)
        #expect(game.unlockedColours == ["#0000FF": [0.8]])
        #expect(stored(defaults) != nil)
    }

    @Test func originalPublishedSaveKeepsEverything() throws {
        let defaults = makeDefaults()
        store(originalFormatSave, in: defaults)
        let game = GameData(defaults: defaults)
        #expect(game.points == 120)
        #expect(game.sfxvolume == 0.3)
        #expect(game.username == "Sam")
        #expect(game.backgroundColourHex == "#FF0000")
        #expect(game.backgroundOpacity == 0.9)
        #expect(game.unlockedColours["#FF0000"] == [0.7, 0.9])
        #expect(game.unlockedColours["#0000FF"] == [0.8])
        #expect(game.unlockedColours["0000FF"] == nil)
        // The legacy flag is not carried forward.
        let json = try #require(defaults.data(forKey: gameSettingsKey))
        #expect(!String(decoding: json, as: UTF8.self).contains("adsRemoved"))
    }

    @Test func legacyAdsRemovedFlagInTheSaveGrantsNothing() {
        // PurchaseManager reads only its own cache key, never GameSettings, and GameData has no such property.
        let defaults = makeDefaults()
        store(originalFormatSave, in: defaults)
        _ = GameData(defaults: defaults)
        #expect(defaults.object(forKey: "adsRemoved") == nil)
        let mirror = Mirror(reflecting: GameData(defaults: defaults))
        #expect(!mirror.children.contains { $0.label?.contains("adsRemoved") == true })
    }

    @Test func totalQuestionsAnsweredIsRestoredAndSurvivesSaving() {
        let defaults = makeDefaults()
        store("""
        {"points":5,"totalQuestionsAnswered":37,"sfxvolume":0.5,"username":"","backgroundColourHex":"0000FF","backgroundOpacity":0.8,"unlockedColours":{"0000FF":[0.8]}}
        """, in: defaults)
        let game = GameData(defaults: defaults)
        #expect(game.totalQuestionsAnswered == 37)
        game.totalQuestionsAnswered += 1
        game.saveData()
        #expect(GameData(defaults: defaults).totalQuestionsAnswered == 38)
        // Loading again, and saving without a change, keeps it.
        game.loadData()
        game.saveData()
        #expect(GameData(defaults: defaults).totalQuestionsAnswered == 38)
    }

    @Test func startingColourKeyWithoutHashBecomesTheShopsKeyAndIsSelectedAndUnlocked() {
        let defaults = makeDefaults()
        store("""
        {"points":10,"totalQuestionsAnswered":3,"sfxvolume":0.5,"username":"A","backgroundColourHex":"0000FF","backgroundOpacity":0.8,"unlockedColours":{"0000FF":[0.8]}}
        """, in: defaults)
        let game = GameData(defaults: defaults)
        #expect(game.backgroundColourHex == "#0000FF")
        #expect(game.unlockedColours == ["#0000FF": [0.8]])
        #expect(game.isColourSelected("#0000FF", opacity: 0.8))
        #expect(game.isColourUnlocked("#0000FF", opacity: 0.8))
        #expect(game.points == 10)
    }

    @Test func bothSpellingsOfTheSameColourAreMergedWithoutLosingOrDuplicatingAnything() {
        let defaults = makeDefaults()
        // Blue 100% was bought through the shop ("#0000FF") while the starting colour was saved as "0000FF".
        store("""
        {"points":0,"totalQuestionsAnswered":0,"sfxvolume":0.5,"username":"","backgroundColourHex":"#0000FF","backgroundOpacity":1.0,"unlockedColours":{"0000FF":[0.8,0.8],"#0000FF":[1.0,0.8,0.7]}}
        """, in: defaults)
        let game = GameData(defaults: defaults)
        #expect(game.unlockedColours == ["#0000FF": [0.7, 0.8, 1.0]])
        #expect(game.backgroundOpacity == 1.0)
    }

    @Test func playerWithManyUnlockedColoursKeepsAllOfThem() {
        let defaults = makeDefaults()
        let game = GameData(defaults: defaults)
        game.points = 1000
        for colour in colours {
            for option in colour.opacities {
                game.purchaseColour(hex: colour.hexCode, opacity: option.opacity, price: 0)
            }
        }
        let expected = game.unlockedColours.mapValues { $0.sorted() }
        #expect(expected.count == colours.count)
        #expect(GameData(defaults: defaults).unlockedColours == expected)
    }

    @Test func missingKeysGetDefaultsAndKeepTheRest() {
        let defaults = makeDefaults()
        store(##"{"points":77,"username":"Kim"}"##, in: defaults)
        let game = GameData(defaults: defaults)
        #expect(game.points == 77)
        #expect(game.username == "Kim")
        #expect(game.totalQuestionsAnswered == 0)
        #expect(game.sfxvolume == 0.5)
        #expect(game.backgroundColourHex == "#0000FF")
        #expect(game.unlockedColours == ["#0000FF": [0.8]])
    }

    @Test func oneUnreadableValueDoesNotWipeTheOthers() {
        let defaults = makeDefaults()
        store(##"{"points":"lots","totalQuestionsAnswered":9,"sfxvolume":0.2,"username":"Lee","unlockedColours":{"#FF0000":[0.7]},"backgroundColourHex":"#FF0000","backgroundOpacity":0.7}"##, in: defaults)
        let game = GameData(defaults: defaults)
        #expect(game.points == 0)
        #expect(game.totalQuestionsAnswered == 9)
        #expect(game.username == "Lee")
        #expect(game.unlockedColours["#FF0000"] == [0.7])
    }

    @Test func impossibleNumbersAreCorrected() {
        let defaults = makeDefaults()
        store(##"{"points":-40,"totalQuestionsAnswered":-1,"sfxvolume":7,"username":"","backgroundColourHex":"#0000FF","backgroundOpacity":0,"unlockedColours":{}}"##, in: defaults)
        let game = GameData(defaults: defaults)
        #expect(game.points == 0)
        #expect(game.totalQuestionsAnswered == 0)
        #expect(game.sfxvolume == 1)
        #expect(game.backgroundOpacity == 0.8)
    }

    @Test func completelyUnreadableSaveStartsFreshButIsKeptAside() {
        let defaults = makeDefaults()
        let junk = Data("not json at all".utf8)
        defaults.set(junk, forKey: gameSettingsKey)
        let game = GameData(defaults: defaults)
        #expect(game.points == 0)
        #expect(defaults.data(forKey: unreadableGameSettingsKey) == junk)
        // A later save does not replace the copy that was set aside.
        game.points = 3
        game.saveData()
        _ = GameData(defaults: defaults)
        #expect(defaults.data(forKey: unreadableGameSettingsKey) == junk)
    }

    @Test func repeatedLoadsAndSavesChangeNothing() {
        let defaults = makeDefaults()
        store(originalFormatSave, in: defaults)
        let game = GameData(defaults: defaults)
        let first = stored(defaults)
        for _ in 0..<5 {
            game.loadData()
            game.saveData()
            _ = GameData(defaults: defaults)
        }
        #expect(stored(defaults) == first)
        #expect(game.unlockedColours["#FF0000"] == [0.7, 0.9])
        #expect(game.points == 120)
    }

    @Test func purchaseTakesThePriceOnceAndUnlocks() {
        let defaults = makeDefaults()
        let game = GameData(defaults: defaults)
        game.points = 60
        #expect(game.purchaseColour(hex: "#FF0000", opacity: 0.7, price: 25) == .purchased)
        #expect(game.points == 35)
        #expect(game.isColourUnlocked("#FF0000", opacity: 0.7))
        // A second tap before the screen redraws doesn't pay again or add a duplicate.
        #expect(game.purchaseColour(hex: "#FF0000", opacity: 0.7, price: 25) == .alreadyUnlocked)
        #expect(game.points == 35)
        #expect(game.unlockedColours["#FF0000"] == [0.7])
    }

    @Test func purchaseNeedsEnoughPointsAndNeverGoesNegative() {
        let game = GameData(defaults: makeDefaults())
        game.points = 24
        #expect(game.purchaseColour(hex: "#FF0000", opacity: 0.7, price: 25) == .notEnoughPoints)
        #expect(game.points == 24)
        #expect(!game.isColourUnlocked("#FF0000", opacity: 0.7))
        #expect(game.purchaseColour(hex: "#FF0000", opacity: 0.7, price: -5) == .invalidPrice)
        #expect(game.points == 24)
    }

    @Test func purchaseWithExactlyEnoughPointsLeavesZero() {
        let game = GameData(defaults: makeDefaults())
        game.points = 25
        #expect(game.purchaseColour(hex: "#00FF00", opacity: 0.7, price: 25) == .purchased)
        #expect(game.points == 0)
    }

    @Test func lockedColourCannotBeSelectedAndSelectionPersists() {
        let defaults = makeDefaults()
        let game = GameData(defaults: defaults)
        #expect(!game.selectColour(hex: "#FF0000", opacity: 0.7))
        #expect(game.backgroundColourHex == "#0000FF")
        game.points = 25
        game.purchaseColour(hex: "#FF0000", opacity: 0.7, price: 25)
        #expect(game.selectColour(hex: "#FF0000", opacity: 0.7))
        let again = GameData(defaults: defaults)
        #expect(again.isColourSelected("#FF0000", opacity: 0.7))
        #expect(again.points == 0)
        // Only one strength is selected at a time.
        #expect(!again.isColourSelected("#FF0000", opacity: 0.8))
        #expect(!again.isColourSelected("#0000FF", opacity: 0.8))
    }

    @Test func spendingPointsIsAllOrNothing() {
        let defaults = makeDefaults()
        let game = GameData(defaults: defaults)
        game.points = 10
        #expect(!game.spendPoints(11))
        #expect(!game.spendPoints(0))
        #expect(!game.spendPoints(-3))
        #expect(game.points == 10)
        #expect(game.spendPoints(10))
        #expect(game.points == 0)
        #expect(GameData(defaults: defaults).points == 0)
    }

    @Test func pointsEarnedAreSavedAndSeenByTheNextLaunch() {
        let defaults = makeDefaults()
        let game = GameData(defaults: defaults)
        game.points += 1
        game.totalQuestionsAnswered += 1
        game.saveData()
        let relaunched = GameData(defaults: defaults)
        #expect(relaunched.points == 1)
        #expect(relaunched.totalQuestionsAnswered == 1)
    }

    @Test func shopKeysAreAllCanonicalAndTheStartingColourIsFree() throws {
        for colour in colours {
            #expect(GameSettings.canonicalColourHex(colour.hexCode) == colour.hexCode)
        }
        let blue = try #require(colours.first { $0.hexCode == GameSettings.defaultColourHex })
        let eighty = try #require(blue.opacities.first { $0.opacity == GameSettings.defaultOpacity })
        // Free on purpose (owner confirmed): it is the colour every player starts with.
        #expect(eighty.price == 0)
        #expect(GameData(defaults: makeDefaults()).isColourUnlocked(blue.hexCode, opacity: 0.8))
    }
}
