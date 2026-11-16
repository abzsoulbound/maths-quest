//
//  FeedbackBatchFBEUITests.swift
//  Maths QuestUITests
//

import XCTest

/// User feedback, batch FB-E, as a player sees it: the Information screen's message from the creator (FB-06).
///
/// - It says what Feedback is for, asks for nothing about the child, and says there are no replies.
/// - Its privacy line is the one Feedback shows, word for word.
/// - The old words, "please use the feedback section in the sidebar", are gone.
/// - It can be scrolled to its last line, and fits the width of the screen, at the default and the largest text size.
///
/// The words are written out here, not taken from the app. Nothing is sent.
@MainActor
final class FeedbackBatchFBEUITests: MathsQuestUITestCase {

    static let largestText = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

    static let feedbackPurpose = "You can help by using Feedback in the menu. Tell me if something doesn't work, if a question looks wrong, or if you have an idea for the app."
    static let privacyLine = "Please don't write your name, school, address or anything else about you."
    static let noReplies = "I can't reply to messages, because they don't say who sent them. If you're stuck on a question, ask a grown-up or your teacher."

    var creatorMessage: XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Message from the creator.'")).firstMatch
    }

    func testInformationSaysWhatFeedbackIsForAndThatThereAreNoReplies() throws {
        try checkTheMessage(largestText: false)
    }

    func testInformationSaysWhatFeedbackIsForAndThatThereAreNoRepliesAtTheLargestTextSize() throws {
        try checkTheMessage(largestText: true)
    }

    private func checkTheMessage(largestText: Bool) throws {
        continueAfterFailure = true
        if largestText {
            extraLaunchArguments = Self.largestText
        }
        let size = largestText ? ", largest text" : ""
        launchApp()
        openFromSidebar("Information")
        let message = creatorMessage
        XCTAssertTrue(message.waitForExistence(timeout: 10), "Information didn't open.")
        let label = message.label
        attachText("Information\(size): label", label)

        // The words.
        let paragraphs = label.components(separatedBy: "\n\n")
        XCTAssertTrue(paragraphs.count >= 2 && paragraphs[1].hasPrefix("Hi there ") && paragraphs[1].hasSuffix("!"),
                      "The greeting is missing.")
        for line in [Self.feedbackPurpose, Self.privacyLine, Self.noReplies, "Thank you for your support!"] {
            XCTAssertTrue(paragraphs.contains(line), "Information doesn't say: \(line)")
        }
        XCTAssertTrue(label.hasSuffix("Have Fun!\nEwdo Ozdemir"), "The signature is missing.")
        for old in ["feedback section", "sidebar", "constantly striving"] {
            XCTAssertFalse(label.contains(old), "Information still says \"\(old)\".")
        }
        if let purpose = paragraphs.firstIndex(of: Self.feedbackPurpose),
           let privacy = paragraphs.firstIndex(of: Self.privacyLine),
           let replies = paragraphs.firstIndex(of: Self.noReplies) {
            XCTAssertTrue(purpose < privacy && privacy < replies, "The three lines are out of order.")
        }

        // It fits across the screen, starts under the header, and can be scrolled to its last line.
        let window = windowFrame
        let headerBottom = max(pointsLabel.frame.maxY, menuButton.frame.maxY)
        XCTAssertGreaterThanOrEqual(message.frame.minX, window.minX - 0.5, "The message starts off the screen.")
        XCTAssertLessThanOrEqual(message.frame.maxX, window.maxX + 0.5, "The message runs off the screen.")
        XCTAssertGreaterThanOrEqual(message.frame.minY, headerBottom - 0.5, "The message starts under the header.")
        attachScreenshot("Information\(size), top")
        let top = message.frame
        var swipes = 0
        while message.frame.maxY > window.maxY + 0.5 && swipes < 12 && app.scrollViews.firstMatch.exists {
            app.scrollViews.firstMatch.swipeUp()
            swipes += 1
            _ = waitForFrameToSettle(of: message)
        }
        attachScreenshot("Information\(size), end")
        attachText("Information\(size): frames", """
            Header bottom \(headerBottom)
            Message at the top \(top)
            Message at the end \(message.frame)
            Window \(window)
            Swipes to reach the end: \(swipes)
            """)
        XCTAssertLessThanOrEqual(message.frame.maxY, window.maxY + 0.5,
                                 "The end of the message at \(message.frame) can't be scrolled into view.")

        // Feedback shows the same privacy line.
        openFromSidebar("Feedback")
        XCTAssertTrue(text(Self.privacyLine).waitForExistence(timeout: 10),
                      "Feedback's privacy line isn't the one on Information.")
    }
}
