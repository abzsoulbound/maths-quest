//
//  PurchaseAndFeedbackSafetyUITests.swift
//  Maths QuestUITests
//

import XCTest

/// The UI tests reach Remove Ads and Feedback but can't buy anything or send feedback.
final class PurchaseAndFeedbackSafetyUITests: MathsQuestUITestCase {

    @MainActor
    func testRemoveAdsShowsTheLocalStoreKitProductWithoutBuyingIt() throws {
        launchApp()
        openFromSidebar("Remove Ads")
        XCTAssertFalse(text("Ads removed! Thank you.").waitForExistence(timeout: 3),
                       "Remove Ads is already bought in this simulator. Erase it, or delete the app, to clear the local StoreKit purchase.")

        let buy = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Buy - '")).firstMatch
        XCTAssertTrue(buy.waitForExistence(timeout: 20), "The Remove Ads product didn't load.")
        // Maths QuestTests/RemoveAds.storekit prices the product at 1.99 in a GBR storefront. xcodebuild
        // doesn't give the UI tests the scheme's StoreKit configuration: the simulator keeps using the
        // one the unit tests' SKTestSession installed, and before that it shows the sandbox's price.
        // Either way Buy is refused, so nothing can be bought.
        XCTAssertEqual(buy.label, "Buy - £1.99",
                       "Remove Ads isn't coming from RemoveAds.storekit. Run Maths QuestTests on this simulator first.")
        let restore = button("Restore Purchases")
        XCTAssertTrue(restore.exists)
        attachScreenshot("Remove Ads")

        // tap(_:) refuses both, so no test can start a purchase or a restore.
        XCTAssertNotNil(Self.refusalReason(forLabel: buy.label, onFeedbackScreen: false))
        XCTAssertNotNil(Self.refusalReason(forLabel: restore.label, onFeedbackScreen: false))
    }

    @MainActor
    func testFeedbackOpensButIsNeverSent() throws {
        launchApp()
        openFromSidebar("Feedback")
        XCTAssertTrue(feedbackPrivacyReminder.waitForExistence(timeout: 10), "Feedback didn't open.")
        let send = button("Enter")
        XCTAssertTrue(send.exists)
        attachScreenshot("Feedback")

        // tap(_:) refuses Feedback's Enter but still allows the activities' "Enter ".
        XCTAssertNotNil(Self.refusalReason(forLabel: send.label, onFeedbackScreen: true))
        XCTAssertNil(Self.refusalReason(forLabel: "Enter ", onFeedbackScreen: false))
    }
}
