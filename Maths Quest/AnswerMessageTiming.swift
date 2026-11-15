import SwiftUI

/// When the message after Enter goes away, from user feedback (batch FB-C).
///
/// Each activity shows its message ("Incorrect. Try Again!", "Fill in both boxes.") for a second, or a second and a
/// half, and Enter can't be tapped while it shows, so that one answer can't be marked twice. Two things made Enter
/// seem not to respond:
/// - a corrected answer couldn't be entered until the message about the old one had gone, and
/// - the timer of an earlier message could hide a newer one early.
///
/// So the message about an answer now goes as soon as the answer is changed, and only a message's own timer hides it.
/// Enter is still unavailable while a message shows, and a question that has been answered or skipped still ignores
/// Enter and Return (`QuestionProgress`), so no answer can score twice.
struct AnswerMessageClock: Equatable {
    /// How many messages have been shown.
    private(set) var current = 0

    /// Notes that a message is being shown, and returns its number for its timer.
    mutating func show() -> Int {
        current &+= 1
        return current
    }

    /// Whether `message` is still the latest one shown, so that its timer may hide it.
    func isShowing(_ message: Int) -> Bool {
        message == current
    }
}

extension View {
    /// Hides the message about an answer as soon as the answer is changed, so that Enter, which can't be tapped while
    /// a message shows, works at once for the new answer. The message is left alone while the question is moving on
    /// after a right answer or a Skip.
    func hidesAnswerMessage(whenChanged answer: [String], showMessage: Binding<Bool>,
                            isAdvancing: @escaping () -> Bool) -> some View {
        onChange(of: answer) {
            guard showMessage.wrappedValue, !isAdvancing() else { return }
            withAnimation {
                showMessage.wrappedValue = false
            }
        }
    }
}
