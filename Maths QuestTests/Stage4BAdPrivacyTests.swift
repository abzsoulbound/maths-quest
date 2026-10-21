//
//  Stage4BAdPrivacyTests.swift
//  Maths QuestTests
//
//  Stage 4B: advertising and privacy for a primary-school audience. The request settings are
//  checked on a real RequestConfiguration and on a recorder that logs every call in order. That
//  shows the privacy settings are in place before Google Mobile Ads starts and before any ad
//  request. The interstitial schedule and the Skip prompt are pure state. As in Stage 4A, the
//  wiring in ContentView.swift is checked in the source. Nothing here loads or shows an ad, and
//  Debug builds only know Google's test ad units.
//

import Foundation
import GoogleMobileAds
import Testing
@testable import Maths_Quest

// MARK: - Child-directed request settings

private final class CallLog {
    var entries: [String] = []
}

/// Records each privacy setting in the order AdPrivacy makes it.
private final class RecordingConfiguration: AdRequestConfiguring {
    let log: CallLog
    private(set) var firstPartyIDEnabled: Bool?

    init(log: CallLog = CallLog()) {
        self.log = log
    }

    var tagForChildDirectedTreatment: NSNumber? {
        didSet { log.entries.append("childDirected") }
    }

    var tagForUnderAgeOfConsent: NSNumber? {
        didSet { log.entries.append("underAgeOfConsent") }
    }

    var maxAdContentRating: GADMaxAdContentRating? {
        didSet { log.entries.append("maxAdContentRating") }
    }

    var publisherPrivacyPersonalizationState: PublisherPrivacyPersonalizationState = .default {
        didSet { log.entries.append("personalisation") }
    }

    func setPublisherFirstPartyIDEnabled(_ enabled: Bool) {
        firstPartyIDEnabled = enabled
        log.entries.append("firstPartyID")
    }
}

private let privacySettings: Set<String> = [
    "childDirected", "underAgeOfConsent", "maxAdContentRating", "personalisation", "firstPartyID",
]

struct Stage4BAdPrivacySettingsTests {
    /// Child treatment: the app is treated as child-directed, which turns off personalised ads,
    /// remarketing and third-party ad vendors.
    @Test func requestsAreTreatedAsChildDirected() {
        let configuration = RequestConfiguration()
        AdPrivacy.apply(to: configuration)
        #expect(configuration.tagForChildDirectedTreatment?.boolValue == true)
        // Google says not to set this alongside child-directed treatment.
        #expect(configuration.tagForUnderAgeOfConsent == nil)
    }

    @Test func adsAreLimitedToRatingG() {
        let configuration = RequestConfiguration()
        AdPrivacy.apply(to: configuration)
        #expect(configuration.maxAdContentRating == .general)
    }

    @Test func adsAreNonPersonalised() {
        let configuration = RequestConfiguration()
        AdPrivacy.apply(to: configuration)
        #expect(configuration.publisherPrivacyPersonalizationState == .disabled)
    }

    @Test func thePublisherFirstPartyIDIsTurnedOff() {
        let configuration = RecordingConfiguration()
        AdPrivacy.apply(to: configuration)
        #expect(configuration.firstPartyIDEnabled == false)
    }

    /// Whatever was set before, AdPrivacy leaves only the child-safe values.
    @Test func looserSettingsAreReplaced() {
        let configuration = RecordingConfiguration()
        configuration.tagForChildDirectedTreatment = false
        configuration.tagForUnderAgeOfConsent = true
        configuration.maxAdContentRating = .matureAudience
        configuration.publisherPrivacyPersonalizationState = .enabled
        configuration.setPublisherFirstPartyIDEnabled(true)

        AdPrivacy.apply(to: configuration)

        #expect(configuration.tagForChildDirectedTreatment?.boolValue == true)
        #expect(configuration.tagForUnderAgeOfConsent == nil)
        #expect(configuration.maxAdContentRating == .general)
        #expect(configuration.publisherPrivacyPersonalizationState == .disabled)
        #expect(configuration.firstPartyIDEnabled == false)
    }

    /// ageRestrictedTreatment arrived in Google Mobile Ads 13.3.0. While the app links 12.x,
    /// tagForChildDirectedTreatment is the supported way to ask for child treatment. If this fails
    /// after an SDK upgrade, move AdPrivacy to ageRestrictedTreatment = .child.
    @MainActor
    @Test func theLinkedSDKUsesTagForChildDirectedTreatmentForChildren() {
        #expect(MobileAds.shared.isSDKVersionAtLeast(major: 12, minor: 0, patch: 0))
        #expect(!MobileAds.shared.isSDKVersionAtLeast(major: 13, minor: 3, patch: 0))
    }
}

// MARK: - Order: privacy settings, then SDK start, then the first ad request

@MainActor
struct Stage4BAdSDKOrderTests {
    private func makeSDK() -> (AdSDK, CallLog, RecordingConfiguration) {
        let log = CallLog()
        let configuration = RecordingConfiguration(log: log)
        let sdk = AdSDK(configuration: configuration, startSDK: { log.entries.append("start") })
        return (sdk, log, configuration)
    }

    @Test func nothingHappensUntilTheFirstRequest() {
        let (sdk, log, _) = makeSDK()
        #expect(!sdk.isStarted)
        #expect(log.entries.isEmpty)
    }

    /// Google asks for the request configuration to be set before the SDK is initialised.
    @Test func everyPrivacySettingIsAppliedBeforeTheSDKStarts() throws {
        let (sdk, log, _) = makeSDK()
        _ = sdk.makeRequest()
        let start = try #require(log.entries.firstIndex(of: "start"))
        #expect(Set(log.entries[..<start]) == privacySettings)
        #expect(log.entries.count == privacySettings.count + 1)
        #expect(sdk.isStarted)
    }

    /// The SDK starts once. Every later request applies the settings again before it's made.
    @Test func theSDKStartsOnceAndEveryRequestReappliesPrivacy() {
        let (sdk, log, configuration) = makeSDK()
        for request in 1...3 {
            log.entries.removeAll()
            _ = sdk.makeRequest()
            #expect(Set(log.entries.filter { $0 != "start" }) == privacySettings)
            #expect(log.entries.contains("start") == (request == 1))
            #expect(configuration.tagForChildDirectedTreatment?.boolValue == true)
        }
    }

    /// The app's real shared configuration once the app has made a request. In Debug this starts
    /// the SDK but loads no ad.
    @Test func theAppsSharedConfigurationIsChildSafe() {
        _ = AdSDK.shared.makeRequest()
        let configuration = MobileAds.shared.requestConfiguration
        #expect(AdSDK.shared.isStarted)
        #expect(configuration.tagForChildDirectedTreatment?.boolValue == true)
        #expect(configuration.tagForUnderAgeOfConsent == nil)
        #expect(configuration.maxAdContentRating == .general)
        #expect(configuration.publisherPrivacyPersonalizationState == .disabled)
    }
}

// MARK: - Test and production ad units

struct Stage4BAdUnitTests {
    /// Unit tests run the Debug build, so this is what simulator and test runs request.
    @Test func debugBuildsUseGoogleTestUnits() {
        #expect(AdUnitIDs.isDebugBuild)
        #expect(AdUnitIDs.current == AdUnitIDs.googleTest)
    }

    /// Google's published sample units for these two formats.
    @Test func googleTestUnitsAreGooglesSamples() {
        #expect(AdUnitIDs.googleTest.interstitial == "ca-app-pub-3940256099942544/4411468910")
        #expect(AdUnitIDs.googleTest.rewardedInterstitial == "ca-app-pub-3940256099942544/6978759866")
    }

    @Test func releaseBuildsUseTheAppsOwnUnits() throws {
        #expect(AdUnitIDs.forBuild(isDebug: true) == AdUnitIDs.googleTest)
        let release = AdUnitIDs.forBuild(isDebug: false)
        #expect(release == AdUnitIDs.production)

        // The production units belong to the AdMob account whose app ID is in Info.plist.
        let appID = try #require(Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String)
        let publisher = try #require(appID.components(separatedBy: "~").first)
        #expect(release.interstitial.hasPrefix(publisher + "/"))
        #expect(release.rewardedInterstitial.hasPrefix(publisher + "/"))

        let test = Set([AdUnitIDs.googleTest.interstitial, AdUnitIDs.googleTest.rewardedInterstitial])
        #expect(test.isDisjoint(with: [release.interstitial, release.rewardedInterstitial]))
    }
}

// MARK: - When the interstitial may appear

struct Stage4BInterstitialScheduleTests {
    private let launch = Date(timeIntervalSinceReferenceDate: 0)

    private func at(_ seconds: TimeInterval) -> Date {
        launch.addingTimeInterval(seconds)
    }

    @Test func notInTheFirstThreeMinutes() {
        let schedule = InterstitialSchedule(appLaunched: launch)
        #expect(!schedule.canShowAtBreak(now: at(0), adsRemoved: false, adOnScreen: false))
        #expect(!schedule.canShowAtBreak(now: at(179), adsRemoved: false, adOnScreen: false))
        #expect(schedule.canShowAtBreak(now: at(180), adsRemoved: false, adOnScreen: false))
    }

    @Test func neverWhileAQuestionIsOnScreen() {
        var schedule = InterstitialSchedule(appLaunched: launch)
        let activity = UUID()
        schedule.questionScreenAppeared(activity)
        for minutes in [3.0, 10, 60, 600] {
            #expect(!schedule.canShowAtBreak(now: at(minutes * 60), adsRemoved: false, adOnScreen: false))
        }
        schedule.questionScreenDisappeared(activity)
        #expect(schedule.canShowAtBreak(now: at(600 * 60), adsRemoved: false, adOnScreen: false))
    }

    /// During a navigation push the next screen can appear before the last one disappears.
    @Test func overlappingActivitiesAllHaveToLeave() {
        var schedule = InterstitialSchedule(appLaunched: launch)
        let first = UUID()
        let second = UUID()
        schedule.questionScreenAppeared(first)
        schedule.questionScreenAppeared(second)
        schedule.questionScreenDisappeared(first)
        #expect(!schedule.canShowAtBreak(now: at(1000), adsRemoved: false, adOnScreen: false))
        schedule.questionScreenDisappeared(second)
        #expect(schedule.canShowAtBreak(now: at(1000), adsRemoved: false, adOnScreen: false))
    }

    /// A screen that reports appearing twice, such as after a Skip ad covers it, still leaves once.
    @Test func aRepeatedAppearanceIsCountedOnce() {
        var schedule = InterstitialSchedule(appLaunched: launch)
        let activity = UUID()
        schedule.questionScreenAppeared(activity)
        schedule.questionScreenAppeared(activity)
        schedule.questionScreenDisappeared(activity)
        #expect(schedule.questionScreens.isEmpty)
        #expect(schedule.canShowAtBreak(now: at(1000), adsRemoved: false, adOnScreen: false))
    }

    @Test func neverForRemoveAdsPurchasers() {
        let schedule = InterstitialSchedule(appLaunched: launch)
        for seconds in [0.0, 180, 3600, 86_400] {
            #expect(!schedule.canShowAtBreak(now: at(seconds), adsRemoved: true, adOnScreen: false))
        }
    }

    /// Covers both an ad on screen and the Skip prompt on screen.
    @Test func neverOverAnotherAd() {
        let schedule = InterstitialSchedule(appLaunched: launch)
        #expect(!schedule.canShowAtBreak(now: at(1000), adsRemoved: false, adOnScreen: true))
    }

    /// No back-to-back ads: three minutes have to pass after any full-screen ad, a Skip ad included.
    @Test func threeMinutesAfterAnyAdEnds() {
        var schedule = InterstitialSchedule(appLaunched: launch)
        schedule.fullScreenAdEnded(at: at(400))
        #expect(!schedule.canShowAtBreak(now: at(401), adsRemoved: false, adOnScreen: false))
        #expect(!schedule.canShowAtBreak(now: at(579), adsRemoved: false, adOnScreen: false))
        #expect(schedule.canShowAtBreak(now: at(580), adsRemoved: false, adOnScreen: false))
    }

    /// An hour of play: a question screen for 50 seconds, then a menu, again and again. Each ad
    /// lasts 30 seconds. Ads only come at a menu, never in the first three minutes, and never
    /// within three minutes of the last one ending.
    @Test func anHourOfPlayShowsAdsOnlyAtMenusAndNeverBackToBack() {
        var schedule = InterstitialSchedule(appLaunched: launch)
        var adStarts = [TimeInterval]()
        for cycle in 0..<60 {
            let start = TimeInterval(cycle * 60)
            let activity = UUID()
            schedule.questionScreenAppeared(activity)
            for second in stride(from: start, to: start + 50, by: 5) {
                #expect(!schedule.canShowAtBreak(now: at(second), adsRemoved: false, adOnScreen: false))
            }
            schedule.questionScreenDisappeared(activity)

            let menu = start + 51
            if schedule.canShowAtBreak(now: at(menu), adsRemoved: false, adOnScreen: false) {
                adStarts.append(menu)
                #expect(!schedule.canShowAtBreak(now: at(menu + 1), adsRemoved: false, adOnScreen: true))
                schedule.fullScreenAdEnded(at: at(menu + 30))
            }
        }
        #expect(!adStarts.isEmpty)
        #expect(adStarts.allSatisfy { $0 >= InterstitialSchedule.minimumInterval })
        for (previous, next) in zip(adStarts, adStarts.dropFirst()) {
            #expect(next - (previous + 30) >= InterstitialSchedule.minimumInterval)
        }
        #expect(adStarts.count <= 3600 / Int(InterstitialSchedule.minimumInterval + 30) + 1)
    }

    @Test func theMenuSettlesBeforeAnAd() {
        #expect(InterstitialSchedule.settleDelay > 0.5)
        #expect(InterstitialSchedule.settleDelay < 2)
    }
}

// MARK: - Skip Question

struct Stage4BSkipAdTests {
    private static let flags = [false, true]

    @Test func purchasersSkipWithNoAdAndNoPrompt() {
        for adOnScreen in Self.flags {
            for asking in Self.flags {
                for ready in Self.flags {
                    #expect(SkipAdStep.onTap(adsRemoved: true, adOnScreen: adOnScreen, askingToWatch: asking, adReady: ready)
                            == .skipWithoutAd)
                }
            }
        }
    }

    /// The child is always asked first. A tap never plays the ad by itself.
    @Test func aTapAsksBeforeAnyAdPlays() {
        #expect(SkipAdStep.onTap(adsRemoved: false, adOnScreen: false, askingToWatch: false, adReady: true) == .askToWatchAd)
        for removed in Self.flags {
            for adOnScreen in Self.flags {
                for asking in Self.flags {
                    for ready in Self.flags {
                        let step = SkipAdStep.onTap(adsRemoved: removed, adOnScreen: adOnScreen,
                                                    askingToWatch: asking, adReady: ready)
                        #expect(step != .showAd)
                    }
                }
            }
        }
    }

    /// Repeated taps while the prompt or an ad is up do nothing, so a second ad can't be queued.
    @Test func repeatedTapsAreIgnored() {
        #expect(SkipAdStep.onTap(adsRemoved: false, adOnScreen: false, askingToWatch: true, adReady: true) == .ignore)
        #expect(SkipAdStep.onTap(adsRemoved: false, adOnScreen: true, askingToWatch: false, adReady: true) == .ignore)
        #expect(SkipAdStep.onTap(adsRemoved: false, adOnScreen: true, askingToWatch: false, adReady: false) == .ignore)
    }

    /// Saying no never skips and never plays an ad. The child stays on the question.
    @Test func noThanksStaysOnTheQuestion() {
        for removed in Self.flags {
            for adOnScreen in Self.flags {
                for ready in Self.flags {
                    #expect(SkipAdStep.onAnswer(watch: false, adsRemoved: removed, adOnScreen: adOnScreen, adReady: ready)
                            == .stay)
                }
            }
        }
    }

    @Test func watchAdPlaysTheAdOnlyIfItIsStillReady() {
        #expect(SkipAdStep.onAnswer(watch: true, adsRemoved: false, adOnScreen: false, adReady: true) == .showAd)
        // The ad expired or was used while the prompt was up.
        #expect(SkipAdStep.onAnswer(watch: true, adsRemoved: false, adOnScreen: false, adReady: false) == .adNotReady)
        #expect(SkipAdStep.onAnswer(watch: true, adsRemoved: false, adOnScreen: true, adReady: true) == .ignore)
        #expect(SkipAdStep.onAnswer(watch: true, adsRemoved: true, adOnScreen: false, adReady: false) == .skipWithoutAd)
    }
}

// MARK: - Ad loading and load failures

struct Stage4BAdLoadingTests {
    @Test func adsAreNeverRequestedForPurchasers() {
        for adOnScreen in [false, true] {
            for loading in [false, true] {
                for fresh in [false, true] {
                    #expect(!AdManager.shouldLoad(adsRemoved: true, adOnScreen: adOnScreen, isLoading: loading, hasFreshAd: fresh))
                }
            }
        }
    }

    /// One request at a time. None while an ad is on screen, and none while a fresh ad is waiting.
    @Test func noDuplicateRequests() {
        #expect(AdManager.shouldLoad(adsRemoved: false, adOnScreen: false, isLoading: false, hasFreshAd: false))
        #expect(!AdManager.shouldLoad(adsRemoved: false, adOnScreen: false, isLoading: true, hasFreshAd: false))
        #expect(!AdManager.shouldLoad(adsRemoved: false, adOnScreen: false, isLoading: false, hasFreshAd: true))
        #expect(!AdManager.shouldLoad(adsRemoved: false, adOnScreen: true, isLoading: false, hasFreshAd: false))
    }

    /// A failed load is retried four times, at 10, 20, 40 and 80 seconds, and then it stops.
    @Test func failedLoadsBackOffAndStop() {
        #expect(AdManager.maxLoadRetries == 4)
        let delays = (1...AdManager.maxLoadRetries).map(AdManager.retryDelay(forAttempt:))
        #expect(delays == [10, 20, 40, 80])
    }

    /// With no ad loaded, Skip says so and the question isn't skipped.
    @Test func noLoadedAdMeansNoSkip() {
        #expect(SkipAdStep.onTap(adsRemoved: false, adOnScreen: false, askingToWatch: false, adReady: false) == .adNotReady)
    }
}

// MARK: - Privacy manifest and personal data

struct Stage4BPrivacyManifestTests {
    private func manifest() throws -> [String: Any] {
        let url = try #require(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let data = try Data(contentsOf: url)
        return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    @Test func theAppDoesNotTrack() throws {
        let manifest = try manifest()
        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect((manifest["NSPrivacyTrackingDomains"] as? [String])?.isEmpty == true)
        #expect(Bundle.main.object(forInfoDictionaryKey: "NSUserTrackingUsageDescription") == nil)
    }

    /// The app's own UserDefaults use (settings and the Remove Ads cache) needs reason CA92.1.
    @Test func userDefaultsHasItsRequiredReason() throws {
        let types = try #require(try manifest()["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let userDefaults = try #require(types.first {
            $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults"
        })
        #expect(userDefaults["NSPrivacyAccessedAPITypeReasons"] as? [String] == ["CA92.1"])
    }

    /// Feedback text is the only data the app itself sends. It isn't linked to the child or used for tracking.
    @Test func feedbackIsDeclaredAsUnlinkedUserContent() throws {
        let collected = try #require(try manifest()["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        #expect(collected.count == 1)
        let feedback = try #require(collected.first)
        #expect(feedback["NSPrivacyCollectedDataType"] as? String == "NSPrivacyCollectedDataTypeOtherUserContent")
        #expect(feedback["NSPrivacyCollectedDataTypeLinked"] as? Bool == false)
        #expect(feedback["NSPrivacyCollectedDataTypeTracking"] as? Bool == false)
        #expect(feedback["NSPrivacyCollectedDataTypePurposes"] as? [String] == ["NSPrivacyCollectedDataTypePurposeAppFunctionality"])
    }

    @MainActor
    @Test func feedbackAsksChildrenNotToShareAboutThemselves() {
        let reminder = FeedbackView.privacyReminder.lowercased()
        #expect(reminder.contains("name"))
        #expect(reminder.contains("school"))
        #expect(reminder.contains("address"))
    }
}

// MARK: - The wiring in ContentView.swift

private enum Stage4BSourceError: Error {
    case missing(String)
}

private enum Stage4BSource {
    static let appFolder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Maths Quest")

    static let url = appFolder.appendingPathComponent("ContentView.swift")

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

    static let menuViews = ["MainMenuView", "Year1View", "Year2View", "Year3View", "Year4View", "Year5View", "Year6View"]

    static let formViews = ["FeedbackView", "SettingsView", "RemoveAdsView", "ShopView", "InformationView", "NoInternetView"]

    static func source() throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    /// Every Swift file in the app target.
    static func appSources() throws -> String {
        let files = try FileManager.default.contentsOfDirectory(at: appFolder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        return try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
    }

    /// From `opening` at the start of a line to the next closing brace in the first column.
    static func topLevel(_ opening: String, in source: String) throws -> String {
        guard let start = source.range(of: "\n" + opening),
              let end = source.range(of: "\n}\n", range: start.upperBound..<source.endIndex) else {
            throw Stage4BSourceError.missing(opening)
        }
        return String(source[start.lowerBound..<end.upperBound])
    }

    static func view(_ name: String, in source: String) throws -> String {
        try topLevel("struct \(name): View {", in: source)
    }

    /// `opening` up to the brace that closes the first brace after it.
    static func block(_ opening: String, in text: String) throws -> String {
        guard let start = text.range(of: opening),
              var index = text[start.lowerBound...].firstIndex(of: "{") else {
            throw Stage4BSourceError.missing(opening)
        }
        var depth = 0
        repeat {
            if text[index] == "{" { depth += 1 }
            if text[index] == "}" { depth -= 1 }
            index = text.index(after: index)
        } while depth > 0 && index < text.endIndex
        return String(text[start.lowerBound..<index])
    }

    static func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    static func position(of needle: String, in text: String) throws -> String.Index {
        guard let range = text.range(of: needle) else { throw Stage4BSourceError.missing(needle) }
        return range.lowerBound
    }
}

@Suite(.enabled(if: Stage4BSource.isAvailable, "ContentView.swift isn't reachable from this test run"))
struct Stage4BAdWiringTests {
    /// The only `Request()` in the app is in AdSDK.makeRequest(), after the privacy settings and the SDK start.
    @Test func everyAdRequestIsMadeAfterThePrivacySettings() throws {
        let source = try Stage4BSource.source()
        #expect(source.matches(of: #/[^A-Za-z]Request\(\)/#).count == 1)

        let makeRequest = try Stage4BSource.block("func makeRequest() -> Request", in: try Stage4BSource.topLevel("final class AdSDK", in: source))
        let privacy = try Stage4BSource.position(of: "AdPrivacy.apply(to: configuration)", in: makeRequest)
        let start = try Stage4BSource.position(of: "startSDK()", in: makeRequest)
        let request = try Stage4BSource.position(of: "return Request()", in: makeRequest)
        #expect(privacy < start)
        #expect(start < request)
    }

    /// Both ad loads check shouldLoad first, so purchasers never reach the SDK. They then use a request from AdSDK.
    @Test func adLoadsUseAdSDKRequestsAndStopForPurchasers() throws {
        let source = try Stage4BSource.source()
        let manager = try Stage4BSource.topLevel("class AdManager: NSObject, FullScreenContentDelegate {", in: source)
        #expect(Stage4BSource.count(".load(with:", in: source) == 2)
        #expect(Stage4BSource.count("AdSDK.shared.makeRequest()", in: source) == 2)
        for name in ["func loadInterstitialAd()", "func loadRewardedInterstitialAd()"] {
            let load = try Stage4BSource.block(name, in: manager)
            let guardLine = try Stage4BSource.position(of: "guard Self.shouldLoad(adsRemoved: adsRemoved", in: load)
            let makeRequest = try Stage4BSource.position(of: "let request = AdSDK.shared.makeRequest()", in: load)
            let loadCall = try Stage4BSource.position(of: ".load(with:", in: load)
            #expect(guardLine < makeRequest)
            #expect(makeRequest < loadCall)
            #expect(load.contains("request: request)"))
        }
    }

    /// AdManager takes its units from AdUnitIDs, and the production IDs are written only once.
    @Test func adUnitsComeFromAdUnitIDs() throws {
        let source = try Stage4BSource.source()
        let manager = try Stage4BSource.topLevel("class AdManager: NSObject, FullScreenContentDelegate {", in: source)
        #expect(manager.contains("AdUnitIDs.current.interstitial"))
        #expect(manager.contains("AdUnitIDs.current.rewardedInterstitial"))
        #expect(!manager.contains("ca-app-pub-"))
        #expect(Stage4BSource.count(AdUnitIDs.production.interstitial, in: source) == 1)
        #expect(Stage4BSource.count(AdUnitIDs.production.rewardedInterstitial, in: source) == 1)
    }

    /// No IDFA, no App Tracking Transparency and no consent form anywhere in the app.
    @Test func noTrackingOrAdultConsentPrompt() throws {
        let sources = try Stage4BSource.appSources()
        for banned in ["AppTrackingTransparency", "ATTrackingManager", "AdSupport", "ASIdentifierManager",
                       "advertisingIdentifier", "UserMessagingPlatform", "ConsentInformation", "ConsentForm"] {
            #expect(!sources.contains(banned), "\(banned) found in the app")
        }
    }

    /// Every activity reports itself, so an interstitial can't appear over a question.
    @Test(arguments: Stage4BSource.activityViews)
    func activityScreensBlockTheInterstitial(view: String) throws {
        let body = try Stage4BSource.view(view, in: try Stage4BSource.source())
        #expect(Stage4BSource.count(".questionScreen()", in: body) == 1)
        #expect(!body.contains(".adBreakPoint()"))
    }

    /// The interstitial can only be offered when a menu appears.
    @Test(arguments: Stage4BSource.menuViews)
    func menusAreTheOnlyAdBreaks(view: String) throws {
        let body = try Stage4BSource.view(view, in: try Stage4BSource.source())
        #expect(Stage4BSource.count(".adBreakPoint()", in: body) == 1)
        #expect(!body.contains(".questionScreen()"))
    }

    @Test(arguments: Stage4BSource.formViews)
    func formsAndSettingsNeverShowAds(view: String) throws {
        let body = try Stage4BSource.view(view, in: try Stage4BSource.source())
        #expect(!body.contains(".adBreakPoint()"))
        #expect(!body.contains("AdManager"))
    }

    /// No timer or other path shows an interstitial: one call site, in AdBreakPoint, and every
    /// full-screen ad is presented by AdManager.
    @Test func theInterstitialHasOneEntryPoint() throws {
        let source = try Stage4BSource.source()
        #expect(Stage4BSource.count(".adBreakPoint()", in: source) == Stage4BSource.menuViews.count)
        #expect(Stage4BSource.count(".questionScreen()", in: source) == Stage4BSource.activityViews.count)
        #expect(Stage4BSource.count("AdManager.shared.showInterstitialAtBreak()", in: source) == 1)
        let breakPoint = try Stage4BSource.topLevel("private struct AdBreakPoint: ViewModifier {", in: source)
        #expect(breakPoint.contains("AdManager.shared.showInterstitialAtBreak()"))
        #expect(breakPoint.contains("if isOnScreen"))
        #expect(!source.contains("adTimer"))
        #expect(!source.contains("showInterstitialAd(from"))

        let manager = try Stage4BSource.topLevel("class AdManager: NSObject, FullScreenContentDelegate {", in: source)
        #expect(Stage4BSource.count("ad.present(from:", in: source) == 2)
        #expect(Stage4BSource.count("ad.present(from:", in: manager) == 2)

        let atBreak = try Stage4BSource.block("func showInterstitialAtBreak()", in: manager)
        #expect(atBreak.contains("schedule.canShowAtBreak(now: Date(), adsRemoved: adsRemoved"))
        #expect(atBreak.contains("adOnScreen: presentedAd != nil || isAskingToWatchSkipAd"))
        let dismissed = try Stage4BSource.block("func adDidDismissFullScreenContent", in: manager)
        #expect(dismissed.contains("schedule.fullScreenAdEnded(at: Date())"))
    }

    /// The Skip ad plays only from the "Watch ad" answer. The reward, which skips the question,
    /// comes only from the ad's reward handler or a Remove Ads purchase, never from a failure.
    @Test func theSkipAdPlaysOnlyAfterTheChildChoosesIt() throws {
        let source = try Stage4BSource.source()
        let manager = try Stage4BSource.topLevel("class AdManager: NSObject, FullScreenContentDelegate {", in: source)

        let tap = try Stage4BSource.block("func showRewardedInterstitialAd(from", in: manager)
        #expect(!tap.contains("ad.present"))
        #expect(tap.contains("SkipAdStep.onTap("))

        let prompt = try Stage4BSource.block("private func askToWatchSkipAd(from", in: manager)
        #expect(prompt.contains(#"UIAlertAction(title: "No thanks", style: .cancel)"#))
        #expect(prompt.contains(#"UIAlertAction(title: "Watch ad", style: .default)"#))
        #expect(prompt.contains("watch a short video ad"))
        #expect(prompt.contains("isAskingToWatchSkipAd = true"))

        let answer = try Stage4BSource.block("private func answerSkipAdQuestion(watch", in: manager)
        #expect(answer.contains("isAskingToWatchSkipAd = false"))
        let showAd = try Stage4BSource.position(of: "case .showAd:", in: answer)
        let present = try Stage4BSource.position(of: "ad.present(from: topViewController(from: viewController))", in: answer)
        let nextCase = try Stage4BSource.position(of: "case .ignore, .askToWatchAd, .stay:", in: answer)
        #expect(showAd < present)
        #expect(present < nextCase)

        #expect(Stage4BSource.count("onRewardEarned()", in: manager) == 3)
        let failed = try Stage4BSource.block("didFailToPresentFullScreenContentWithError", in: manager)
        #expect(!failed.contains("onRewardEarned"))
        #expect(failed.contains("the question wasn't skipped"))
    }

    /// The feedback screen shows the reminder. The Firestore payload is still only the text and a
    /// timestamp, the shape the rules allow, with nothing that identifies the child.
    @Test func feedbackShowsTheReminderAndKeepsItsShape() throws {
        let body = try Stage4BSource.view("FeedbackView", in: try Stage4BSource.source())
        #expect(body.contains("Text(FeedbackView.privacyReminder)"))
        let compact = body.filter { !$0.isWhitespace }
        #expect(compact.contains(#"letfeedbackData:[String:Any]=["text":feedbackText,"timestamp":Timestamp()]"#))
        #expect(compact.contains("addDocument(data:feedbackData)"))
        #expect(Stage4BSource.count("addDocument(", in: body) == 1)
    }
}
