//
//  Stage5AUITestSafetyTests.swift
//  Maths QuestTests
//
//  Stage 5A: the UI tests launch the app with -MathsQuestUITesting. In Debug builds that points
//  Firestore at the local emulator, with its cache in memory, before any screen can use Firestore,
//  so a UI test can't write feedback to the live project, either straight away or from a write
//  queued for a later launch. These tests check those settings, that they match the emulator in
//  firebase/firebase.json, and that the UI tests and the app agree on the launch argument. Nothing
//  here talks to Firestore.
//

import Foundation
import FirebaseFirestore
import Testing
@testable import Maths_Quest

struct Stage5AUITestFirestoreTests {
    @Test func ordinaryLaunchesKeepFirestoresOwnSettings() {
        #expect(UITestFirestore.settings(forLaunchArguments: []) == nil)
        #expect(UITestFirestore.settings(forLaunchArguments: ["Maths Quest", "-AppleLanguages", "(en)"]) == nil)
        #expect(UITestFirestore.settings(forLaunchArguments: ["-MathsQuestUITestingOff"]) == nil)
    }

    @Test func uiTestLaunchesUseTheLocalEmulator() throws {
        let settings = try #require(UITestFirestore.settings(forLaunchArguments: ["Maths Quest", UITestFirestore.launchArgument]))
        #expect(settings.host == "127.0.0.1:8080")
        #expect(settings.host == UITestFirestore.emulatorHost)
        // The emulator doesn't speak TLS.
        #expect(!settings.isSSLEnabled)
    }

    @Test func uiTestLaunchesKeepNothingOnDisk() throws {
        let settings = try #require(UITestFirestore.settings(forLaunchArguments: [UITestFirestore.launchArgument]))
        #expect(settings.cacheSettings is MemoryCacheSettings)
    }
}

// MARK: - Agreement with the emulator config, the UI tests and AppDelegate.swift

private enum Stage5ASource {
    static let projectFolder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static let firebaseConfig = projectFolder.appendingPathComponent("firebase/firebase.json")
    static let uiTestSupport = projectFolder.appendingPathComponent("Maths QuestUITests/MathsQuestUITestSupport.swift")
    static let appDelegate = projectFolder.appendingPathComponent("Maths Quest/AppDelegate.swift")

    static var isAvailable: Bool {
        [firebaseConfig, uiTestSupport, appDelegate].allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func text(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}

@Suite(.enabled(if: Stage5ASource.isAvailable, "The project's source files aren't reachable from this test run"))
struct Stage5AUITestWiringTests {
    @Test func emulatorHostMatchesFirebaseJSON() throws {
        let data = try Data(contentsOf: Stage5ASource.firebaseConfig)
        let config = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let emulators = try #require(config["emulators"] as? [String: Any])
        let firestore = try #require(emulators["firestore"] as? [String: Any])
        let host = try #require(firestore["host"] as? String)
        let port = try #require(firestore["port"] as? Int)
        #expect(UITestFirestore.emulatorHost == "\(host):\(port)")
    }

    @Test func uiTestsLaunchWithTheSameArgument() throws {
        let support = try Stage5ASource.text(Stage5ASource.uiTestSupport)
        #expect(support.contains("static let launchArgument = \"\(UITestFirestore.launchArgument)\""))
        #expect(support.contains("app.launchArguments = [Self.launchArgument"))
    }

    @Test func settingsAreAppliedAtLaunchInDebugBuildsOnly() throws {
        let source = try Stage5ASource.text(Stage5ASource.appDelegate)
        let launch = try #require(source.range(of: "didFinishLaunchingWithOptions"))
        let configure = try #require(source.range(of: "FirebaseApp.configure()", range: launch.upperBound..<source.endIndex))
        let apply = try #require(source.range(of: "Firestore.firestore().settings = settings", range: configure.upperBound..<source.endIndex))
        let returns = try #require(source.range(of: "return true", range: apply.upperBound..<source.endIndex))
        let debugOnly = try #require(source.range(of: "#if DEBUG", range: configure.upperBound..<apply.lowerBound))
        let endDebug = try #require(source.range(of: "#endif", range: apply.upperBound..<returns.lowerBound))
        #expect(debugOnly.lowerBound < endDebug.lowerBound)

        // The switch itself isn't compiled into Release builds.
        let declaration = try #require(source.range(of: "enum UITestFirestore"))
        let before = source[source.startIndex..<declaration.lowerBound]
        let lastIf = try #require(before.range(of: "#if DEBUG", options: .backwards))
        #expect(!before[lastIf.upperBound...].contains("#endif"))
        #expect(source[declaration.upperBound...].contains("#endif"))
    }
}
