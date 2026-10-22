//
//  Stage7BSaveCompatibilityTests.swift
//  Maths QuestTests
//
//  Stage 7B: saves move both ways between the published 1.3 and this version. `Version13` below is 1.3's own save code
//  (17bbbaa) copied as it was: its GameSettings is synthesized Codable, so every key, `adsRemoved` included, is required,
//  and a save it can't decode loads as an empty game that its next save writes over. The fixtures are the exact bytes
//  found in the simulator: one written by 1.3 itself after real play, one written by an earlier build of this version
//  (Stage 7A, no `adsRemoved`), and one 1.3 wrote after reading this version's save. Every test uses its own throwaway
//  UserDefaults suite.
//

import CryptoKit
import Foundation
import Testing
@testable import Maths_Quest

private func makeDefaults(_ name: String = #function) -> UserDefaults {
    // Each suite leaves a plist in the test app's Preferences folder, so earlier runs' files are swept first.
    if let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first {
        let folder = library.appendingPathComponent("Preferences")
        for file in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        where file.hasPrefix("MathsQuestTests.7B.") {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(file))
        }
    }
    let suite = "MathsQuestTests.7B.\(name).\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

/// 1.3's save code, as published. Only the storage is passed in instead of being UserDefaults.standard.
private enum Version13 {
    struct GameSettings: Codable, Equatable {
        var points: Int
        var totalQuestionsAnswered: Int
        var sfxvolume: Double
        var username: String
        var backgroundColourHex: String
        var backgroundOpacity: Double
        var unlockedColours: [String: [Double]]
        var adsRemoved: Bool = false
    }

    static func saveSettings(_ settings: GameSettings, to defaults: UserDefaults) {
        let encoder = JSONEncoder()
        do {
            let encoded = try encoder.encode(settings)
            defaults.set(encoded, forKey: "GameSettings")
        } catch {
        }
    }

    static func loadSettings(from defaults: UserDefaults) -> GameSettings {
        if let savedSettings = defaults.data(forKey: "GameSettings") {
            let decoder = JSONDecoder()
            do {
                return try decoder.decode(GameSettings.self, from: savedSettings)
            } catch {
            }
        }
        return GameSettings(
            points: 0,
            totalQuestionsAnswered: 0,
            sfxvolume: 0.5,
            username: "",
            backgroundColourHex: "0000FF",
            backgroundOpacity: 0.8,
            unlockedColours: ["0000FF": [0.8]],
            adsRemoved: false
        )
    }

    /// 1.3's GameData: launching loads everything except totalQuestionsAnswered, then saves only if the starting colour
    /// isn't unlocked under "0000FF". Any later save writes every field.
    final class GameData {
        var points = 0
        var totalQuestionsAnswered = 0
        var sfxvolume = 0.5
        var username = ""
        var backgroundColourHex = "0000FF"
        var backgroundOpacity = 0.8
        var unlockedColours: [String: [Double]] = [:]
        var adsRemoved = false
        private let defaults: UserDefaults

        init(defaults: UserDefaults) {
            self.defaults = defaults
            loadData()
            if unlockedColours["0000FF"]?.contains(0.8) != true {
                unlockedColours["0000FF"] = (unlockedColours["0000FF"] ?? []) + [0.8]
                saveData()
            }
        }

        func saveData() {
            Version13.saveSettings(GameSettings(
                points: points,
                totalQuestionsAnswered: totalQuestionsAnswered,
                sfxvolume: sfxvolume,
                username: username,
                backgroundColourHex: backgroundColourHex,
                backgroundOpacity: backgroundOpacity,
                unlockedColours: unlockedColours,
                adsRemoved: adsRemoved
            ), to: defaults)
        }

        func loadData() {
            let settings = Version13.loadSettings(from: defaults)
            points = settings.points
            sfxvolume = settings.sfxvolume
            username = settings.username
            backgroundColourHex = settings.backgroundColourHex
            backgroundOpacity = settings.backgroundOpacity
            unlockedColours = settings.unlockedColours
            adsRemoved = settings.adsRemoved
        }

        /// What every 1.3 question screen does on a correct answer.
        func answerCorrectly() {
            points += 1
            totalQuestionsAnswered += 1
            saveData()
        }
    }

    static func canRead(_ defaults: UserDefaults) -> Bool {
        defaults.data(forKey: "GameSettings").map { (try? JSONDecoder().decode(GameSettings.self, from: $0)) != nil } ?? false
    }
}

/// Written by the published 1.3 on a simulator after 7 correct answers, buying Red 70% and Green 70%, selecting Red 70%,
/// spending 5 points and turning the volume down. Byte for byte as it was saved (SHA-256 below).
private let saveWrittenBy13 = ##"{"username":"Ava Test","unlockedColours":{"#00FF00":[0.7],"0000FF":[0.8],"#FF0000":[0.7]},"totalQuestionsAnswered":7,"points":40,"adsRemoved":false,"backgroundOpacity":0.7,"backgroundColourHex":"#FF0000","sfxvolume":0.14710944890975952}"##
private let saveWrittenBy13SHA256 = "711cb84f5fb17e837640f2804ee7df473a4a063d0afe83da2e4f700d743b818f"

/// Written by the Stage 7A build after upgrading that save and playing on. It has no `adsRemoved`, so 1.3 can't read it.
private let saveWrittenBy7A = ##"{"totalQuestionsAnswered":20,"username":"Ava Upgraded","points":3,"backgroundColourHex":"#00FF00","sfxvolume":0.6584377884864807,"backgroundOpacity":0.8,"unlockedColours":{"#FF0000":[0.7],"#0000FF":[0.8],"#00FF00":[0.7,0.8]}}"##

/// Written by 1.3 when it launched over this version's save: it added its own "0000FF" key and reset the question count.
private let saveRewrittenBy13 = ##"{"backgroundColourHex":"#00FF00","backgroundOpacity":0.8,"points":3,"sfxvolume":0.6583554148674011,"totalQuestionsAnswered":0,"unlockedColours":{"#0000FF":[0.8],"#00FF00":[0.7,0.8],"0000FF":[0.8],"#FF0000":[0.7]},"username":"Ava Upgraded","adsRemoved":false}"##

@Suite("Stage 7B save compatibility", .serialized)
@MainActor
struct Stage7BSaveCompatibilityTests {
    private func store(_ json: String, in defaults: UserDefaults) {
        defaults.set(Data(json.utf8), forKey: gameSettingsKey)
    }

    private func savedJSON(_ defaults: UserDefaults) throws -> [String: Any] {
        let data = try #require(defaults.data(forKey: gameSettingsKey))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func savedBy13Reading(_ defaults: UserDefaults) throws -> Version13.GameSettings {
        let data = try #require(defaults.data(forKey: gameSettingsKey))
        return try JSONDecoder().decode(Version13.GameSettings.self, from: data)
    }

    // MARK: 1.3 → this version

    @Test func fixtureIsTheExactBytes13Wrote() {
        let digest = SHA256.hash(data: Data(saveWrittenBy13.utf8)).map { String(format: "%02x", $0) }.joined()
        #expect(digest == saveWrittenBy13SHA256)
        #expect(gameSettingsKey == "GameSettings")
    }

    @Test func upgradeKeepsEverything13Saved() {
        let defaults = makeDefaults()
        store(saveWrittenBy13, in: defaults)
        let game = GameData(defaults: defaults)
        #expect(game.points == 40)
        #expect(game.totalQuestionsAnswered == 7)
        #expect(game.username == "Ava Test")
        #expect(game.sfxvolume == 0.14710944890975952)
        #expect(game.isColourSelected("#FF0000", opacity: 0.7))
        #expect(game.unlockedColours == ["#0000FF": [0.8], "#00FF00": [0.7], "#FF0000": [0.7]])
    }

    @Test func upgradedSaveIsWrittenOnceAndThenStable() throws {
        let defaults = makeDefaults()
        store(saveWrittenBy13, in: defaults)
        _ = GameData(defaults: defaults)
        let first = try #require(defaults.data(forKey: gameSettingsKey))
        #expect(first != Data(saveWrittenBy13.utf8))       // the "0000FF" key was tidied
        for _ in 0..<5 {
            _ = GameData(defaults: defaults)
            #expect(defaults.data(forKey: gameSettingsKey) == first)
        }
    }

    // MARK: This version → 1.3

    @Test func everySaveThisVersionWritesHasExactly13sKeys() throws {
        let defaults = makeDefaults()
        _ = GameData(defaults: defaults)
        let keys = Set(try savedJSON(defaults).keys)
        #expect(keys == ["points", "totalQuestionsAnswered", "sfxvolume", "username", "backgroundColourHex",
                         "backgroundOpacity", "unlockedColours", "adsRemoved"])
        #expect(try savedJSON(defaults)["adsRemoved"] as? Bool == false)
    }

    @Test func freshInstallIsReadableBy13() throws {
        let defaults = makeDefaults()
        _ = GameData(defaults: defaults)
        #expect(savedSettingsReadableBy13(in: defaults))
        let seen = try savedBy13Reading(defaults)
        #expect(seen.points == 0)
        #expect(seen.backgroundColourHex == "#0000FF")
    }

    @Test func thirteenReadsProgressMadeAfterUpgrading() throws {
        let defaults = makeDefaults()
        store(saveWrittenBy13, in: defaults)
        let game = GameData(defaults: defaults)
        #expect(Version13.canRead(defaults))
        // The same play as on the simulator: 10 correct answers, buy Green 80% with exactly 50, select it, rename,
        // change the volume, 3 more answers.
        for _ in 0..<10 { game.points += 1; game.totalQuestionsAnswered += 1; game.saveData() }
        #expect(Version13.canRead(defaults))
        #expect(game.purchaseColour(hex: "#00FF00", opacity: 0.8, price: 50) == .purchased)
        #expect(Version13.canRead(defaults))
        #expect(game.selectColour(hex: "#00FF00", opacity: 0.8))
        game.username = "Ava Upgraded"
        game.saveData()
        game.sfxvolume = 0.66
        game.saveData()
        for _ in 0..<3 { game.points += 1; game.totalQuestionsAnswered += 1; game.saveData() }
        #expect(game.spendPoints(1))

        let seen = try savedBy13Reading(defaults)
        #expect(seen.points == 2)
        #expect(seen.totalQuestionsAnswered == 20)
        #expect(seen.username == "Ava Upgraded")
        #expect(seen.sfxvolume == 0.66)
        #expect(seen.backgroundColourHex == "#00FF00")
        #expect(seen.backgroundOpacity == 0.8)
        #expect(seen.unlockedColours["#00FF00"] == [0.7, 0.8])
        #expect(seen.unlockedColours["#FF0000"] == [0.7])
        #expect(seen.adsRemoved == false)
    }

    @Test func goingBackTo13KeepsProgressThroughPlay() {
        let defaults = makeDefaults()
        store(saveWrittenBy13, in: defaults)
        let game = GameData(defaults: defaults)
        #expect(game.purchaseColour(hex: "#0000FF", opacity: 1.0, price: 40) == .purchased)
        #expect(game.selectColour(hex: "#0000FF", opacity: 1.0))
        game.username = "Ava Upgraded"
        game.saveData()

        // 1.3 launches over it, then the player answers a question, which saves every field.
        let old = Version13.GameData(defaults: defaults)
        #expect(old.points == 0)
        #expect(old.username == "Ava Upgraded")
        #expect(old.backgroundColourHex == "#0000FF")
        #expect(old.backgroundOpacity == 1.0)
        old.answerCorrectly()
        let reread = Version13.GameData(defaults: defaults)
        #expect(reread.points == 1)
        #expect(reread.username == "Ava Upgraded")
        #expect(reread.unlockedColours["#0000FF"] == [0.8, 1.0])
        #expect(reread.unlockedColours["#FF0000"] == [0.7])
        #expect(reread.sfxvolume == 0.14710944890975952)
    }

    @Test func roundTripThrough13AndBackLosesNothing13Keeps() {
        let defaults = makeDefaults()
        store(saveWrittenBy13, in: defaults)
        let game = GameData(defaults: defaults)
        game.totalQuestionsAnswered += 5
        game.points += 5
        game.saveData()

        let old = Version13.GameData(defaults: defaults)
        old.answerCorrectly()

        let back = GameData(defaults: defaults)
        #expect(back.points == 46)
        // 1.3 never loads this count, so its own save starts it again. Nothing this version can do about that.
        #expect(back.totalQuestionsAnswered == 1)
        #expect(back.username == "Ava Test")
        #expect(back.sfxvolume == 0.14710944890975952)
        #expect(back.isColourSelected("#FF0000", opacity: 0.7))
        #expect(back.unlockedColours == ["#0000FF": [0.8], "#00FF00": [0.7], "#FF0000": [0.7]])
        #expect(savedSettingsReadableBy13(in: defaults))
    }

    @Test func the13RewriteOfThisVersionsSaveIsMergedBack() throws {
        // The exact bytes 1.3 wrote after launching over this version's save: both "0000FF" and "#0000FF".
        let defaults = makeDefaults()
        store(saveRewrittenBy13, in: defaults)
        let game = GameData(defaults: defaults)
        #expect(game.points == 3)
        #expect(game.username == "Ava Upgraded")
        #expect(game.sfxvolume == 0.6583554148674011)
        #expect(game.unlockedColours == ["#0000FF": [0.8], "#00FF00": [0.7, 0.8], "#FF0000": [0.7]])
        #expect(game.isColourSelected("#00FF00", opacity: 0.8))
        let keys = try #require(try savedJSON(defaults)["unlockedColours"] as? [String: Any]).keys
        #expect(!keys.contains("0000FF"))
        #expect(Version13.canRead(defaults))
    }

    @Test func repeatedUpgradesAndDowngradesStayConsistent() throws {
        let defaults = makeDefaults()
        store(saveWrittenBy13, in: defaults)
        for round in 1...4 {
            let game = GameData(defaults: defaults)
            #expect(game.points == 40 + 2 * (round - 1))
            game.points += 1
            game.saveData()
            let old = Version13.GameData(defaults: defaults)
            #expect(old.points == 40 + 2 * (round - 1) + 1)
            old.answerCorrectly()
        }
        let last = GameData(defaults: defaults)
        #expect(last.points == 48)
        #expect(last.username == "Ava Test")
        #expect(last.unlockedColours == ["#0000FF": [0.8], "#00FF00": [0.7], "#FF0000": [0.7]])
        #expect(try savedJSON(defaults)["adsRemoved"] as? Bool == false)
    }

    // MARK: Saves from the earlier build of this version (no adsRemoved)

    @Test func saveWithoutAdsRemovedIsRepairedAtLaunch() throws {
        let defaults = makeDefaults()
        store(saveWrittenBy7A, in: defaults)
        #expect(!Version13.canRead(defaults))
        #expect(!savedSettingsReadableBy13(in: defaults))
        let game = GameData(defaults: defaults)
        #expect(game.points == 3)
        #expect(game.totalQuestionsAnswered == 20)
        #expect(game.username == "Ava Upgraded")
        #expect(Version13.canRead(defaults))
        let seen = try savedBy13Reading(defaults)
        #expect(seen.points == 3)
        #expect(seen.username == "Ava Upgraded")
        #expect(seen.sfxvolume == 0.6584377884864807)
        #expect(seen.unlockedColours["#00FF00"] == [0.7, 0.8])
        #expect(seen.adsRemoved == false)
    }

    @Test func savedSettingsReadableBy13MatchesThe13Decoder() {
        let cases: [String?] = [
            nil,
            saveWrittenBy13,
            saveWrittenBy7A,
            saveRewrittenBy13,
            ##"{"points":77,"username":"Kim"}"##,
            ##"{"points":"lots","totalQuestionsAnswered":9,"sfxvolume":0.2,"username":"Lee","unlockedColours":{},"backgroundColourHex":"#FF0000","backgroundOpacity":0.7,"adsRemoved":false}"##,
            "not json at all",
        ]
        for json in cases {
            let defaults = makeDefaults()
            if let json { store(json, in: defaults) }
            #expect(savedSettingsReadableBy13(in: defaults) == Version13.canRead(defaults))
        }
    }

    // MARK: Damaged saves

    @Test func missingOrUnreadableFieldsAreRewrittenSo13CanReadThem() throws {
        let defaults = makeDefaults()
        store(##"{"points":"lots","totalQuestionsAnswered":9,"username":"Lee","unlockedColours":{"#FF0000":[0.7]},"backgroundColourHex":"#FF0000","backgroundOpacity":0.7}"##, in: defaults)
        let game = GameData(defaults: defaults)
        #expect(game.points == 0)
        #expect(game.totalQuestionsAnswered == 9)
        #expect(game.username == "Lee")
        let seen = try savedBy13Reading(defaults)
        #expect(seen.totalQuestionsAnswered == 9)
        #expect(seen.username == "Lee")
        #expect(seen.sfxvolume == 0.5)
        #expect(seen.unlockedColours["#FF0000"] == [0.7])
        // Nothing was unreadable as a whole, so nothing was set aside.
        #expect(defaults.data(forKey: unreadableGameSettingsKey) == nil)
    }

    @Test func unreadableSaveIsStillSetAsideAndTheFreshOneIs13Readable() {
        let defaults = makeDefaults()
        let junk = Data("not json at all".utf8)
        defaults.set(junk, forKey: gameSettingsKey)
        let game = GameData(defaults: defaults)
        #expect(game.points == 0)
        #expect(defaults.data(forKey: unreadableGameSettingsKey) == junk)
        #expect(Version13.canRead(defaults))
    }

    // MARK: Remove Ads

    @Test func legacyAdsRemovedTrueGrantsNothingAndIsWrittenFalse() throws {
        // Only 1.3's "noads1937" cheat ever wrote true. It must not become an entitlement.
        let defaults = makeDefaults()
        store(##"{"points":5,"totalQuestionsAnswered":1,"sfxvolume":0.5,"username":"","backgroundColourHex":"0000FF","backgroundOpacity":0.8,"unlockedColours":{"0000FF":[0.8]},"adsRemoved":true}"##, in: defaults)
        let game = GameData(defaults: defaults)
        #expect(game.points == 5)
        #expect(try savedJSON(defaults)["adsRemoved"] as? Bool == false)
        // PurchaseManager's cache lives under "adsRemoved" in the same store; the save must never create it.
        #expect(defaults.object(forKey: "adsRemoved") == nil)
        let mirror = Mirror(reflecting: game)
        #expect(!mirror.children.contains { $0.label?.lowercased().contains("ads") == true })
    }

    @Test func paidPlayersCachedPurchaseIsNeverTouchedBySaving() throws {
        // A 1.3 player who bought Remove Ads: StoreKit's cache is true, and 1.3's save still said false.
        let defaults = makeDefaults()
        defaults.set(true, forKey: "adsRemoved")
        store(saveWrittenBy13, in: defaults)
        let game = GameData(defaults: defaults)
        game.points += 1
        game.saveData()
        #expect(game.purchaseColour(hex: "#00FF00", opacity: 0.8, price: 50) == .notEnoughPoints)
        #expect(game.spendPoints(1))
        Version13.GameData(defaults: defaults).answerCorrectly()
        _ = GameData(defaults: defaults)
        #expect(defaults.bool(forKey: "adsRemoved") == true)
        #expect(try savedJSON(defaults)["adsRemoved"] as? Bool == false)
    }

    @Test func freePlayersHaveNoCachedPurchaseAfterUpgrading() {
        let defaults = makeDefaults()
        store(saveWrittenBy13, in: defaults)
        let game = GameData(defaults: defaults)
        game.saveData()
        _ = GameData(defaults: defaults)
        #expect(defaults.object(forKey: "adsRemoved") == nil)
    }

    // MARK: No double counting

    @Test func repairingAtLaunchNeverChangesPointsOrCounts() {
        let defaults = makeDefaults()
        store(saveWrittenBy7A, in: defaults)
        for _ in 0..<3 {
            let game = GameData(defaults: defaults)
            #expect(game.points == 3)
            #expect(game.totalQuestionsAnswered == 20)
        }
        let game = GameData(defaults: defaults)
        #expect(game.purchaseColour(hex: "#00FF00", opacity: 0.8, price: 50) == .alreadyUnlocked)
        #expect(game.points == 3)
        #expect(GameData(defaults: defaults).points == 3)
    }
}
