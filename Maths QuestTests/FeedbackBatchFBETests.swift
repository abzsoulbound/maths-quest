//
//  FeedbackBatchFBETests.swift
//  Maths QuestTests
//
//  User feedback, batch FB-E: the Information screen's message from the creator (FB-06, approved 15 November).
//  - It says what Feedback is for: something that doesn't work, a question that looks wrong, or an idea.
//  - It asks children not to write anything about themselves, in the same words as Feedback.
//  - It says there are no replies, why, and who to ask instead.
//  - It keeps the creator's greeting, thanks and signature, and the name the child chose, or "Player".
//

import Foundation
import Testing
@testable import Maths_Quest

struct FBEInformationTests {
    /// The message, written out here in full, so any change to its words has to change this test too.
    static let expected = """
        Message from the creator.

        Hi there Player!

        I've been working hard on Maths Quest, and I'm always trying to make it better.

        You can help by using Feedback in the menu. Tell me if something doesn't work, if a question looks wrong, or if you have an idea for the app.

        Please don't write your name, school, address or anything else about you.

        I can't reply to messages, because they don't say who sent them. If you're stuck on a question, ask a grown-up or your teacher.

        Thank you for your support!

        Have Fun!
        Ewdo Ozdemir
        """

    static var paragraphs: [String] {
        InformationView.message(for: "").components(separatedBy: "\n\n")
    }

    @Test func theMessageHasTheApprovedWords() {
        #expect(InformationView.message(for: "") == Self.expected)
    }

    @Test func itGreetsTheChildByTheNameTheyChoseOrAsPlayer() {
        #expect(InformationView.message(for: "").contains("Hi there Player!"))
        #expect(InformationView.message(for: "Sam").contains("Hi there Sam!"))
        #expect(!InformationView.message(for: "Sam").contains("Player"))
        // Only the greeting changes with the name.
        #expect(InformationView.message(for: "Sam").replacingOccurrences(of: "Hi there Sam!", with: "Hi there Player!")
                == Self.expected)
    }

    @Test func itKeepsTheCreatorsOpeningThanksAndSignature() {
        let message = InformationView.message(for: "")
        #expect(message.hasPrefix("Message from the creator.\n\nHi there "))
        #expect(message.hasSuffix("Thank you for your support!\n\nHave Fun!\nEwdo Ozdemir"))
    }

    @Test func itSaysWhatFeedbackIsFor() {
        let purpose = InformationView.feedbackPurpose
        #expect(Self.paragraphs.contains(purpose))
        // The names a child sees: "Feedback" in the sidebar, which the "Menu" button opens.
        #expect(purpose.contains("Feedback in the menu"))
        for reason in ["something doesn't work", "a question looks wrong", "an idea for the app"] {
            #expect(purpose.contains(reason), "\(reason)")
        }
    }

    /// The same reminder as on Feedback, word for word, so the two screens never disagree.
    @Test func itAsksForNothingAboutTheChildInFeedbacksOwnWords() {
        #expect(Self.paragraphs.contains(FeedbackView.privacyReminder))
        // It is the only paragraph that mentions anything personal, and it says not to write it.
        for paragraph in Self.paragraphs where paragraph != FeedbackView.privacyReminder {
            let words = Set(paragraph.lowercased().split { !$0.isLetter && $0 != "-" }.map(String.init))
            for word in ["name", "school", "address", "email", "e-mail", "phone", "age", "how old", "where you live"] {
                let found = word.contains(" ") ? paragraph.lowercased().contains(word) : words.contains(word)
                #expect(!found, "\(paragraph) mentions \(word)")
            }
        }
    }

    @Test func itSaysThereAreNoRepliesAndWhoToAskInstead() {
        let noReplies = InformationView.noReplies
        #expect(Self.paragraphs.contains(noReplies))
        #expect(noReplies.hasPrefix("I can't reply to messages"))
        #expect(noReplies.contains("ask a grown-up or your teacher"))
        // Nothing promises or hints at an answer.
        let message = InformationView.message(for: "").lowercased()
        for promise in ["i'll reply", "i will reply", "get back to you", "write back", "hear from", "answer you",
                        "contact me", "let me know how to"] {
            #expect(!message.contains(promise), "\(promise)")
        }
        // The privacy reminder comes before the no-reply line, and both after what Feedback is for.
        let purpose = Self.paragraphs.firstIndex(of: InformationView.feedbackPurpose)
        let privacy = Self.paragraphs.firstIndex(of: FeedbackView.privacyReminder)
        let replies = Self.paragraphs.firstIndex(of: noReplies)
        #expect(purpose != nil && privacy != nil && replies != nil)
        if let purpose, let privacy, let replies {
            #expect(purpose < privacy && privacy < replies)
        }
    }

    @Test func theOldWordsAreGone() {
        let message = InformationView.message(for: "")
        for old in ["feedback section", "sidebar", "constantly striving", "finds you well", "suggestions or ideas"] {
            #expect(!message.contains(old), "\(old)")
        }
    }

    /// Short sentences and everyday words, for children in Years 1 to 6.
    @Test func everySentenceIsShort() {
        let sentences = InformationView.message(for: "")
            .components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        #expect(sentences.count >= 10)
        for sentence in sentences {
            #expect(sentence.split(separator: " ").count <= 22, "\(sentence)")
        }
        let words = InformationView.message(for: "").split { !$0.isLetter && $0 != "'" }
        for word in words {
            #expect(word.count <= 9, "\(word)")
        }
    }

    /// The screen shows the message as one piece of text, with nothing that could cut it short.
    @Test func theScreenShowsTheWholeMessage() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Maths Quest/ContentView.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        let start = try #require(source.range(of: "struct InformationView: View {"))
        let end = try #require(source.range(of: "struct RemoveAdsView", range: start.upperBound..<source.endIndex))
        let view = String(source[start.lowerBound..<end.lowerBound])
        #expect(view.contains("message = Self.message(for: gameData.username)"))
        #expect(view.components(separatedBy: "Text(message)").count == 2)
        #expect(!view.contains("lineLimit"))
        #expect(!view.contains("minimumScaleFactor"))
        #expect(!view.contains("truncationMode"))
    }
}
