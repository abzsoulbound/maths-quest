//
//  Stage4AScoringIntegrityTests.swift
//  Maths QuestTests
//
//  Stage 4A: scoring integrity for Year 1 Addition and Subtraction, Year 3 Fractions and Time,
//  Year 4 Geometry and Year 5 Percentages, and a check of the source that all 18 activities use
//  QuestionProgress the same way. The timeline tests run the real QuestionProgress against a
//  virtual main queue, so the delayed resets, the feedback timers that re-enable Enter and the Skip
//  rewards fire in the order they would on a device. Geometry and Time are made and marked by the
//  app's own Year4GeometryQuestion and Year3TimeQuestion. Everything here is pure state, so it runs
//  without the simulator UI, StoreKit or Firebase.
//

import Foundation
import Testing
@testable import Maths_Quest

// MARK: - QuestionProgress, rule by rule

struct Stage4AQuestionProgressRuleTests {
    private func progressShowingSkip() -> QuestionProgress {
        var progress = QuestionProgress()
        for _ in 0..<QuestionProgress.wrongAttemptsBeforeSkip {
            progress.recordWrongAttempt()
        }
        return progress
    }

    /// Rules 1 and 2: a question scores once, and every later submission is ignored.
    @Test func aQuestionScoresOnceAndCannotBeResubmitted() {
        var progress = QuestionProgress()
        let first = progress.recordSubmission(isCorrect: true)
        #expect(first == .correct)
        for _ in 0..<5 {
            let right = progress.recordSubmission(isCorrect: true)
            let wrong = progress.recordSubmission(isCorrect: false)
            let scored = progress.recordCorrectAnswer()
            #expect(right == .ignored)
            #expect(wrong == .ignored)
            #expect(!scored)
        }
        #expect(progress.wrongAttempts == 0)
        #expect(progress.isAdvancing)
    }

    /// Rule 4: once answered, Skip disappears and a Skip reward is turned down.
    @Test func anAnsweredQuestionCannotBeSkipped() {
        var progress = progressShowingSkip()
        #expect(progress.showSkipButton)
        let scored = progress.recordCorrectAnswer()
        #expect(scored)
        #expect(!progress.showSkipButton)
        let skipped = progress.recordSkip()
        #expect(!skipped)
    }

    /// Rule 5: Skip works once, and a skipped question can't then score.
    @Test func skipWorksOnceAndBlocksScoring() {
        var progress = progressShowingSkip()
        let firstSkip = progress.recordSkip()
        let secondSkip = progress.recordSkip()
        let scored = progress.recordCorrectAnswer()
        let submitted = progress.recordSubmission(isCorrect: true)
        #expect(firstSkip)
        #expect(!secondSkip)
        #expect(!scored)
        #expect(submitted == .ignored)
    }

    /// Rules 6, 7 and 8: wrong answers never score, every one counts, and Skip appears after two.
    @Test func wrongAnswersCountAndUnlockSkipAfterTwo() {
        #expect(QuestionProgress.wrongAttemptsBeforeSkip == 2)
        var progress = QuestionProgress()
        for attempt in 1...5 {
            let submission = progress.recordSubmission(isCorrect: false)
            #expect(submission == .incorrect)
            #expect(progress.wrongAttempts == attempt)
            #expect(progress.showSkipButton == (attempt >= 2))
            #expect(!progress.isAdvancing)
        }
        let submission = progress.recordSubmission(isCorrect: true)
        #expect(submission == .correct)
    }

    /// Wrong answers pressed after a correct one don't count against the next question.
    @Test func wrongAnswersWhileMovingOnAreIgnored() {
        var progress = QuestionProgress()
        progress.recordWrongAttempt()
        let scored = progress.recordCorrectAnswer()
        progress.recordWrongAttempt()
        progress.recordWrongAttempt()
        #expect(scored)
        #expect(progress.wrongAttempts == 1)
        #expect(!progress.showSkipButton)
    }

    /// Rules 9 and 11: the next question starts clean, and the last question's Skip doesn't carry over.
    @Test func resetStartsCleanAndDoesNotReopenTheLastQuestion() {
        var skipped = progressShowingSkip()
        let skip = skipped.recordSkip()
        skipped.reset()
        let lateSkip = skipped.recordSkip()
        #expect(skip)
        #expect(skipped == QuestionProgress())
        #expect(!lateSkip, "a late Skip reward from the last question")

        var answered = progressShowingSkip()
        let firstScore = answered.recordCorrectAnswer()
        answered.reset()
        #expect(firstScore)
        #expect(answered == QuestionProgress())
        #expect(!answered.showSkipButton)
        let nextScore = answered.recordCorrectAnswer()
        let repeatScore = answered.recordCorrectAnswer()
        #expect(nextScore)
        #expect(!repeatScore)
    }
}

// MARK: - A virtual main queue

/// Stands in for DispatchQueue.main.asyncAfter. Nothing runs until the test moves the clock on, then
/// work runs in deadline order, and in the order it was scheduled when deadlines match.
private final class Stage4AMainQueue {
    private struct Work {
        let deadline: Int
        let order: Int
        let run: () -> Void
    }

    /// Milliseconds since the activity opened.
    private(set) var now = 0
    private var pending = [Work]()
    private var scheduled = 0

    func asyncAfter(milliseconds: Int, _ run: @escaping () -> Void) {
        pending.append(Work(deadline: now + milliseconds, order: scheduled, run: run))
        scheduled += 1
    }

    func advance(by milliseconds: Int) {
        let target = now + milliseconds
        while let next = pending
            .filter({ $0.deadline <= target })
            .min(by: { ($0.deadline, $0.order) < ($1.deadline, $1.order) }) {
            pending.removeAll { $0.order == next.order }
            now = next.deadline
            next.run()
        }
        now = target
    }
}

// MARK: - The six activities

/// Everything a child can type or set on the six screens. Each activity reads only its own fields.
private struct Stage4AAnswer: Equatable {
    var text = ""
    var unit = ""
    var numerator = ""
    var denominator = ""
    var hours = ""
    var minutes = ""
    var clockHour = 0
    var clockMinute = 0
}

private enum Stage4AMark: Equatable {
    case correct
    case incorrect(message: String = "Incorrect. Try Again!")
    /// Nothing typed, or the clock still at 12:00. Since Stage 6E every screen asks for an answer and nothing counts.
    case unanswered
}

private struct Stage4AQuestion {
    let rightAnswer: Stage4AAnswer
    /// Answers the activity marks wrong, each of which counts as a wrong attempt. A blank answer isn't one.
    let wrongAnswers: [Stage4AAnswer]
    let mark: (Stage4AAnswer) -> Stage4AMark

    /// Marked as the views do it: a blank answer is asked for, and anything else must be
    /// `TypedAnswer.wholeNumber(answerString) == answer`.
    static func wholeNumber(_ answer: Int) -> Stage4AQuestion {
        Stage4AQuestion(
            rightAnswer: Stage4AAnswer(text: "\(answer)"),
            wrongAnswers: [Stage4AAnswer(text: "\(answer + 1)")],
            mark: { typed in
                guard !TypedAnswer.isBlank(typed.text) else { return .unanswered }
                return TypedAnswer.wholeNumber(typed.text) == answer ? .correct : .incorrect()
            }
        )
    }
}

enum Stage4AActivity: String, CaseIterable {
    case year1Addition, year1Subtraction, year3Fractions, year3Time, year4Geometry, year5Percentages

    /// How long showFeedback() shows a message for.
    var feedbackMilliseconds: Int { self == .year5Percentages ? 1_500 : 1_000 }
    /// How long after a correct answer resetQuestion() runs.
    var correctResetMilliseconds: Int { self == .year5Percentages ? 1_500 : 1_000 }
    /// Geometry doesn't add to totalQuestionsAnswered.
    var countsQuestionsAnswered: Bool { self != .year4Geometry }
    /// Fractions marks through recordSubmission(isCorrect:), the others through recordCorrectAnswer().
    /// All six ignore Enter while the question moves on, then ask for a blank answer rather than mark it.
    var usesRecordSubmission: Bool { self == .year3Fractions }
    /// Geometry calls resetQuestion() from .onAppear, and its resetQuestion() also hides the message.
    var isGeometry: Bool { self == .year4Geometry }

    /// A question as the view makes it, marked as the view marks it.
    fileprivate func question(using generator: inout SeededGenerator) -> Stage4AQuestion {
        switch self {
        case .year1Addition:
            let first = Int.random(in: 0..<10, using: &generator)
            let second = Int.random(in: 0..<10, using: &generator)
            return .wholeNumber(first + second)

        case .year1Subtraction:
            var first = Int.random(in: 0..<10, using: &generator)
            var second = Int.random(in: 0..<10, using: &generator)
            // numberadjustment() puts the larger number first.
            if second > first {
                swap(&first, &second)
            }
            return .wholeNumber(first - second)

        case .year3Fractions:
            // Year3FractionsView's own lists.
            let fractions = [[1, 2], [1, 3], [1, 4], [2, 3], [3, 4]]
            let simplified = ["1/2", "1/2", "1/2", "1/3", "2/3"]
            let index = Int.random(in: 0..<5, using: &generator)
            let multiplier = fractions[index][1] * Int.random(in: 2...5, using: &generator)
            guard Int.random(in: 1...2, using: &generator) == 1 else {
                return .wholeNumber(fractions[index][0] * multiplier / fractions[index][1])
            }
            let parts = simplified[index].split(separator: "/").map(String.init)
            return Stage4AQuestion(
                rightAnswer: Stage4AAnswer(numerator: parts[0], denominator: parts[1]),
                wrongAnswers: [Stage4AAnswer(numerator: parts[1], denominator: parts[0])],
                mark: { answer in
                    // Asked for only when both boxes are empty; one empty box is marked, and is wrong.
                    if TypedAnswer.isBlank(answer.numerator) && TypedAnswer.isBlank(answer.denominator) {
                        return .unanswered
                    }
                    return answer.numerator + "/" + answer.denominator == simplified[index] ? .correct : .incorrect()
                }
            )

        case .year3Time:
            return timeQuestion(using: &generator)

        case .year4Geometry:
            let question = Year4GeometryQuestion.random(using: &generator)
            let rightAnswer: Stage4AAnswer
            var wrongAnswers = [Stage4AAnswer(text: "0", unit: question.correctUnit ?? "")]
            if let unit = question.correctUnit {
                let value = question.question == 1 ? question.perimeter : question.area!
                rightAnswer = Stage4AAnswer(text: "\(value)", unit: unit)
                wrongAnswers.append(Stage4AAnswer(text: "\(value)", unit: ""))
            } else {
                rightAnswer = Stage4AAnswer(text: question.angleType)
            }
            return Stage4AQuestion(rightAnswer: rightAnswer, wrongAnswers: wrongAnswers) { answer in
                switch question.evaluate(answer: answer.text, unit: answer.unit) {
                case .correct:
                    return .correct
                case .wrongUnit:
                    return .incorrect(message: "Correct number, but wrong unit!")
                case .incorrect:
                    return .incorrect()
                case .unanswered:
                    return .unanswered
                }
            }

        case .year5Percentages:
            // generateValidQuestion(): a multiple of 5 per cent of a number that gives a whole answer.
            let percentage = Int.random(in: 1...20, using: &generator) * 5
            let step = 100 / greatestCommonDivisor(100, percentage)
            let number = Array(stride(from: step, through: 200, by: step)).randomElement(using: &generator)!
            return .wholeNumber(percentage * number / 100)
        }
    }

    /// Year3TimeQuestion itself, so the model asks the questions the view asks and marks them the same way.
    private func timeQuestion(using generator: inout SeededGenerator) -> Stage4AQuestion {
        let question = Year3TimeQuestion.random(using: &generator)
        let (hours, minutes) = question.answer
        let rightAnswer: Stage4AAnswer
        let wrongAnswer: Stage4AAnswer
        switch question.kind {
        case .toMinutes:
            // Answered in the minutes box alone.
            rightAnswer = Stage4AAnswer(minutes: "\(minutes)")
            wrongAnswer = Stage4AAnswer(minutes: "\(minutes + 1)")
        case .toHoursAndMinutes, .timeAfter:
            rightAnswer = Stage4AAnswer(hours: "\(hours)", minutes: "\(minutes)")
            wrongAnswer = Stage4AAnswer(hours: "\((hours + 1) % 24)", minutes: "\(minutes)")
        case .readClock:
            // Read in 12-hour time, so the hour is 1 to 12.
            rightAnswer = Stage4AAnswer(hours: "\(hours)", minutes: "\(minutes)")
            wrongAnswer = Stage4AAnswer(hours: "\(hours % 12 + 1)", minutes: "\(minutes)")
        case .setClock:
            // The hands start at 12:00, which is never asked for. The wrong answer is an hour out, never 12:00.
            rightAnswer = Stage4AAnswer(clockHour: hours % 12, clockMinute: minutes)
            wrongAnswer = Stage4AAnswer(clockHour: hours % 12 == 11 ? 10 : hours % 12 + 1, clockMinute: minutes)
        }
        return Stage4AQuestion(rightAnswer: rightAnswer, wrongAnswers: [wrongAnswer]) { answer in
            switch question.evaluate(hours: answer.hours, minutes: answer.minutes,
                                     clockHour: answer.clockHour, clockMinute: answer.clockMinute) {
            case .correct:
                return .correct
            case .incorrect:
                return .incorrect()
            case .unanswered:
                return .unanswered
            }
        }
    }

    private func greatestCommonDivisor(_ a: Int, _ b: Int) -> Int {
        b == 0 ? a : greatestCommonDivisor(b, a % b)
    }
}

/// How the six screens kept score: before Stage 4A, with their own wrongAttempts and
/// showSkipButton and no guards, or now, with QuestionProgress.
enum Stage4AWiring {
    case beforeStage4A
    case questionProgress
}

/// One of the six screens, driven the way its view drives it. Enter is .disabled(showMessage),
/// but Return (TextField.onSubmit) never is. Every message hides itself after
/// feedbackMilliseconds, even if a later message is showing by then. A correct answer schedules
/// resetQuestion() after correctResetMilliseconds, and a Skip reward calls GameData.skipQuestion,
/// which schedules it a second later. With Remove Ads the reward arrives as soon as Skip is tapped,
/// otherwise when the ad finishes. The first onAppear is left out, so every screen starts on
/// question 1.
private final class Stage4AScreen {
    let activity: Stage4AActivity
    let wiring: Stage4AWiring
    private let queue = Stage4AMainQueue()
    private var generator: SeededGenerator
    private(set) var question: Stage4AQuestion
    /// 1 for the first question, plus one each time resetQuestion() runs.
    private(set) var questionNumber = 1
    private(set) var progress = QuestionProgress()
    /// The state the six views kept before Stage 4A.
    private(set) var oldWrongAttempts = 0
    private(set) var oldShowSkipButton = false
    var answer = Stage4AAnswer()
    private(set) var message = ""
    private(set) var showMessage = false
    private(set) var points = 0
    private(set) var totalQuestionsAnswered = 0
    /// Points scored on each question, by question number.
    private(set) var pointsByQuestion = [Int: Int]()
    private(set) var scheduledResets = 0
    private(set) var completedResets = 0
    /// Scheduled resets that ran after the question that scheduled them had already gone.
    private(set) var staleResets = 0
    var adsRemoved = true
    /// The reward closure of a Skip ad on screen. AdManager won't show a second ad over it.
    private var adReward: (() -> Void)?

    init(_ activity: Stage4AActivity, wiring: Stage4AWiring = .questionProgress, seed: UInt64) {
        self.activity = activity
        self.wiring = wiring
        var generator = SeededGenerator(seed: seed)
        question = activity.question(using: &generator)
        self.generator = generator
    }

    var wrongAttempts: Int {
        wiring == .questionProgress ? progress.wrongAttempts : oldWrongAttempts
    }

    var isSkipShowing: Bool {
        wiring == .questionProgress ? progress.showSkipButton : oldShowSkipButton
    }

    var pendingResets: Int { scheduledResets - completedResets }
    var isAdShowing: Bool { adReward != nil }

    func wait(_ milliseconds: Int) {
        queue.advance(by: milliseconds)
    }

    /// Button("Enter"), which is .disabled(showMessage).
    func tapEnter() {
        guard !showMessage else { return }
        checkAnswer()
    }

    /// Two taps on Enter that both land before SwiftUI redraws it as disabled.
    func doubleTapEnter() {
        guard !showMessage else { return }
        checkAnswer()
        checkAnswer()
    }

    /// TextField.onSubmit, which is never disabled.
    func pressReturn() {
        checkAnswer()
    }

    /// Skip, which is only on screen while isSkipShowing.
    func tapSkip() {
        guard isSkipShowing else { return }
        tapSkipBeforeRedraw()
    }

    /// A tap on Skip from a frame drawn before the button disappeared.
    func tapSkipBeforeRedraw() {
        guard !isAdShowing else { return }
        let reward = { [unowned self] in self.earnSkipReward() }
        if adsRemoved {
            reward()
        } else {
            adReward = reward
        }
    }

    /// The Skip ad pays out its reward and closes, and the screen may appear again behind it.
    func finishAd(appearsAgain: Bool = true) {
        guard let reward = adReward else { return }
        adReward = nil
        reward()
        if appearsAgain {
            appear()
        }
    }

    /// Geometry's background .onAppear.
    func appear() {
        guard activity.isGeometry else { return }
        if wiring == .questionProgress {
            guard !progress.isAdvancing else { return }
        }
        resetQuestion()
    }

    /// The closure passed to AdManager.showRewardedInterstitialAd.
    private func earnSkipReward() {
        if wiring == .questionProgress {
            guard progress.recordSkip() else { return }
        }
        // GameData.skipQuestion(resetQuestion:)
        scheduleReset(after: 1_000)
    }

    private func checkAnswer() {
        let mark = question.mark(answer)
        switch wiring {
        case .beforeStage4A:
            if mark == .correct {
                scoreCorrectAnswer()
            } else {
                // A blank answer was marked wrong then, like any other.
                showIncorrect(mark == .unanswered ? .incorrect() : mark)
                oldWrongAttempts += 1
                if oldWrongAttempts >= 2 {
                    oldShowSkipButton = true
                }
            }

        case .questionProgress where activity.usesRecordSubmission:
            guard !progress.isAdvancing else { return }
            guard mark != .unanswered else {
                askForAnAnswer()
                return
            }
            switch progress.recordSubmission(isCorrect: mark == .correct) {
            case .ignored:
                return
            case .correct:
                scoreCorrectAnswer()
            case .incorrect:
                showIncorrect(mark)
            }

        case .questionProgress:
            guard !progress.isAdvancing else { return }
            guard mark != .unanswered else {
                askForAnAnswer()
                return
            }
            if mark == .correct {
                guard progress.recordCorrectAnswer() else { return }
                scoreCorrectAnswer()
            } else {
                showIncorrect(mark)
                progress.recordWrongAttempt()
            }
        }
    }

    private func scoreCorrectAnswer() {
        message = "Correct!"
        showFeedback()
        points += 1
        pointsByQuestion[questionNumber, default: 0] += 1
        if activity.countsQuestionsAnswered {
            totalQuestionsAnswered += 1
        }
        scheduleReset(after: activity.correctResetMilliseconds)
    }

    private func showIncorrect(_ mark: Stage4AMark) {
        if case let .incorrect(text) = mark {
            message = text
        }
        showFeedback()
    }

    /// "Please enter an answer!": no points, no wrong attempt, and the question stays.
    private func askForAnAnswer() {
        message = "Please enter an answer!"
        showFeedback()
    }

    private func showFeedback() {
        showMessage = true
        queue.asyncAfter(milliseconds: activity.feedbackMilliseconds) { [unowned self] in
            self.showMessage = false
        }
    }

    private func scheduleReset(after milliseconds: Int) {
        scheduledResets += 1
        let scheduledOn = questionNumber
        queue.asyncAfter(milliseconds: milliseconds) { [unowned self] in
            self.completedResets += 1
            if self.questionNumber != scheduledOn {
                self.staleResets += 1
            }
            self.resetQuestion()
        }
    }

    private func resetQuestion() {
        question = activity.question(using: &generator)
        questionNumber += 1
        answer = Stage4AAnswer()
        message = ""
        if activity.isGeometry {
            showMessage = false
        }
        progress.reset()
        oldWrongAttempts = 0
        oldShowSkipButton = false
    }
}

// MARK: - The six activities on a timeline

struct Stage4ATimelineTests {
    /// Enough time for every timer to fire.
    private let drain = 10_000

    private func answerWrongTwice(_ screen: Stage4AScreen) {
        for _ in 0..<QuestionProgress.wrongAttemptsBeforeSkip {
            screen.answer = screen.question.wrongAnswers[0]
            screen.tapEnter()
            screen.wait(screen.activity.feedbackMilliseconds)
        }
    }

    /// The tests below rely on these answers being marked right and wrong, and a blank one being neither.
    @Test(arguments: Stage4AActivity.allCases)
    func everyQuestionHasARightAnswerAndWrongAnswers(activity: Stage4AActivity) {
        var generator = SeededGenerator(seed: 0x4A_0001)
        var wrongUnits = 0
        for _ in 0..<3_000 {
            let question = activity.question(using: &generator)
            #expect(question.mark(question.rightAnswer) == .correct, "\(question.rightAnswer)")
            #expect(question.mark(Stage4AAnswer()) == .unanswered)
            #expect(!question.wrongAnswers.isEmpty)
            for wrong in question.wrongAnswers {
                #expect(question.mark(wrong) != .correct, "\(wrong)")
                #expect(question.mark(wrong) != .unanswered, "\(wrong)")
                if question.mark(wrong) == .incorrect(message: "Correct number, but wrong unit!") {
                    wrongUnits += 1
                }
            }
        }
        #expect((wrongUnits > 0) == activity.isGeometry)
    }

    /// A correct answer scores exactly +1, and the next question starts clean once its timer fires.
    @Test(arguments: Stage4AActivity.allCases)
    func correctAnswerScoresOnceAndMovesOnOnce(activity: Stage4AActivity) {
        let screen = Stage4AScreen(activity, seed: 0x4A_1001)
        screen.answer = screen.question.rightAnswer
        screen.tapEnter()
        #expect(screen.points == 1)
        #expect(screen.totalQuestionsAnswered == (activity.countsQuestionsAnswered ? 1 : 0))
        #expect(screen.message == "Correct!")
        #expect(screen.progress.isAdvancing)

        screen.wait(activity.correctResetMilliseconds - 1)
        #expect(screen.questionNumber == 1)
        screen.wait(1)
        #expect(screen.questionNumber == 2)
        #expect(screen.progress == QuestionProgress())
        #expect(screen.answer == Stage4AAnswer())
        #expect(screen.message == "")
        #expect(!screen.isSkipShowing)

        screen.wait(drain)
        #expect(screen.questionNumber == 2)
        #expect(screen.points == 1)
        #expect(screen.staleResets == 0)
    }

    /// Return, Enter and double taps on Enter all through the transition.
    @Test(arguments: Stage4AActivity.allCases)
    func repeatedEnterAndReturnDuringTheTransitionScoreOnce(activity: Stage4AActivity) {
        let screen = Stage4AScreen(activity, seed: 0x4A_1002)
        screen.answer = screen.question.rightAnswer
        screen.doubleTapEnter()
        for _ in 0..<(activity.correctResetMilliseconds / 100 - 1) {
            screen.pressReturn()
            screen.tapEnter()
            screen.doubleTapEnter()
            screen.wait(100)
        }
        #expect(screen.points == 1)
        #expect(screen.totalQuestionsAnswered == (activity.countsQuestionsAnswered ? 1 : 0))
        #expect(screen.pendingResets == 1)
        #expect(screen.questionNumber == 1)
        #expect(screen.message == "Correct!")

        screen.wait(drain)
        #expect(screen.questionNumber == 2)
        #expect(screen.points == 1)
    }

    /// A wrong answer's timer hides "Correct!" early and re-enables Enter before the next question.
    @Test(arguments: Stage4AActivity.allCases)
    func earlierFeedbackTimerCannotReopenScoring(activity: Stage4AActivity) {
        let screen = Stage4AScreen(activity, seed: 0x4A_1003)
        screen.answer = screen.question.wrongAnswers[0]
        screen.tapEnter()
        screen.wait(activity.feedbackMilliseconds - 100)

        screen.answer = screen.question.rightAnswer
        screen.tapEnter()
        #expect(screen.points == 0, "Enter is still disabled")
        screen.pressReturn()
        #expect(screen.points == 1)

        screen.wait(100)
        #expect(!screen.showMessage)
        #expect(screen.questionNumber == 1)
        screen.tapEnter()
        screen.pressReturn()
        #expect(screen.points == 1)
        #expect(screen.message == "Correct!")
        #expect(screen.wrongAttempts == 1)

        screen.wait(drain)
        #expect(screen.questionNumber == 2)
        #expect(screen.points == 1)
        #expect(screen.progress == QuestionProgress())
    }

    /// A wrong answer pressed during the transition doesn't replace "Correct!" or count as a wrong attempt.
    @Test(arguments: Stage4AActivity.allCases)
    func wrongAnswerDuringTheTransitionIsIgnored(activity: Stage4AActivity) {
        let screen = Stage4AScreen(activity, seed: 0x4A_1004)
        screen.answer = screen.question.rightAnswer
        screen.pressReturn()
        for wrong in screen.question.wrongAnswers {
            screen.answer = wrong
            screen.pressReturn()
        }
        #expect(screen.message == "Correct!")
        #expect(screen.wrongAttempts == 0)
        #expect(!screen.isSkipShowing)
        #expect(screen.points == 1)
    }

    /// Wrong answers never score, each one counts as before, and Skip appears after the second.
    @Test(arguments: Stage4AActivity.allCases)
    func wrongAnswersNeverScoreAndUnlockSkipAfterTwo(activity: Stage4AActivity) {
        let screen = Stage4AScreen(activity, seed: 0x4A_1005)
        let wrongAnswers = screen.question.wrongAnswers
        for attempt in 1...4 {
            screen.answer = wrongAnswers[(attempt - 1) % wrongAnswers.count]
            screen.tapEnter()
            #expect(screen.points == 0)
            #expect(screen.totalQuestionsAnswered == 0)
            #expect(screen.wrongAttempts == attempt)
            #expect(screen.isSkipShowing == (attempt >= 2))
            #expect(screen.message != "Correct!")
            #expect(screen.message != "")
            screen.wait(activity.feedbackMilliseconds)
        }
        screen.wait(drain)
        #expect(screen.questionNumber == 1)
        #expect(screen.pendingResets == 0)
    }

    /// Enter or Return with nothing typed, or with the clock still at 12:00, asks for an answer: no points, no
    /// wrong attempt and no Skip, and the question stays to be answered.
    @Test(arguments: Stage4AActivity.allCases)
    func blankAnswersAreAskedForAndNeverCount(activity: Stage4AActivity) {
        let screen = Stage4AScreen(activity, seed: 0x4A_1012)
        for _ in 0..<3 {
            screen.tapEnter()
            #expect(screen.message == "Please enter an answer!")
            screen.pressReturn()
            screen.wait(activity.feedbackMilliseconds)
        }
        #expect(screen.points == 0)
        #expect(screen.totalQuestionsAnswered == 0)
        #expect(screen.wrongAttempts == 0)
        #expect(!screen.isSkipShowing)
        screen.wait(drain)
        #expect(screen.questionNumber == 1)
        #expect(screen.pendingResets == 0)

        screen.answer = screen.question.wrongAnswers[0]
        screen.tapEnter()
        #expect(screen.wrongAttempts == 1)
        screen.wait(activity.feedbackMilliseconds)
        screen.answer = screen.question.rightAnswer
        screen.tapEnter()
        #expect(screen.points == 1)

        // Emptied while the question moves on, the answer is ignored like any other.
        screen.answer = Stage4AAnswer()
        screen.pressReturn()
        #expect(screen.message == "Correct!")
        screen.wait(drain)
        #expect(screen.questionNumber == 2)
        #expect(screen.points == 1)
    }

    /// Skip gives no points and moves on once, however many times it's tapped.
    @Test(arguments: Stage4AActivity.allCases, [true, false])
    func skipGivesNoPointsAndMovesOnOnce(activity: Stage4AActivity, adsRemoved: Bool) {
        let screen = Stage4AScreen(activity, seed: 0x4A_1006)
        screen.adsRemoved = adsRemoved
        answerWrongTwice(screen)
        #expect(screen.isSkipShowing)

        screen.tapSkip()
        if !adsRemoved {
            #expect(screen.isAdShowing)
            #expect(screen.pendingResets == 0)
            screen.tapSkip()
            screen.finishAd()
        }
        #expect(!screen.isSkipShowing)
        #expect(screen.pendingResets == 1)

        screen.tapSkip()
        screen.tapSkipBeforeRedraw()
        screen.tapSkipBeforeRedraw()
        screen.finishAd()
        #expect(screen.pendingResets == 1)
        #expect(screen.points == 0)
        #expect(screen.totalQuestionsAnswered == 0)

        screen.wait(drain)
        #expect(screen.questionNumber == 2)
        #expect(screen.progress == QuestionProgress())
        #expect(screen.answer == Stage4AAnswer())
        #expect(screen.points == 0)
        #expect(screen.staleResets == 0)
    }

    /// Answered with Skip still on screen: Skip goes, and a tap that lands anyway is turned down.
    @Test(arguments: Stage4AActivity.allCases, [true, false])
    func correctAnswerThenSkipMovesOnOnce(activity: Stage4AActivity, adsRemoved: Bool) {
        let screen = Stage4AScreen(activity, seed: 0x4A_1007)
        screen.adsRemoved = adsRemoved
        answerWrongTwice(screen)
        #expect(screen.isSkipShowing)

        screen.answer = screen.question.rightAnswer
        screen.pressReturn()
        #expect(screen.points == 1)
        #expect(!screen.isSkipShowing)

        screen.tapSkip()
        screen.tapSkipBeforeRedraw()
        screen.finishAd()
        #expect(screen.pendingResets == 1)

        screen.wait(drain)
        #expect(screen.questionNumber == 2)
        #expect(screen.points == 1)
        #expect(screen.staleResets == 0)
    }

    /// A skipped question can't then be answered for points.
    @Test(arguments: Stage4AActivity.allCases)
    func skippedQuestionCannotScore(activity: Stage4AActivity) {
        let screen = Stage4AScreen(activity, seed: 0x4A_1008)
        answerWrongTwice(screen)
        screen.tapSkip()
        screen.answer = screen.question.rightAnswer
        screen.tapEnter()
        screen.pressReturn()
        #expect(screen.points == 0)
        #expect(screen.pendingResets == 1)

        screen.wait(drain)
        #expect(screen.questionNumber == 2)
        #expect(screen.points == 0)
    }

    /// A Skip ad whose reward only arrives after the question has been answered and replaced.
    @Test(arguments: Stage4AActivity.allCases)
    func lateSkipRewardCannotSkipTheNextQuestion(activity: Stage4AActivity) {
        let screen = Stage4AScreen(activity, seed: 0x4A_1009)
        screen.adsRemoved = false
        answerWrongTwice(screen)
        screen.tapSkip()
        #expect(screen.isAdShowing)

        screen.answer = screen.question.rightAnswer
        screen.pressReturn()
        #expect(screen.points == 1)
        screen.wait(activity.correctResetMilliseconds)
        #expect(screen.questionNumber == 2)

        // Left out: Geometry appearing again behind the ad, which gives a new question as it always has.
        screen.finishAd(appearsAgain: false)
        #expect(screen.pendingResets == 0)
        screen.wait(drain)
        #expect(screen.questionNumber == 2)
        #expect(screen.progress == QuestionProgress())
    }

    /// Presses straight after the next question appears are marked against it, and only it.
    @Test(arguments: Stage4AActivity.allCases)
    func repeatedInputBeforeAndAfterTheResetScoresEachQuestionOnce(activity: Stage4AActivity) {
        let screen = Stage4AScreen(activity, seed: 0x4A_1010)
        screen.answer = screen.question.rightAnswer
        screen.pressReturn()
        screen.pressReturn()
        screen.wait(activity.correctResetMilliseconds - 1)
        screen.pressReturn()
        screen.wait(1)
        #expect(screen.questionNumber == 2)
        #expect(screen.points == 1)

        screen.answer = screen.question.wrongAnswers[0]
        screen.pressReturn()
        screen.pressReturn()
        #expect(screen.points == 1)
        #expect(screen.wrongAttempts == 2, "Return isn't disabled, so each press is a wrong attempt, as before")
        #expect(screen.isSkipShowing)

        screen.answer = screen.question.rightAnswer
        screen.pressReturn()
        screen.pressReturn()
        screen.tapSkip()
        #expect(screen.points == 2)
        #expect(screen.pendingResets == 1)

        screen.wait(drain)
        #expect(screen.questionNumber == 3)
        #expect(screen.pointsByQuestion == [1: 1, 2: 1])
        #expect(screen.staleResets == 0)
    }

    /// Geometry's .onAppear can run while a question is moving on, for example when the Skip ad closes.
    @Test func geometryAppearingAgainDuringTheTransitionDoesNotMoveOnTwice() {
        let screen = Stage4AScreen(.year4Geometry, seed: 0x4A_1011)
        screen.answer = screen.question.rightAnswer
        screen.tapEnter()
        screen.wait(500)
        screen.appear()
        #expect(screen.questionNumber == 1)
        screen.wait(drain)
        #expect(screen.questionNumber == 2)
        #expect(screen.points == 1)

        screen.adsRemoved = false
        answerWrongTwice(screen)
        screen.tapSkip()
        screen.finishAd(appearsAgain: true)
        #expect(screen.questionNumber == 2)
        screen.wait(drain)
        #expect(screen.questionNumber == 3)
        #expect(screen.staleResets == 0)

        // Appearing on a question that isn't moving on still gives a new question, as before.
        screen.appear()
        #expect(screen.questionNumber == 4)
        #expect(screen.progress == QuestionProgress())
        #expect(screen.points == 1)
    }

    /// Long random runs of typing, Enter, Return, Skip, ads and waiting. Each question scores or is
    /// skipped at most once, only a right answer scores, Skip needs two wrong attempts, and no more
    /// than one next question is ever waiting.
    @Test(arguments: Stage4AActivity.allCases, [true, false])
    func randomSessionsScoreAndMoveOnAtMostOncePerQuestion(activity: Stage4AActivity, adsRemoved: Bool) {
        var generator = SeededGenerator(seed: 0x4A_9030)
        let screen = Stage4AScreen(activity, seed: 0x4A_9031)
        screen.adsRemoved = adsRemoved
        var mistakes = [String]()
        var skips = 0

        for step in 0..<10_000 {
            let points = screen.points
            let scheduled = screen.scheduledResets
            let wrong = screen.wrongAttempts
            let wasAdvancing = screen.progress.isAdvancing
            let wasRight = screen.question.mark(screen.answer) == .correct
            let action = Int.random(in: 0..<10, using: &generator)

            switch action {
            case 0, 1:
                screen.answer = screen.question.rightAnswer
            case 2, 3:
                screen.answer = screen.question.wrongAnswers.randomElement(using: &generator)!
            case 4:
                screen.tapEnter()
            case 5:
                screen.pressReturn()
            case 6:
                screen.tapSkip()
            case 7:
                screen.tapSkipBeforeRedraw()
            case 8:
                screen.finishAd(appearsAgain: Bool.random(using: &generator))
            default:
                screen.wait(Int.random(in: 1...800, using: &generator))
            }

            if screen.points != points {
                if screen.points != points + 1 {
                    mistakes.append("step \(step): \(screen.points - points) points at once")
                }
                if action != 4 && action != 5 {
                    mistakes.append("step \(step): scored without Enter or Return")
                }
                if !wasRight {
                    mistakes.append("step \(step): scored a wrong answer")
                }
                if wasAdvancing {
                    mistakes.append("step \(step): scored a question that was already moving on")
                }
            } else if screen.scheduledResets > scheduled {
                skips += 1
                if wrong < QuestionProgress.wrongAttemptsBeforeSkip {
                    mistakes.append("step \(step): skipped after \(wrong) wrong attempts")
                }
                if wasAdvancing {
                    mistakes.append("step \(step): skipped a question that was already moving on")
                }
            }
            if screen.pendingResets > 1 {
                mistakes.append("step \(step): \(screen.pendingResets) next questions waiting")
            }
            if screen.staleResets > 0 || screen.pointsByQuestion.values.contains(where: { $0 > 1 }) {
                mistakes.append("step \(step): a question moved on or scored twice")
                break
            }
        }

        #expect(mistakes.isEmpty, "\(mistakes.prefix(5))")
        #expect(screen.points > 50)
        #expect(skips > 10)
        #expect(screen.totalQuestionsAnswered == (activity.countsQuestionsAnswered ? screen.points : 0))
    }
}

// MARK: - The same screens as they were before Stage 4A

/// Shows each defect on the wiring the six screens had before Stage 4A, so the tests above fail
/// for the reasons the fix addresses rather than for some quirk of the model.
struct Stage4ABeforeFixTests {
    private let drain = 10_000

    private func oldScreen(_ activity: Stage4AActivity) -> Stage4AScreen {
        Stage4AScreen(activity, wiring: .beforeStage4A, seed: 0x4A_2001)
    }

    private func answerWrongTwice(_ screen: Stage4AScreen) {
        for _ in 0..<2 {
            screen.answer = screen.question.wrongAnswers[0]
            screen.tapEnter()
            screen.wait(screen.activity.feedbackMilliseconds)
        }
    }

    /// Return during the transition scored the same question again and moved on twice.
    @Test(arguments: Stage4AActivity.allCases)
    func returnDuringTheTransitionScoredAgain(activity: Stage4AActivity) {
        let screen = oldScreen(activity)
        screen.answer = screen.question.rightAnswer
        screen.tapEnter()
        screen.pressReturn()
        #expect(screen.points == 2)
        #expect(screen.pendingResets == 2)
        screen.wait(drain)
        #expect(screen.questionNumber == 3)
        #expect(screen.staleResets == 1)
    }

    /// A wrong answer's timer re-enabled Enter while "Correct!" was still waiting to move on.
    @Test(arguments: Stage4AActivity.allCases)
    func earlierFeedbackTimerReopenedScoring(activity: Stage4AActivity) {
        let screen = oldScreen(activity)
        screen.answer = screen.question.wrongAnswers[0]
        screen.tapEnter()
        screen.wait(activity.feedbackMilliseconds - 100)
        screen.answer = screen.question.rightAnswer
        screen.pressReturn()
        screen.wait(100)
        screen.tapEnter()
        #expect(screen.points == 2)
    }

    /// With Remove Ads every tap on Skip scheduled another next question.
    @Test(arguments: Stage4AActivity.allCases)
    func skipTappedTwiceMovedOnTwice(activity: Stage4AActivity) {
        let screen = oldScreen(activity)
        answerWrongTwice(screen)
        screen.tapSkip()
        screen.tapSkip()
        #expect(screen.pendingResets == 2)
        screen.wait(drain)
        #expect(screen.questionNumber == 3)
    }

    /// Skip stayed on screen after a correct answer, so the activity moved on twice.
    @Test(arguments: Stage4AActivity.allCases)
    func correctAnswerThenSkipMovedOnTwice(activity: Stage4AActivity) {
        let screen = oldScreen(activity)
        answerWrongTwice(screen)
        screen.answer = screen.question.rightAnswer
        screen.pressReturn()
        #expect(screen.isSkipShowing)
        screen.tapSkip()
        #expect(screen.pendingResets == 2)
        screen.wait(drain)
        #expect(screen.questionNumber == 3)
    }

    /// A wrong answer pressed during the transition replaced "Correct!" and counted as a wrong attempt.
    @Test(arguments: Stage4AActivity.allCases)
    func wrongAnswerDuringTheTransitionCounted(activity: Stage4AActivity) {
        let screen = oldScreen(activity)
        screen.answer = screen.question.rightAnswer
        screen.pressReturn()
        screen.answer = screen.question.wrongAnswers[0]
        screen.pressReturn()
        #expect(screen.message != "Correct!")
        #expect(screen.wrongAttempts == 1)
    }

    /// Geometry appearing again mid-transition moved on at once, and the pending reset moved on again.
    @Test func geometryAppearingAgainMovedOnTwice() {
        let screen = oldScreen(.year4Geometry)
        screen.answer = screen.question.rightAnswer
        screen.tapEnter()
        screen.wait(500)
        screen.appear()
        #expect(screen.questionNumber == 2)
        screen.wait(drain)
        #expect(screen.questionNumber == 3)
        #expect(screen.staleResets == 1)
    }
}

// MARK: - The views themselves

private enum Stage4ASourceError: Error {
    case missing(String)
}

/// ContentView.swift, read from the source tree so the views' own code is checked for the wiring
/// the timeline tests model. The tests are skipped if the source isn't reachable.
private enum Stage4ASource {
    static let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Maths Quest")
        .appendingPathComponent("ContentView.swift")

    static var isAvailable: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    static let activityViews = [
        "Year1CountingView", "Year1AdditionView", "Year1SubtractionView",
        "Year2MultiplicationView", "Year2DivisionView", "Year2ShapesView",
        "Year3FractionsView", "Year3MeasurementView", "Year3TimeView",
        "Year4DecimalsView", "Year4GeometryView", "Year4MoneyView",
        "Year5PercentagesView", "Year5StatisticsView", "Year5VolumeView",
        "Year6AlgebraView", "Year6ProbabilityView", "Year6RatiosView",
    ]

    static func source() throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    /// From `struct Name: View {` to its closing brace in the first column.
    static func body(of view: String, in source: String) throws -> String {
        guard let start = source.range(of: "\nstruct \(view): View {"),
              let end = source.range(of: "\n}\n", range: start.upperBound..<source.endIndex) else {
            throw Stage4ASourceError.missing(view)
        }
        return String(source[start.lowerBound..<end.upperBound])
    }

    /// Each `opening` up to the brace that closes the first brace after it.
    static func block(startingWith opening: String, in text: String) -> [String] {
        var blocks = [String]()
        var searchFrom = text.startIndex
        while let start = text.range(of: opening, range: searchFrom..<text.endIndex),
              let brace = text[start.lowerBound...].firstIndex(of: "{") {
            var depth = 0
            var index = brace
            repeat {
                if text[index] == "{" { depth += 1 }
                if text[index] == "}" { depth -= 1 }
                index = text.index(after: index)
            } while depth > 0 && index < text.endIndex
            blocks.append(String(text[start.lowerBound..<index]))
            searchFrom = index
        }
        return blocks
    }

    static func lines(of text: String) -> [String] {
        text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("//") }
    }

    static func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }
}

@Suite(.enabled(if: Stage4ASource.isAvailable, "ContentView.swift isn't reachable from this test run"))
struct Stage4AViewWiringTests {
    /// The list below is every activity screen in the app, not counting the year menus.
    @Test func everyActivityViewIsChecked() throws {
        let source = try Stage4ASource.source()
        let views = try Regex(#"\nstruct (Year\d\w+View): View \{"#)
        let names = source.matches(of: views).compactMap { $0.output[1].substring.map(String.init) }
        let activities = names.filter { $0.range(of: #"^Year\dView$"#, options: .regularExpression) == nil }
        #expect(Set(activities) == Set(Stage4ASource.activityViews))
        #expect(activities.count == 18)
    }

    /// The old per-view counters are gone and Skip is shown by QuestionProgress.
    @Test(arguments: Stage4ASource.activityViews)
    func viewKeepsItsProgressInQuestionProgress(view: String) throws {
        let body = try Stage4ASource.body(of: view, in: Stage4ASource.source())
        #expect(body.contains("@State private var progress = QuestionProgress()"))
        #expect(Stage4ASource.count("wrongAttempts", in: body) == Stage4ASource.count("progress.wrongAttempts", in: body))
        #expect(!body.contains("showSkipButton ="))
        #expect(!body.contains("var showSkipButton"))
        #expect(Stage4ASource.count("if progress.showSkipButton {", in: body) == 1)
        #expect(Stage4ASource.block(startingWith: "private func resetQuestion() {", in: body).first?.contains("progress.reset()") == true)
    }

    /// The four activities that show a worked solution after Skip (Stage 9C Batch 1).
    static let workedSolutionViews: Set = ["Year2MultiplicationView", "Year2DivisionView", "Year4GeometryView",
                                           "Year6RatiosView"]

    /// The Skip reward is turned down unless the question can still be skipped.
    ///
    /// Updated deliberately in Stage 9C: in the four activities with worked solutions, the reward shows the solution
    /// (`showSolution()`) and Next Question moves on, instead of `gameData.skipQuestion(resetQuestion:)`. The reward is
    /// still recorded once, behind the same guard. The other 14 activities are checked as before.
    @Test(arguments: Stage4ASource.activityViews)
    func skipRewardIsRecordedBeforeMovingOn(view: String) throws {
        let lines = Stage4ASource.lines(of: try Stage4ASource.body(of: view, in: Stage4ASource.source()))
        let showsSolution = Self.workedSolutionViews.contains(view)
        let skips = lines.indices.filter {
            showsSolution ? lines[$0] == "showSolution()" : lines[$0].hasPrefix("gameData.skipQuestion(")
        }
        #expect(skips.count == 1)
        for index in skips {
            #expect(lines[index - 1] == "guard progress.recordSkip() else { return }")
        }
        #expect(lines.filter { $0.contains("recordSkip()") }.count == 1)
        if showsSolution {
            #expect(!lines.contains { $0.contains("skipQuestion(") })
        }
    }

    /// Enter and Return do nothing once the question is answered or skipped, and every point is
    /// behind recordCorrectAnswer() or the .correct case of recordSubmission(isCorrect:).
    @Test(arguments: Stage4ASource.activityViews)
    func everyPointIsGatedByQuestionProgress(view: String) throws {
        let body = try Stage4ASource.body(of: view, in: Stage4ASource.source())
        let checkAnswer = try #require(Stage4ASource.block(startingWith: "private func checkAnswer() {", in: body).first)
        let lines = Stage4ASource.lines(of: checkAnswer)
        let scores = Stage4ASource.count("gameData.points += 1", in: body)
        #expect(scores >= 1)

        if checkAnswer.contains("progress.recordSubmission(isCorrect:") {
            let ignored = try #require(lines.firstIndex(of: "case .ignored:"))
            #expect(lines[ignored + 1] == "return")
            let correct = try #require(lines.firstIndex(of: "case .correct:"))
            let incorrect = try #require(lines.firstIndex(of: "case .incorrect:"))
            let correctCase = lines[correct..<incorrect]
            #expect(scores == 1)
            if !correctCase.contains("gameData.points += 1") {
                // Fractions scores in correctResponse(), called only from the .correct case.
                let helpers = correctCase.compactMap { $0.firstMatch(of: #/(\w+)\(\)$/#).map { String($0.1) } }
                let helper = try #require(helpers.first)
                let calls = try Regex(#"\b"# + helper + #"\(\)"#)
                #expect(body.matches(of: calls).count == 2, "declared once and called once")
                let helperBody = try #require(Stage4ASource.block(startingWith: "private func \(helper)()", in: body).first)
                #expect(helperBody.contains("gameData.points += 1"))
            }
        } else {
            #expect(lines.dropFirst().first == "guard !progress.isAdvancing else { return }")
            let guards = lines.indices.filter { lines[$0] == "guard progress.recordCorrectAnswer() else { return }" }
            let points = lines.indices.filter { lines[$0] == "gameData.points += 1" }
            #expect(guards.count == scores)
            #expect(points.count == scores)
            for point in points {
                let gate = lines[..<point].lastIndex {
                    $0 == "guard progress.recordCorrectAnswer() else { return }" || $0.hasPrefix("}") ||
                        $0.hasPrefix("case ") || $0.hasPrefix("if ") || $0.hasPrefix("default") || $0 == "gameData.points += 1"
                }
                #expect(gate.map { lines[$0] } == "guard progress.recordCorrectAnswer() else { return }", "\(view) line \(point)")
            }
        }
    }

    /// The next question comes only from the reset scheduled by a score, from Skip, or from an
    /// .onAppear that first checks the question isn't already moving on.
    ///
    /// Updated deliberately in Stage 9C: in the four activities with worked solutions, the question after a Skip comes
    /// from Next Question instead of `gameData.skipQuestion(resetQuestion:)`. Next Question is the only caller of
    /// `nextQuestion()`, which moves on only while a solution is showing, and `resetQuestion()` clears the solution, so
    /// a second tap does nothing. Every other check is unchanged.
    @Test(arguments: Stage4ASource.activityViews)
    func nextQuestionComesOncePerScoreOrSkip(view: String) throws {
        let body = try Stage4ASource.body(of: view, in: Stage4ASource.source())
        let scheduled = try Regex(#"asyncAfter\(deadline: \.now\(\) \+ [0-9.]+\) \{\s*resetQuestion\(\)\s*\}"#)
        let scheduledResets = body.matches(of: scheduled).count
        let calls = Stage4ASource.count("resetQuestion()", in: body) - Stage4ASource.count("func resetQuestion()", in: body)
        #expect(scheduledResets == Stage4ASource.count("gameData.points += 1", in: body))

        var onAppearResets = 0
        for block in Stage4ASource.block(startingWith: ".onAppear {", in: body) where block.contains("resetQuestion()") {
            let lines = Stage4ASource.lines(of: block)
            let guardLine = lines.firstIndex(of: "guard !progress.isAdvancing else { return }")
            let resetLine = lines.firstIndex(of: "resetQuestion()")
            #expect(guardLine != nil && resetLine != nil && guardLine! < resetLine!, "\(view) .onAppear")
            onAppearResets += Stage4ASource.count("resetQuestion()", in: block)
        }
        guard Self.workedSolutionViews.contains(view) else {
            #expect(calls == scheduledResets + onAppearResets)
            #expect(Stage4ASource.count("skipQuestion(resetQuestion: resetQuestion)", in: body) == 1)
            return
        }
        #expect(Stage4ASource.count("skipQuestion(", in: body) == 0)
        let next = try #require(Stage4ASource.block(startingWith: "private func nextQuestion() {", in: body).first)
        #expect(Stage4ASource.lines(of: next) == ["private func nextQuestion() {", "guard solution != nil else { return }",
                                                  "resetQuestion()", "}"])
        #expect(Stage4ASource.count("nextQuestion", in: body) == 2, "declared once, and Next Question's action")
        #expect(body.contains("NextQuestionButton(action: nextQuestion)"))
        let reset = try #require(Stage4ASource.block(startingWith: "private func resetQuestion() {", in: body).first)
        #expect(reset.contains("solution = nil"))
        let show = try #require(Stage4ASource.block(startingWith: "private func showSolution() {", in: body).first)
        #expect(!show.contains("resetQuestion()"))
        #expect(calls == scheduledResets + onAppearResets + 1)
    }
}
