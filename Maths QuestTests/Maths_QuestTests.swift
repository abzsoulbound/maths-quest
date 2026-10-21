//
//  Maths_ManiaTests.swift
//  Maths ManiaTests
//
//  Created by Abdullah Ozdemir on 29/01/2025.
//

import Foundation
import StoreKit
import StoreKitTest
import Testing
import UIKit
@testable import Maths_Quest

struct Maths_ManiaTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }
}

// Remove Ads regression tests. They run against the local RemoveAds.storekit configuration,
// so no real or sandbox purchases are made.
//
// From the command line the simulator only accepts a StoreKit test session from an app with the
// get-task-allow entitlement, which command-line simulator builds don't get by default. Without it
// StoreKit falls back to the sandbox, so init refuses to continue unless the local product loads.
@MainActor
@Suite(.serialized)
struct RemoveAdsPurchaseTests {
    private static let productID = "removeads"
    private static let cacheKey = "adsRemoved"
    // Only the local RemoveAds.storekit product has this description; App Store Connect's differs.
    private static let localProductDescription = "Removes adverts from Maths Quest."

    private let session: SKTestSession

    init() async throws {
        // If the simulator names this app after a deleted copy of itself, the local StoreKit server refuses every
        // purchase and restore (see StoreKitTestHost). Put the name right, or stop here and say how to fix it.
        let executable = StoreKitTestHost.identifyAsInstalledApp()
        try #require(
            executable == nil || executable == StoreKitTestHost.installedExecutablePath,
            "The simulator names this app after \(executable ?? ""), not its installed copy, so the local StoreKit server would refuse every purchase. Run `\(StoreKitTestHost.recoveryCommand)` and run the tests again."
        )
        session = try SKTestSession(contentsOf: Self.configurationURL())
        // Also clears any simulated errors. Don't clear them with setSimulatedError(nil, forAPI: .purchase):
        // the local server reads that as an unknown failure type and cancels every purchase.
        session.resetToDefaultState()
        session.disableDialogs = true
        session.askToBuyEnabled = false
        try await clearTransactionsAndWait()
        // Safety guard: stop before any purchase or sync if StoreKit isn't using the local configuration.
        let product = try await Product.products(for: [Self.productID]).first
        try #require(
            product?.description == Self.localProductDescription,
            "StoreKit isn't using RemoveAds.storekit, so these tests would reach the sandbox App Store. Stopping."
        )
        let serverAcceptsApp = await StoreKitTestHost.waitUntilServerAcceptsThisApp()
        try #require(
            serverAcceptsApp,
            "The local StoreKit server kept refusing this app for 15 seconds. Run `\(StoreKitTestHost.recoveryCommand)` and run the tests again."
        )
        // The app's own shared instance is also running in the test host, so bring it in line too.
        await PurchaseManager.shared.refreshEntitlements()
        UserDefaults.standard.removeObject(forKey: Self.cacheKey)
    }

    private static func configurationURL() -> URL {
        if let url = Bundle(for: BundleToken.self).url(forResource: "RemoveAds", withExtension: "storekit") {
            return url
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("RemoveAds.storekit")
    }

    // Creates a manager and waits until its launch-time StoreKit checks have settled.
    private func makeManager() async -> PurchaseManager {
        let manager = PurchaseManager()
        await manager.fetchProducts()
        await manager.refreshEntitlements()
        await manager.refreshEntitlements()
        return manager
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    // The local test server takes about a second to add a new purchase to StoreKit's transaction
    // history (storekitd logs that it can't decode the server's purchase response, then picks the
    // purchase up on its next sync). Checks of history or entitlements have to wait for it.
    private func waitForPurchaseInHistory() async throws {
        for _ in 0..<100 {
            if await StoreKit.Transaction.latest(for: Self.productID) != nil { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        Issue.record("The purchase never appeared in StoreKit's transaction history.")
    }

    private func unfinishedRemoveAdsTransactions() async -> Int {
        var count = 0
        for await result in StoreKit.Transaction.unfinished where result.unsafePayloadValue.productID == Self.productID {
            count += 1
        }
        return count
    }

    // The updates listener grants Remove Ads and then finishes the transaction, which is a separate
    // round trip to StoreKit, so adsRemoved can already be true while finish() is still in flight.
    // Checks that a delivered transaction was finished have to wait for StoreKit to stop reporting it.
    // finish() takes about 20ms here, but the local test environment also drops transactions from
    // Transaction.unfinished on its own about a second after delivering them, finished or not, so the
    // wait is capped at half a second; any longer and a listener that never calls finish() would pass.
    private func waitUntilRemoveAdsTransactionsFinished() async throws {
        for _ in 0..<25 where await unfinishedRemoveAdsTransactions() > 0 {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    // clearTransactions() returns before storekitd has deleted anything (2-4ms later on an idle simulator, 17ms in
    // the run that failed), so a StoreKit check made straight after it can still find the old purchase. Wait until
    // StoreKit stops reporting it.
    private func clearTransactionsAndWait() async throws {
        session.clearTransactions()
        for _ in 0..<250 {
            if await !removeAdsVisibleToStoreKit() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        Issue.record("StoreKit still reported a Remove Ads transaction 5 seconds after clearTransactions().")
    }

    private func removeAdsVisibleToStoreKit() async -> Bool {
        if await StoreKit.Transaction.latest(for: Self.productID) != nil { return true }
        for await result in StoreKit.Transaction.currentEntitlements where result.unsafePayloadValue.productID == Self.productID {
            return true
        }
        return false
    }

    private func latestTestTransaction() throws -> SKTestTransaction {
        try #require(session.allTransactions().last { $0.productIdentifier == Self.productID })
    }

    @Test func freshInstallHasNoEntitlementAndLoadsProduct() async throws {
        let manager = await makeManager()
        #expect(manager.adsRemoved == false)
        #expect(manager.product?.id == Self.productID)
        #expect(manager.productLoadFailed == false)
    }

    @Test func purchaseRemovesAdsFinishesTransactionAndSurvivesRelaunch() async throws {
        let manager = await makeManager()
        await manager.buyRemoveAds()

        #expect(manager.adsRemoved)
        #expect(manager.statusMessage == nil)
        #expect(manager.isBusy == false)
        #expect(UserDefaults.standard.bool(forKey: Self.cacheKey))

        try await waitForPurchaseInHistory()
        #expect(await unfinishedRemoveAdsTransactions() == 0)

        // A relaunch is a new manager: it starts from the cache and StoreKit confirms it.
        let relaunched = PurchaseManager()
        #expect(relaunched.adsRemoved)
        #expect(await relaunched.refreshEntitlements())
        #expect(relaunched.adsRemoved)
    }

    @Test func cancelledPurchaseGrantsNothing() async throws {
        let manager = await makeManager()
        try await session.setSimulatedError(.generic(.userCancelled), forAPI: .purchase)
        await manager.buyRemoveAds()

        #expect(manager.adsRemoved == false)
        #expect(manager.statusMessage == "Purchase cancelled. You have not been charged.")
        #expect(UserDefaults.standard.bool(forKey: Self.cacheKey) == false)
    }

    @Test func purchaseErrorsAreReported() async throws {
        let manager = await makeManager()

        try await session.setSimulatedError(.purchase(.purchaseNotAllowed), forAPI: .purchase)
        await manager.buyRemoveAds()
        #expect(manager.adsRemoved == false)
        #expect(manager.statusMessage?.contains("Purchases aren't allowed") == true)

        try await session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .purchase)
        await manager.buyRemoveAds()
        #expect(manager.adsRemoved == false)
        #expect(manager.statusMessage?.contains("Couldn't connect to the App Store") == true)

        try await session.setSimulatedError(.generic(.unknown), forAPI: .purchase)
        await manager.buyRemoveAds()
        #expect(manager.adsRemoved == false)
        #expect(manager.statusMessage?.contains("you have not been charged") == true)
        #expect(manager.isBusy == false)
    }

    @Test func unverifiedPurchaseIsNotGranted() async throws {
        let manager = await makeManager()
        try await session.setSimulatedError(.verification(.invalidSignature), forAPI: .verification)
        await manager.buyRemoveAds()

        #expect(manager.adsRemoved == false)
        #expect(manager.statusMessage?.contains("couldn't be verified") == true)

        try await waitForPurchaseInHistory()
        // Left unfinished so StoreKit offers it again, but still not granted.
        #expect(await unfinishedRemoveAdsTransactions() == 1)
        #expect(await manager.refreshEntitlements() == false)
        #expect(manager.adsRemoved == false)
        #expect(UserDefaults.standard.bool(forKey: Self.cacheKey) == false)
    }

    @Test func askToBuyStaysPendingUntilApproved() async throws {
        session.askToBuyEnabled = true
        let manager = await makeManager()
        await manager.buyRemoveAds()

        #expect(manager.isPending)
        #expect(manager.adsRemoved == false)
        #expect(manager.statusMessage?.contains("waiting for approval") == true)
        // The pending message isn't cleared just by reopening the screen.
        manager.clearStatusMessage()
        #expect(manager.statusMessage != nil)

        let pending = try latestTestTransaction()
        #expect(pending.pendingAskToBuyConfirmation)
        try session.approveAskToBuyTransaction(identifier: pending.identifier)

        try await waitUntil { manager.adsRemoved }
        #expect(manager.adsRemoved)
        #expect(manager.isPending == false)
        #expect(manager.statusMessage == "Your purchase was approved. Ads have been removed.")
    }

    @Test func askToBuyDeclinedGrantsNothing() async throws {
        session.askToBuyEnabled = true
        let manager = await makeManager()
        await manager.buyRemoveAds()
        let pending = try latestTestTransaction()
        try session.declineAskToBuyTransaction(identifier: pending.identifier)

        try await Task.sleep(nanoseconds: 1_000_000_000)
        #expect(manager.adsRemoved == false)
        #expect(await manager.refreshEntitlements() == false)
    }

    @Test func refundRevokesEntitlement() async throws {
        let manager = await makeManager()
        await manager.buyRemoveAds()
        #expect(manager.adsRemoved)

        try session.refundTransaction(identifier: try latestTestTransaction().identifier)

        try await waitUntil { !manager.adsRemoved }
        #expect(manager.adsRemoved == false)
        #expect(UserDefaults.standard.bool(forKey: Self.cacheKey) == false)

        // A relaunch after the refund must not trust the old cache.
        UserDefaults.standard.set(true, forKey: Self.cacheKey)
        let relaunched = await makeManager()
        #expect(relaunched.adsRemoved == false)
    }

    @Test func purchaseFromAnotherDeviceArrivesThroughUpdates() async throws {
        let manager = await makeManager()
        _ = try await session.buyProduct(identifier: Self.productID)

        try await waitUntil { manager.adsRemoved }
        #expect(manager.adsRemoved)
        // Only meaningful once the update has been delivered, which adsRemoved being true confirms.
        try await waitUntilRemoveAdsTransactionsFinished()
        #expect(await unfinishedRemoveAdsTransactions() == 0)
    }

    @Test func restoreFindsExistingPurchase() async throws {
        _ = try await session.buyProduct(identifier: Self.productID)
        try await Task.sleep(nanoseconds: 500_000_000)
        UserDefaults.standard.removeObject(forKey: Self.cacheKey)

        let manager = PurchaseManager()
        await manager.restorePurchases()
        #expect(manager.adsRemoved)
        #expect(manager.statusMessage == "Purchase restored. Ads have been removed.")
    }

    @Test func restoreWithNoPurchaseSaysSo() async throws {
        let manager = await makeManager()
        await manager.restorePurchases()
        #expect(manager.adsRemoved == false)
        #expect(manager.statusMessage == "No Remove Ads purchase was found for this Apple Account.")
    }

    @Test func restoreFailuresAreReported() async throws {
        let manager = await makeManager()

        try await session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .appStoreSync)
        await manager.restorePurchases()
        #expect(manager.adsRemoved == false)
        #expect(manager.statusMessage?.contains("Couldn't connect to the App Store") == true)

        try await session.setSimulatedError(.generic(.userCancelled), forAPI: .appStoreSync)
        await manager.restorePurchases()
        #expect(manager.statusMessage == "Restore cancelled.")
        #expect(manager.isBusy == false)
    }

    @Test func productLoadFailureCanBeRetried() async throws {
        try await session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .loadProducts)
        let manager = PurchaseManager()
        await manager.fetchProducts()
        #expect(manager.product == nil)
        #expect(manager.productLoadFailed)

        await manager.buyRemoveAds()
        #expect(manager.adsRemoved == false)
        #expect(manager.statusMessage?.contains("couldn't be loaded") == true)

        try await session.setSimulatedError(nil, forAPI: .loadProducts)
        await manager.fetchProducts()
        #expect(manager.product?.id == Self.productID)
        #expect(manager.productLoadFailed == false)
    }

    @Test func untrustedCachedFlagIsOverruledByStoreKit() async throws {
        UserDefaults.standard.set(true, forKey: Self.cacheKey)
        let manager = PurchaseManager()
        // Provisional value until StoreKit answers.
        #expect(manager.adsRemoved)

        await manager.refreshEntitlements()
        await manager.refreshEntitlements()
        #expect(manager.adsRemoved == false)
        #expect(UserDefaults.standard.bool(forKey: Self.cacheKey) == false)
    }

    @Test func purchasersSkipWithoutAnAd() async throws {
        _ = try await session.buyProduct(identifier: Self.productID)
        try await waitUntil { PurchaseManager.shared.adsRemoved }
        #expect(PurchaseManager.shared.adsRemoved)

        var skipped = false
        AdManager.shared.showRewardedInterstitialAd(from: UIViewController()) {
            skipped = true
        }
        #expect(skipped)

        try await clearTransactionsAndWait()
        await PurchaseManager.shared.refreshEntitlements()
        #expect(PurchaseManager.shared.adsRemoved == false)
    }
}

private final class BundleToken {}
