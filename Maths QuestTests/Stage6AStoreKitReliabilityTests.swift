//
//  Stage6AStoreKitReliabilityTests.swift
//  Maths QuestTests
//
//  Stage 6A: the Remove Ads tests failed now and then for two reasons outside the app's purchase code. Clearing the
//  local StoreKit transactions finishes a moment after SKTestSession says it has (see RemoveAdsPurchaseTests'
//  clearTransactionsAndWait), and the simulator sometimes names the test app after an old, deleted copy of itself,
//  which the local StoreKit test server then refuses to serve (see StoreKitTestHost).
//

import Darwin
import Foundation
import StoreKit
import Testing

/// Keeps the local StoreKit test server able to tell which app is asking.
///
/// When Xcode reinstalls an app whose executable hasn't changed, the simulator installs it as a patch: the new copy's
/// unchanged files are hard links to the old copy's, and the old copy is moved to a "Dead" cache folder
/// (`Library/Caches/com.apple.containermanagerd/Dead`) that stays until the app is deleted.
/// The kernel names a running executable after whichever of its links was looked up last, or after one of the others
/// when that link is deleted, and about half the time the new copy launches still named after the old one. storekitd then sees the test app running from the Dead folder
/// and can't find its app record. The local test server rejects every transaction request (HTTP 400, AMSErrorDomain
/// 301, ASDErrorDomain 500), and every purchase, restore and test-session purchase fails before the app's purchase
/// code is reached.
@MainActor
enum StoreKitTestHost {
    static let recoveryCommand = "xcrun simctl uninstall booted com.abz.maths-mania.Maths-Mania"

    /// The installed copy's executable: the path the simulator launched the app from. Bundle.main and dyld can't be
    /// used, as they ask the kernel for the path after launch and so get the Dead copy's too. Nil if argv[0] isn't an
    /// absolute path to the file that's running.
    nonisolated static let installedExecutablePath: String? = {
        guard let launched = CommandLine.arguments.first, launched.hasPrefix("/"),
              let current = kernelExecutablePath() else { return nil }
        // Look up the kernel's current name first, so the check doesn't rename the executable before it's recorded.
        // Looking up the installed path then gives the executable that name.
        var running = stat(), installed = stat()
        guard stat(current, &running) == 0, stat(launched, &installed) == 0,
              running.st_dev == installed.st_dev, running.st_ino == installed.st_ino else { return nil }
        if current != launched {
            print("StoreKitTestHost: when first checked, the executable was named after \(current); looked up \(launched) again, now \(kernelExecutablePath() ?? "unknown").")
        }
        return launched
    }()

    /// Whether storekitd might still be refusing this app. True until it accepts 15 syncs in a row, and again whenever
    /// the executable is found with another link's name. It starts true even if the name looks right at the first
    /// test: the app's own StoreKit requests at launch can reach storekitd while the executable has a Dead copy's name,
    /// and the name can be put right by something else before the first test looks.
    private(set) static var needsServerCheck = true

    /// The path the kernel, and so storekitd, gives for this process's executable. Reading it doesn't look anything up.
    nonisolated static func kernelExecutablePath() -> String? {
        // libproc.h isn't in the iOS SDK, but the simulator's libSystem has proc_pidpath. -2 is RTLD_DEFAULT, which
        // Swift doesn't import.
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "proc_pidpath") else { return nil }
        typealias ProcPIDPath = @convention(c) (Int32, UnsafeMutableRawPointer?, UInt32) -> Int32
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = unsafeBitCast(symbol, to: ProcPIDPath.self)(getpid(), &buffer, UInt32(buffer.count))
        return length > 0 ? String(cString: buffer) : nil
    }

    /// If the kernel names the executable after another link, looks the installed one up again so the kernel names it
    /// after that instead. Returns the path storekitd will now see.
    @discardableResult
    static func identifyAsInstalledApp() -> String? {
        guard let installed = installedExecutablePath, let current = kernelExecutablePath() else { return nil }
        guard current != installed else { return current }
        var info = stat()
        _ = stat(installed, &info)
        needsServerCheck = true
        let fixed = kernelExecutablePath()
        print("StoreKitTestHost: the executable was named after \(current); looked up \(installed) again, now \(fixed ?? "unknown").")
        return fixed
    }

    /// Once storekitd has seen a Dead copy's name, it goes on refusing some of the app's requests for a few seconds,
    /// even after the name is put right. On a used simulator, three launches named after a Dead copy had refusals mixed
    /// with successes until 2.9 seconds after the name was put right, and none in the 5.6 seconds after that; the
    /// longest run of successes before the last refusal was 7 syncs. So wait for 15 syncs in a row to succeed, about
    /// 2 seconds, before the first test relies on the server, and again after any rename. Gives up after 15 seconds.
    ///
    /// Only call this once StoreKit is known to be using the local configuration, as it syncs with the App Store.
    static func waitUntilServerAcceptsThisApp() async -> Bool {
        guard needsServerCheck else { return true }
        let start = Date()
        var inARow = 0, refusals = 0
        while inARow < 15, Date().timeIntervalSince(start) < 15 {
            do {
                try await AppStore.sync()
                inARow += 1
            } catch {
                inARow = 0
                refusals += 1
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        print(String(format: "StoreKitTestHost: the local StoreKit server refused %d syncs, then %@ after %.1f seconds.",
                     refusals, inARow == 15 ? "accepted 15 in a row" : "still refused them", Date().timeIntervalSince(start)))
        needsServerCheck = inARow < 15
        return !needsServerCheck
    }
}

// A test in RemoveAdsPurchaseTests, so no StoreKit test runs while the executable has the wrong name.
extension RemoveAdsPurchaseTests {
    /// Recreates the simulator's fault with a hard link of our own and checks the suite's guard undoes it.
    @Test func testHostIsNamedAfterTheInstalledAppAgainAfterAnotherLinkIsLookedUp() throws {
        let installed = try #require(StoreKitTestHost.installedExecutablePath)
        #expect(!installed.contains("/com.apple.containermanagerd/Dead/"))
        #expect(StoreKitTestHost.identifyAsInstalledApp() == installed)

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let otherApp = folder.appendingPathComponent("Maths Quest.app")
        try FileManager.default.createDirectory(at: otherApp, withIntermediateDirectories: true)
        let otherLink = otherApp.appendingPathComponent("Maths Quest").path
        defer {
            try? FileManager.default.removeItem(at: folder)
            // Deleting the link leaves the executable named after another of its links, a Dead copy's if there is one
            // (in every run that had one), so put the name right again.
            StoreKitTestHost.identifyAsInstalledApp()
        }
        try #require(link(installed, otherLink) == 0, "Couldn't hard-link the executable: errno \(errno)")

        var info = stat()
        _ = stat(otherLink, &info)
        // This is what storekitd saw in the failing runs, with the Dead folder's copy in place of this one.
        #expect(StoreKitTestHost.kernelExecutablePath() == otherLink)

        #expect(StoreKitTestHost.identifyAsInstalledApp() == installed)
        #expect(StoreKitTestHost.kernelExecutablePath() == installed)
        // So the next test waits until storekitd serves the app again before relying on it.
        #expect(StoreKitTestHost.needsServerCheck)
    }
}
